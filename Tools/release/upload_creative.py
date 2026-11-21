"""App Store 크리에이티브 에셋(제품 페이지 헤더·검색 결과)을 Asset Library에 올리고 버전 현지화에 배치합니다.

사용법:
  PYTHONPATH=Tools/release python3 Tools/release/upload_creative.py <버전 현지화 ID> <placementType> <이미지 경로>
placementType: PRODUCT_PAGE_HEADER_ASSET | APP_STORE_SEARCH_RESULTS_ASSET
"""
from __future__ import annotations
import hashlib, sys, time, urllib.request
from pathlib import Path
from asc import api, token

APP_ID = "6819558739"

def upload(path: Path) -> str:
    data = path.read_bytes()
    status, body = api("POST", "/v1/appAssetLibraryImages", {"data": {
        "type": "appAssetLibraryImages",
        "attributes": {"fileName": path.name, "fileSize": len(data), "category": "CREATIVE_ASSETS"},
        "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": APP_ID}}}}})
    if status >= 300: raise SystemExit(f"이미지 예약 실패 {status}: {body}")
    image = body["data"]
    for op in image["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        request = urllib.request.Request(op["url"], chunk, headers, method=op["method"])
        with urllib.request.urlopen(request) as response:
            if response.status >= 300: raise SystemExit(f"업로드 실패 {response.status}")
    attributes = {"uploaded": True}
    status, body = api("PATCH", f"/v1/appAssetLibraryImages/{image['id']}", {"data": {
        "type": "appAssetLibraryImages", "id": image["id"],
        "attributes": {**attributes, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    if status >= 300:
        status, body = api("PATCH", f"/v1/appAssetLibraryImages/{image['id']}", {"data": {
            "type": "appAssetLibraryImages", "id": image["id"], "attributes": attributes}})
    if status >= 300: raise SystemExit(f"업로드 확정 실패 {status}: {body}")
    for _ in range(60):
        status, body = api("GET", f"/v1/appAssetLibraryImages/{image['id']}")
        state = body["data"]["attributes"].get("assetDeliveryState", {}) or {}
        state = state.get("state") if isinstance(state, dict) else state
        state = state or body["data"]["attributes"].get("state")
        print(path.name, state, flush=True)
        if state in ("COMPLETE", "PREPARE_FOR_SUBMISSION", "READY", "UPLOAD_COMPLETE"): return image["id"]
        if state == "FAILED": raise SystemExit(f"처리 실패: {body['data']['attributes']}")
        time.sleep(5)
    raise SystemExit("처리 대기 시간 초과")

def place(localization_id: str, placement_type: str, image_id: str):
    status, body = api("POST", "/v1/appAssetLibraryPlacements", {"data": {
        "type": "appAssetLibraryPlacements",
        "attributes": {"placementType": placement_type, "placementGroup": "DEFAULT_PROFILE"},
        "relationships": {
            "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": localization_id}},
            "image": {"data": {"type": "appAssetLibraryImages", "id": image_id}}}}})
    print("placement", status, body if status >= 300 else body["data"]["id"])

if __name__ == "__main__":
    localization_id, placement_type, image_path = sys.argv[1:4]
    place(localization_id, placement_type, upload(Path(image_path)))
