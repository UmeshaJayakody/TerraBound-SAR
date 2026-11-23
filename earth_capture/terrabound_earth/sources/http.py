"""HTTP with retries, polite identification and an on-disk cache of responses."""
from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .. import config

_session: requests.Session | None = None


class SourceError(RuntimeError):
    """A data source could not be reached or returned something unusable."""


def session() -> requests.Session:
    global _session
    if _session is None:
        s = requests.Session()
        retry = Retry(total=3, backoff_factor=1.0, status_forcelist=(429, 500, 502, 503, 504),
                      allowed_methods=frozenset(["GET", "HEAD", "POST"]))
        s.mount("https://", HTTPAdapter(max_retries=retry))
        s.mount("http://", HTTPAdapter(max_retries=retry))
        s.headers["User-Agent"] = config.USER_AGENT
        _session = s
    return _session


def cache_path(kind: str, key: str, suffix: str) -> Path:
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()[:20]
    d = config.cache_dir() / kind
    d.mkdir(parents=True, exist_ok=True)
    return d / f"{h}{suffix}"


def url_status(url: str, timeout: float = 30) -> int:
    """HTTP status of a URL (HEAD), or 0 if it could not be reached at all."""
    try:
        r = session().head(url, timeout=timeout, allow_redirects=True)
        return r.status_code
    except requests.RequestException:
        return 0


def post_json_cached(urls: list[str], data: dict, kind: str, timeout: float = 180, log=print) -> dict:
    """POST to the first of several mirrors that answers with JSON; the answer is cached by the request."""
    key = json.dumps(data, sort_keys=True)
    path = cache_path(kind, key, ".json")
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    errors = []
    for attempt in range(2):
        for url in urls:
            try:
                r = session().post(url, data=data, timeout=timeout)
                if r.status_code == 200 and "json" in r.headers.get("content-type", ""):
                    out = r.json()
                    path.write_text(json.dumps(out), encoding="utf-8")
                    return out
                errors.append(f"{url}: HTTP {r.status_code} {r.text[:120].strip()}")
            except (requests.RequestException, ValueError) as e:
                errors.append(f"{url}: {e}")
            log(f"  {url.split('/')[2]} did not answer; trying another server")
        time.sleep(5 * (attempt + 1))
    raise SourceError("No OpenStreetMap server answered. " + " | ".join(errors[-3:]))


def get_json(url: str, params: dict | None = None, timeout: float = 60) -> dict:
    r = session().get(url, params=params, timeout=timeout)
    r.raise_for_status()
    return r.json()
