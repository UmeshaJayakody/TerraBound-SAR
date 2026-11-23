"""Starts Earth Capture: a desktop window with the map (pywebview), or the same page in the browser."""
from __future__ import annotations

import time
import webbrowser

from .server import App, serve


def main(browser: bool = False, port: int = 0) -> None:
    app = App()
    httpd = serve(app, port)
    url = f"http://127.0.0.1:{httpd.server_address[1]}/"
    if not browser:
        try:
            import webview
            app.window = webview.create_window("Earth Capture - TerraBound SAR", url, width=1440, height=900,
                                               min_size=(1000, 650))
            webview.start()
            return
        except Exception as e:  # noqa: BLE001 -- no WebView2 runtime etc.: use the browser
            print(f"Could not open the app window ({e}); opening it in the browser instead.")
    print(f"Earth Capture is running at {url}  (close this window or press Ctrl+C to stop)")
    webbrowser.open(url)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
