# 앱 역 데이터와 공식 자료(data.go.kr 파일) 전수 대조
# usage: python3 -I Tools/official_compare/compare.py RememberSubway/Resources/transit_data.json DL_DIR
#   DL_DIR은 fetch.py로 내려받은 data.go.kr 파일 폴더(파일명 = 공공데이터 PK).
#   보조 자료(공식 파일이 없는 노선)는 이 스크립트 옆 extra.json에서 읽는다.
import sys, os, re, csv, io, json, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xlsx

app_path, dl = sys.argv[1], sys.argv[2]
app = json.load(open(app_path))

def norm(s):
    s = s.replace("（", "(").replace("）", ")")
    s = re.sub(r"[\s·ㆍ‧.・]", "", s)
    s = re.sub(r"역(?=$|\()", "", s)
    return s
def base(s): return norm(s).split("(")[0]
def sub(s):
    m = re.search(r"\((.*)\)", norm(s)); return m.group(1) if m else None

def load(pk):
    for ext in ("xlsx", "csv"):
        p = os.path.join(dl, f"{pk}.{ext}")
        if os.path.exists(p): break
    if p.endswith("xlsx"): rows = xlsx.rows(p)
    else:
        b = open(p, "rb").read()
        try: t = b.decode("utf-8-sig")
        except UnicodeDecodeError: t = b.decode("cp949")
        rows = [r for r in csv.reader(io.StringIO(t)) if any(r)]
    h = rows[0]
    return [dict(zip(h, r)) for r in rows[1:]]

# (line_id, label, pk, filter(row)->bool, name_col, order_col or "seq" or None, partial)
def eq(col, *vals): return lambda r: r.get(col, "").strip() in vals
S = []
def add(line, label, pk, flt, name="역명", order=None, partial=False): S.append((line, label, pk, flt, name, order, partial))
add("seoul-1", "서울교통공사 역주소", "15044231", eq("호선", "1"), order="역번호", partial=True)
add("seoul-1", "KRNA 1호선 역정보", "15041013", eq("선명", "1호선"))
for b in ("1호선(경인선)", "1호선(광명선)", "1호선(서동탄선)", "1호선(경부선)"):
    add("seoul-1", f"KRNA 역간거리 {b}", "15041460", eq("선명", b), order="seq", partial=True)
for n in "2345678":
    add(f"seoul-{n}", "서울교통공사 역주소", "15044231", eq("호선", n), order="역번호", partial=n in "3478")
add("seoul-2", "KRNA 2호선 역간거리", "15041425", eq("선명", "2호선"), order="seq")
add("seoul-3", "KRNA 3호선 역정보", "15041016", eq("선명", "3호선"))
add("seoul-3", "KRNA 3호선 역간거리", "15041423", eq("선명", "3호선"), order="seq")
add("seoul-4", "KRNA 4호선 역정보", "15041806", eq("선명", "4호선"))
add("seoul-4", "KRNA 4호선 역간거리", "15041350", eq("선명", "4호선"), order="seq")
add("seoul-6", "KRNA 6호선 역정보", "15041809", eq("선명", "6호선"))
add("seoul-7", "KRNA 7호선 역정보", "15041808", eq("선명", "7호선"))
add("seoul-7", "KRNA 7호선 역간거리", "15041340", eq("선명", "7호선"), order="seq")
add("seoul-7", "인천교통공사 역주소", "15043811", eq("호선", "7호선"), order="seq", partial=True)
add("seoul-8", "KRNA 8호선 역정보", "15041810", eq("선명", "8호선"))
add("seoul-8", "KRNA 8호선 역간거리", "15041299", eq("선명", "8호선"), order="seq")
add("seoul-9", "서울교통공사 역주소", "15044231", eq("호선", "9"), order="역번호", partial=True)
add("seoul-9", "KRNA 9호선 역정보", "15041811", eq("선명", "9호선"))
add("seoul-9", "KRNA 9호선 역간거리", "15041298", eq("선명", "9호선"), order="seq")
add("seoul-ui", "KRNA 우이신설 역정보", "15041029", eq("선명", "우이신설"), order="역번호")
add("incheon-1", "KRNA 인천1호선 역정보", "15041031", eq("선명", "인천1호선"))
add("incheon-1", "인천교통공사 역주소", "15043811", eq("호선", "1호선"), order="seq")
add("incheon-2", "KRNA 인천2호선 역정보", "15041032", eq("선명", "인천2호선"))
add("incheon-2", "인천교통공사 역주소", "15043811", eq("호선", "2호선"), order="seq")
add("suin-bundang", "KRNA 분당선 역정보", "15041812", eq("선명", "수인분당"))
add("suin-bundang", "KRNA 분당선 역간거리", "15041284", eq("선명", "수인분당"), order="seq")
add("suin-bundang", "KRNA 수인선 역간거리", "15041269", eq("선명", "수인분당"), order="seq")
add("gyeongui-jungang", "KRNA 경의중앙 역정보", "15041027", eq("선명", "경의중앙"))
add("gyeongui-jungang", "KRNA 경의중앙 역간거리", "15041327", eq("선명", "경의중앙"), order="seq")
add("gyeongchun", "KRNA 경춘 역정보", "15041813", eq("선명", "경춘"))
add("gyeongchun", "KRNA 경춘 역간거리", "15041295", eq("선명", "경춘"), order="seq")
add("gyeonggang", "KRNA 경강 역정보", "15041028", eq("선명", "경강"))
add("shinbundang", "KRNA 신분당 역정보", "15041033", eq("선명", "신분당"))
add("shinbundang", "KRNA 신분당 역간거리", "15041074", eq("선명", "신분당"), order="seq")
add("arex", "KRNA 공항철도 역정보", "15041034", eq("선명", "공항"))
add("arex", "KRNA 공항철도 역간거리", "15041310", eq("선명", "공항"), order="seq")
for n in "1234":
    add(f"busan-{n}", f"KRNA 부산{n}호선 역정보", str(15041036 + int(n)), eq("선명", f"{n}호선"))
    add(f"busan-{n}", "부산교통공사 역명정보", "3077187", eq("호선", f"{n}호선"), order="역번호")
    add(f"busan-{n}", "KRNA 부산 호선구성", "15041436", eq("선명", f"{n}호선"), order="역구성순서")
