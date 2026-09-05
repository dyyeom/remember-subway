#!/usr/bin/env python3
"""App Store Connect API로 역순서 Game Center 리더보드를 등록합니다.

기본값은 미리보기입니다. 실제 요청에는 --apply를 사용하세요.
"""
from __future__ import annotations
import argparse, base64, json, os, sys, time, urllib.error, urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

# The v1 endpoint remains the compatible creation endpoint for classic
# leaderboards; v2 additionally requires an inline leaderboard version.
API_ROOT = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_DATA = Path(__file__).resolve().parents[1] / "RememberSubway/Resources/transit_data.json"
PREFIX = "kr.co.remembersubway.single"

def b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")

def make_token(issuer: str, key_id: str, key_path: Path) -> str:
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    except ImportError as exc:
        raise SystemExit("cryptography가 필요합니다. `python3 -m pip install cryptography`를 먼저 실행하세요.") from exc
    now = datetime.now(timezone.utc)
    header = b64(json.dumps({"alg":"ES256","kid":key_id,"typ":"JWT"}, separators=(",",":")).encode())
    payload = b64(json.dumps({"iss":issuer,"iat":int(now.timestamp()),"exp":int((now+timedelta(minutes=15)).timestamp()),"aud":"appstoreconnect-v1"}, separators=(",",":")).encode())
    der = serialization.load_pem_private_key(key_path.read_bytes(), password=None).sign(f"{header}.{payload}".encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    return f"{header}.{payload}.{b64(r.to_bytes(32,'big') + s.to_bytes(32,'big'))}"

def component(value: str) -> str:
    return "".join(c.lower() if c.isalnum() else "_" for c in value)

def entries(catalog: dict, include_fallback: bool) -> list[dict]:
    regions = {r["id"]: r["name"] for r in catalog.get("regions", [])}
    result = ([{"id": f"{PREFIX}.v1", "name": "역순서 전체 기록"}] if include_fallback else [])
    for region in sorted(catalog.get("regions", []), key=lambda x: x.get("sortOrder", 0)):
        result.append({"id": f"{PREFIX}.region.{component(region['id'])}.v1", "name": f"{region['name']} 전체 기록"})
    for line in sorted(catalog.get("lines", []), key=lambda x: (x.get("regionID", ""), x.get("sortOrder", 0))):
        result.append({"id": f"{PREFIX}.line.{component(line['id'])}.v1", "name": f"{regions.get(line['regionID'], '지역')} · {line['name']}"})
    return result

def create(token: str, detail_id: str, item: dict) -> tuple[int, str]:
    body = {"data": {"type":"gameCenterLeaderboards", "attributes": {
        "referenceName": item["name"][:40], "vendorIdentifier": item["id"], "defaultFormatter":"INTEGER",
        "submissionType":"BEST_SCORE", "scoreSortType":"DESC", "scoreRangeStart":"0", "scoreRangeEnd":"100000",
        "visibility":"SHOW_FOR_ALL"}, "relationships":{"gameCenterDetail":{"data":{"type":"gameCenterDetails","id":detail_id}}}}}
    req = urllib.request.Request(f"{API_ROOT}/gameCenterLeaderboards", json.dumps(body).encode(), {"Authorization":f"Bearer {token}","Content-Type":"application/json","Accept":"application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as response: return response.status, response.read().decode()
    except urllib.error.HTTPError as error: return error.code, error.read().decode()

def main() -> int:
    parser = argparse.ArgumentParser(description="역순서 리더보드 일괄 등록")
    parser.add_argument("--apply", action="store_true", help="실제 생성 요청 전송")
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--game-center-detail-id", default=os.getenv("ASC_GAME_CENTER_DETAIL_ID"))
    parser.add_argument("--include-fallback", action="store_true", help="호환용 전체 기록 ID 포함")
    args = parser.parse_args()
    items = entries(json.loads(args.data.read_text(encoding="utf-8")), args.include_fallback)
    print(f"등록 대상: {len(items)}개")
    for item in items: print(f"  {item['id']} — {item['name']}")
    if not args.apply:
        print("\n미리보기입니다. 실제 등록은 --apply를 추가하세요."); return 0
    values = {"ASC_ISSUER_ID":os.getenv("ASC_ISSUER_ID"),"ASC_KEY_ID":os.getenv("ASC_KEY_ID"),"ASC_PRIVATE_KEY_PATH":os.getenv("ASC_PRIVATE_KEY_PATH")}
    missing = [key for key, value in values.items() if not value] + ([] if args.game_center_detail_id else ["ASC_GAME_CENTER_DETAIL_ID"])
    if missing: print("필수 설정 누락: " + ", ".join(missing), file=sys.stderr); return 2
    token = make_token(values["ASC_ISSUER_ID"], values["ASC_KEY_ID"], Path(values["ASC_PRIVATE_KEY_PATH"]))
    for index, item in enumerate(items, 1):
        for attempt in range(3):
            status, response = create(token, args.game_center_detail_id, item)
            if status != 429 or attempt == 2: break
            time.sleep(2 ** attempt)
        if status == 201: print(f"[{index}/{len(items)}] 생성됨: {item['id']}")
        elif status == 409 and ("already" in response.lower() or "duplicate" in response.lower()): print(f"[{index}/{len(items)}] 이미 존재: {item['id']}")
        else: print(f"[{index}/{len(items)}] 실패 {status}: {response}", file=sys.stderr)
    return 0

if __name__ == "__main__": raise SystemExit(main())
