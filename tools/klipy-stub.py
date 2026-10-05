#!/usr/bin/env python3
"""KLIPY im Kleinen - fuer das GIF-Blatt im Simulator und in UI-Tests.

Ohne echten Schluessel antwortet KLIPY nicht, und ein Schluessel gehoert in
kein Repo. Dieser Stub beantwortet trending, search und share wie KLIPY
(Vertrag §2.7a); die Medien-URLs sind die echten aus KLIPYs oeffentlicher
Doku - sie laden ohne Schluessel, und der Dienst nimmt sie beim Senden an
(static.klipy.com).

    python3 tools/klipy-stub.py 48793
    COCKPIT_URL_KLIPY=http://127.0.0.1:48793/api/v1 tools/run-simulator.sh coHabit …

Jede Seite hat 24 Eintraege, die erste meldet has_next, die zweite nicht.
Geteilte GIFs (POST …/share/{slug}) stehen in der Ausgabe.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

MEDIA = "https://static.klipy.com/ii/935d7ab9d8c6202580a668421940ec81/14/af/"
FILES = {
    "hd": (498, {"gif": "um0L4dFH.gif", "webp": "eUbp2uNc.webp", "jpg": "LyWpim71.jpg", "mp4": "MCCBoQlZ.mp4"}),
    "md": (498, {"gif": "8GCrVAB7.gif", "webp": "JUYsGsrc.webp", "jpg": "UsX8Vqtm.jpg", "mp4": "V6da8Awi.mp4"}),
    "sm": (220, {"gif": "y6iepZM7.gif", "webp": "SE72470w.webp", "jpg": "uvntdY4w.jpg", "mp4": "3c2Tqd1S.mp4"}),
    "xs": (90, {"gif": "A4bPjSsj.gif", "webp": "Sp4pln3Z.webp", "jpg": "cGfi4U83.jpg", "mp4": "La0HaAzw.mp4"}),
}
BLUR = "data:image/jpeg;base64,/9j//gAQTGF2YzU5LjM3LjEwMAD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xAB6AAADAQEBAAAAAAAAAAAAAAAFBgMEBwEBAAIDAQAAAAAAAAAAAAAAAAQDAAIBBRAAAgEEAQMDAQkBAAAAAAAAAgEDAAUEEQYxEyESYUGScZHhUkIHMqEjFBEAAgMAAgICAwEAAAAAAAAAAgEDABEEITESE2EiQVEy/8AAEQgAHgAeAwESAAISAAMSAP/aAAwDAQACEQMRAD8A7AMw48RynvQCyevaow52KaYsk001r7am2Y7LNVTj/e+OPkP/ABgJKEZe29i99dUA5dZoLbzGOSSMRgnmRepLXhuqOVosqpRYyd/uuGDQ3ukcYxkhxLtK9gPNjycbEyx/hKhf1UOmuWAuORLFP19qIGteyohO4GNLugvU8tpRJG9T83PyKe4WfLUsCZxTrwl8PrXsPL7VmYcPeDuMfHnzpqrbZ62vdy54MnEhW2QffSLk3WeEUbZNLqt9a3HWF4uey/tRG9JUxfMaHkF1TmMXHDti90rDyT0qY1GaLX5vxoWSEzP6rr0oOTHFFi/1RNtbny3PsmW8KKQiBtiktvarBj3fFyc1zTYvcME2mWnQr+UC6pPqm70hKCUFud3n/IQj03bhyaaKP/KTyRNkL/TSpd7qeTdJ3ACgSfT4/qlx8jV+Xm2KAG6RyOGxLQ7Tqg5cgiu9v//Z"
PER_PAGE = 24


def item(number, title):
    file = {size: {fmt: {"url": MEDIA + name, "width": side, "height": side, "size": 1000}
                   for fmt, name in formats.items()}
            for size, (side, formats) in FILES.items()}
    return {"id": 8041071659142944 + number, "slug": f"hello-hi-{662 + number}", "title": title,
            "type": "gif", "blur_preview": BLUR, "file": file, "tags": []}


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        parts = url.path.strip("/").split("/")
        # /api/v1/{key}/gifs/{trending|search}
        if len(parts) != 5 or parts[3] != "gifs" or parts[4] not in ("trending", "search"):
            return self._json(404, {"result": False})
        page = int(query.get("page", ["1"])[0])
        words = query.get("q", [""])[0]
        title = words.capitalize() if words else "Hello"
        items = [item((page - 1) * PER_PAGE + i, f"{title} {i + 1}") for i in range(PER_PAGE)]
        print(f"{parts[4]} q={words!r} page={page} customer_id={query.get('customer_id', [''])[0]}", flush=True)
        self._json(200, {"result": True, "data": {"data": items, "current_page": page,
                                                   "per_page": PER_PAGE, "has_next": page < 2}})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        print(f"POST {self.path} {body}", flush=True)
        self._json(200, {"result": True})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 48793
    print(f"KLIPY-Stub auf http://127.0.0.1:{port}/api/v1", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