add("busan-gimhae", "KRNA 부산김해 역정보", "15041041", eq("선명", "부산김해경전철"), order="역번호")
add("donghae", "KRNA 부산동해선 역정보(2024-09)", "15041042", eq("선명", "동해"), order="seq")
for n, pk in zip("123", ("15041043", "15041045", "15041047")):
    add(f"daegu-{n}", f"KRNA 대구{n}호선 역정보", pk, eq("선명", f"{n}호선"), order="역번호")
    add(f"daegu-{n}", "대구교통공사 역주소", "15119035", eq("호선", n), name="역명(한글)", order="역번호")
    add(f"daegu-{n}", "KRNA 대구 호선구성", "15041441", eq("선명", f"{n}호선"), order="역구성순서")
add("gwangju-1", "KRNA 광주1호선 역정보(2023-07)", "15041048", eq("선명", "1호선"), order="seq")
add("daejeon-1", "KRNA 대전1호선 역정보", "15041049", eq("선명", "1호선"), order="역번호")
add("daejeon-1", "KRNA 대전 호선구성", "15041445", eq("선명", "1호선"), order="역구성순서")
# 국가철도공단 도시광역철도 역명 (2026-06-30 기준, 순서 없음)
ALL = lambda r: True
for line, pk in [("seoul-1","15064037"),("seoul-2","15064039"),("seoul-3","15064040"),("seoul-4","15064041"),("seoul-5","15064043"),
                 ("seoul-6","15064045"),("seoul-7","15064046"),("seoul-8","15064048"),("seoul-9","15064049"),("gyeonggang","15064050"),
                 ("gyeongui-jungang","15064051"),("gyeongchun","15064052"),("arex","15064053"),("shinbundang","15064621"),
                 ("seoul-ui","15064624"),("incheon-1","15064661"),("incheon-2","15064663"),("seohae","15064679"),("busan-1","15064687"),
                 ("busan-2","15064688"),("busan-3","15064695"),("busan-4","15064700"),("donghae","15064706"),("busan-gimhae","15064713"),
                 ("daegu-1","15068942"),("daegu-2","15068943"),("daegu-3","15068944"),("gwangju-1","15068945"),("daejeon-1","15068947")]:
    add(line, "KRNA 역명 2026-06-30", pk, ALL)
