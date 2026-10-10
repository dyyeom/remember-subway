"""App Store Connect API 공용 호출 도우미.

환경 변수 ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY_PATH가 필요합니다.
"""
from __future__ import annotations
import json, os, socket, sys, time, urllib.error, urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from register_game_center_leaderboards import make_token

socket.setdefaulttimeout(120)
_token = {"value": None, "at": 0.0}

def token() -> str:
    if time.time() - _token["at"] > 600:
        _token["value"] = make_token(os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_ID"], Path(os.environ["ASC_PRIVATE_KEY_PATH"]).expanduser())
        _token["at"] = time.time()
    return _token["value"]

def api(method: str, path: str, body: dict | None = None):
    url = path if path.startswith("http") else "https://api.appstoreconnect.apple.com" + path
    for attempt in range(3):
        request = urllib.request.Request(url, json.dumps(body).encode() if body else None,
                                         {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}, method=method)
        try:
            with urllib.request.urlopen(request) as response:
                text = response.read().decode()
                return response.status, (json.loads(text) if text else {})
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read().decode() or "{}")
        except (socket.timeout, urllib.error.URLError, ConnectionError, OSError):
            if attempt == 2: raise
            time.sleep(5)
