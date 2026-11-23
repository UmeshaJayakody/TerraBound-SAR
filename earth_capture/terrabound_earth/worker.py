"""Long jobs, one at a time in the background: preparing areas, making SAR images, suggesting
places and exporting the dataset. The app polls `state` to show progress."""
from __future__ import annotations

import collections
import datetime as dt
import threading
import traceback

from . import dataset, suggest as suggest_mod
from .matlab_bridge import MatlabNotFound, MatlabRun
from .scene import build_scene
from .sources.http import SourceError
from .store import Store
from .views import plan


class Worker:
    def __init__(self, store: Store):
        self.store = store
        self.lock = threading.Lock()
        self.thread: threading.Thread | None = None
        self.stop_flag = threading.Event()
        self.task = ""            # what it is doing, in words
        self.item = ""            # the area it is on
        self.progress = [0, 0]    # views done, views planned (current area)
        self.last_result: dict = {}
        self.log_lines: collections.deque = collections.deque(maxlen=400)

    # ---- state ----------------------------------------------------------------------------------
    def log(self, text: str):
        stamp = dt.datetime.now().strftime("%H:%M:%S")
        for line in str(text).splitlines() or [""]:
            self.log_lines.append(f"{stamp}  {line}")

    @property
    def busy(self) -> bool:
        return self.thread is not None and self.thread.is_alive()

    def state(self) -> dict:
        return {"busy": self.busy, "task": self.task, "item": self.item, "progress": self.progress,
                "stopping": self.stop_flag.is_set() and self.busy, "log": list(self.log_lines)[-120:],
                "last_result": self.last_result}

    def _start(self, name: str, fn, *args) -> bool:
        with self.lock:
            if self.busy:
                return False
            self.stop_flag.clear()
            self.task = name
            self.last_result = {}

            def body():
                try:
                    fn(*args)
                except Exception as e:  # noqa: BLE001 -- report anything, keep the app alive
                    self.log(f"Error: {e}")
                    self.log(traceback.format_exc(limit=3))
                    self.last_result = {"ok": False, "error": str(e)}
                finally:
                    self.task, self.item, self.progress = "", "", [0, 0]

            self.thread = threading.Thread(target=body, daemon=True)
            self.thread.start()
            return True

    def stop(self):
        self.stop_flag.set()
        self.log("Stopping after the current step ...")

    # ---- jobs -----------------------------------------------------------------------------------
    def prepare(self, ids: list[str] | None) -> bool:
        return self._start("Preparing areas", self._run, ids, False)

    def run(self, ids: list[str] | None) -> bool:
        return self._start("Making SAR images", self._run, ids, True)

    def _pending(self, ids, with_sar: bool) -> list[str]:
        todo = []
        for it in self.store.snapshot():
            if ids and it["id"] not in ids:
                continue
            if it["status"] == "done" or (not with_sar and it["status"] == "ready"):
                continue
            todo.append(it["id"])
        return todo

    def _run(self, ids, with_sar: bool):
        todo = self._pending(ids, with_sar)
        self.log(f"{len(todo)} area(s) to {'make' if with_sar else 'prepare'}.")
        done = 0
        for item_id in todo:
            if self.stop_flag.is_set():
                break
            area = self.store.area(item_id)
            self.item = area.name
            # 1) the scene (needs the internet the first time)
            self.store.update(item_id, status="downloading", message="")
            try:
                build_scene(area, self.store.scene, log=self.log)
            except SourceError as e:
                self.store.update(item_id, status="waiting", message=str(e))
                self.log(f"{area.name}: data unavailable for now, will retry next time ({e})")
                continue
            except Exception as e:  # noqa: BLE001
                self.store.update(item_id, status="failed", message=str(e))
                self.log(f"{area.name}: {e}")
                continue
            self.store.update(item_id, status="ready")
            if not with_sar:
                done += 1
                continue
            # 2) the SAR images (all on this computer)
            vs = self.store.views
            views = plan(area, vs)
            self.progress = [0, len(views)]
            self.store.update(item_id, status="running", views_total=len(views), views_done=0)
            run = MatlabRun(area, views, vs)
            try:
                run.start()
            except MatlabNotFound as e:
                self.store.update(item_id, status="ready", message=str(e))
                self.log(str(e))
                break
            self.log(f"{area.name}: MATLAB started for {len(views)} views (first start takes a minute)")

            def on_event(e, item_id=item_id):
                kind = e.get("event")
                if kind == "progress":
                    self.log(f"  {e.get('text', '')}")
                elif kind == "view":
                    ok = e.get("status") == "done"
                    if ok:
                        self.progress[0] += 1
                    self.store.update(item_id, views_done=self.progress[0])
                    self.log(f"  view {e.get('i')}/{e.get('n')} {e.get('view')}: {e.get('status')} "
                             f"({float(e.get('seconds') or 0):.0f} s) {e.get('message') or ''}")
                elif kind == "error":
                    self.log(f"  MATLAB error: {e.get('message')}")

            res = run.wait(on_event=on_event, should_stop=self.stop_flag.is_set)
            views_out = res.get("views") or []
            n_ok = sum(1 for v in views_out if v.get("status") == "done")
            if self.stop_flag.is_set() and n_ok < len(views):
                status = "stopped"
            elif res.get("ok"):
                status = "done"
            elif n_ok:
                status = "partial"
            else:
                status = "failed"
            self.store.update(item_id, status=status, views_done=n_ok,
                              message=res.get("error") or "; ".join(res.get("notes") or []))
            self.log(f"{area.name}: {n_ok} of {len(views)} views made ({status})")
            done += 1
        self.last_result = {"ok": True, "areas": done}
        self.log("Finished." if not self.stop_flag.is_set() else "Stopped.")

    def suggest(self, kind: str, region, n: int, side_m: float, seed: int) -> bool:
        def job():
            self.item = suggest_mod.KINDS[kind].label
            self.log(f"Looking for {n} place(s): {suggest_mod.KINDS[kind].label} ...")
            found = suggest_mod.suggest(kind, region, n, side_m, seed, log=self.log, should_stop=self.stop_flag.is_set)
            added = 0
            for a in found:
                _, new = self.store.add(a)
                added += new
            self.last_result = {"ok": True, "added": added}
            self.log(f"Added {added} suggested place(s) to the queue.")
        return self._start("Suggesting places", job)

    def export(self, ids: list[str] | None, lr_size: str, out_dir: str | None) -> bool:
        def job():
            areas = [self.store.area(i) for i in ids] if ids else dataset.finished_areas()
            res = dataset.export(areas, out_dir or None, lr_size=lr_size, log=self.log)
            self.last_result = {"ok": True, "export": res}
        return self._start("Exporting the dataset", job)