add("suin-bundang", "KRNA 분당선 역명 2026-06-30", "15064054", ALL, partial=True)
add("suin-bundang", "KRNA 수인선 역명 2026-06-30", "15064055", ALL, partial=True)
add("daejeon-1", "대전교통공사 역명 및 주소", "15083331", ALL, name="한 글", order="역번호")
extra = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extra.json")  # 보조 자료: {"line": [{"label":..., "stations":[...], "partial":bool}]}
extras = json.load(open(extra)) if os.path.exists(extra) else {}
# 대조 예외: {"_exclude": {"line": {"역명": "사유"}}} — 자료에 있어도 앱에 넣지 않기로 확정한 역
excludes = extras.pop("_exclude", {})
# 시행 미확인 역명 변경: {"_unconfirmed_renames": {"line": {"자료 역명": {"app": "앱 역명", "reason": "사유"}}}}
#   공공데이터에만 바뀐 이름이 보이고 실제 시행은 확인되지 않은 경우. 대조 때 자료 이름을 앱 이름으로
#   바꿔 읽고 '보류'로만 표시한다(차이로 세지 않음).
unconfirmed = extras.pop("_unconfirmed_renames", {})

stations = {s["id"]: s for s in app["stations"]}
lines = {l["id"]: l for l in app["lines"]}
patterns = collections.defaultdict(list)
for p in app["routePatterns"]: patterns[p["lineID"]].append(p["stationIDs"])

def app_index(line):
    ids = []
    for seq in patterns[line]:
        for i in seq:
            if i not in ids: ids.append(i)
    idx = {}
    for i in ids:
        s = stations[i]
        for n in [s["name"], s.get("fullName") or ""] + s.get("aliases", []):
            if n: idx.setdefault(base(n), i)
    return ids, idx
def adjacent(line, a, b):
    return any((x, y) in ((a, b), (b, a)) for seq in patterns[line] for x, y in zip(seq, seq[1:]))

def keyfn(order):
    def k(r):
        v = r[order]; m = re.search(r"\d+", v)
        return (int(m.group(0)) if m else 0, v)
    return k

summary = collections.OrderedDict()
report = []
def compare(line, label, names, partial, ordered):
    ids, idx = app_index(line)
    res = {"missing": [], "extra": [], "name": [], "order": []}
    held = []
    matched = []
    held_map = {base(k): v["app"] for k, v in unconfirmed.get(line, {}).items()}
    for raw in names:
        if base(raw) in {base(k) for k in excludes.get(line, {})}:
            continue
        if base(raw) in held_map:
            held.append(f"자료 '{raw}' → 앱 '{held_map[base(raw)]}' 유지")
            raw = held_map[base(raw)]
        i = idx.get(base(raw))
        if not i:
            res["missing"].append(raw); continue
        matched.append(i)
        s = stations[i]
        full = s.get("fullName") or s["name"]
        if base(raw) != base(s["name"]) and base(raw) != base(full):
            res["name"].append(f"본역명: 앱 '{s['name']}' / 자료 '{raw}'")
        if sub(raw) != sub(full) and sub(raw):
            res["name"].append(f"부역명: 앱 '{full}' / 자료 '{raw}'")
        elif sub(full) and not sub(raw):
            res["name"].append(f"부역명 없음(자료): 앱 '{full}' / 자료 '{raw}'")
    if not partial:
        res["extra"] = [stations[i]["name"] for i in ids if i not in matched]
    if ordered:
        for a, b in zip(matched, matched[1:]):
            if a != b and not adjacent(line, a, b):
                res["order"].append(f"{stations[a]['name']}→{stations[b]['name']}")
    ok = not any(res.values())
    summary.setdefault(line, []).append((label, len(names), ok, res, held))

for line, label, pk, flt, name, order, partial in S:
    rows = [r for r in load(pk) if flt(r)]
    if order and order != "seq": rows.sort(key=keyfn(order))
    if name is None: name = next(k for k in rows[0] if "역명" in k)
    names = [r[name].strip() for r in rows if r.get(name, "").strip()]
    compare(line, f"{label} [{pk}]", names, partial, bool(order))
for line, items in extras.items():
    for it in items:
        compare(line, it["label"], it["stations"], it.get("partial", False), it.get("ordered", True))

total_ok = total = 0
for line in lines:
    ids, _ = app_index(line)
    items = summary.get(line, [])
    print(f"\n## {line} {lines[line]['name']} (앱 {len(ids)}역) — 자료 {len(items)}건")
    for label, n, ok, res, held in items:
        total += 1; total_ok += ok
        print(f"  [{'일치' if ok else '차이'}] {label}: {n}역")
        for k, title in (("missing", "앱에 없음"), ("extra", "자료에 없음"), ("name", "이름"), ("order", "순서(비인접)")):
            if res[k]: print(f"     - {title}: {', '.join(res[k])}")
        if held: print(f"     - 보류(시행 미확인, extra.json): {', '.join(held)}")
print(f"\n총 {total}건 중 일치 {total_ok}건")
