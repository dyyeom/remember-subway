# 앱 역 데이터와 공식 자료(data.go.kr 파일) 전수 대조
# usage: python3 -I Tools/official_compare/compare.py RememberSubway/Resources/transit_data.json DL_DIR
#   DL_DIR은 fetch.py로 내려받은 data.go.kr 파일 폴더(파일명 = 공공데이터 PK). 대조 목록은 sources.py.
#   보조 자료(공식 파일이 없는 노선)는 이 스크립트 옆 extra.json에서 읽는다.
# 규칙(README.md): 공공데이터에서만 보이는 역명 변경은 바로 반영하지 않는다. 운영기관 공지·고시·언론 보도 중
#   하나로 실제 시행이 확인된 경우에만 반영하고, 아니면 extra.json `_unconfirmed_renames`에 등록한다.
#   출력 끝의 "역명 변경 후보(시행 확인 필요)" 목록이 그 확인 대상이다.
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

from sources import S
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
# 순환 계통은 마지막 역과 첫 역도 이웃이다(첫 역을 끝에 다시 적지 않는다).
for p in app["routePatterns"]:
    patterns[p["lineID"]].append(p["stationIDs"] + p["stationIDs"][:1] if p["kind"] == "loop" else p["stationIDs"])

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
def neighbors_between(line, a, c):
    """앱 계통에서 a와 c 사이에 정확히 한 역이 끼어 있으면 그 역 ID들을 돌려준다."""
    found = set()
    for seq in patterns[line]:
        for x, y, z in zip(seq, seq[1:], seq[2:]):
            if (x, z) in ((a, c), (c, a)): found.add(y)
    return found

def compare(line, label, names, partial, ordered):
    ids, idx = app_index(line)
    # rename: 역명 변경 후보(시행 확인 필요). 자료에만 있는 이름이 앱의 한 역 자리를 그대로 차지하는 경우.
    #   README 규칙대로 바로 반영하지 말고 운영기관 공지·고시·언론 보도로 시행을 확인한 뒤 반영하거나,
    #   미시행이면 extra.json `_unconfirmed_renames`에 등록한다.
    res = {"missing": [], "extra": [], "name": [], "order": [], "rename": []}
    held = []
    matched = []
    slots = []  # 자료 순서대로 (raw, 앱 역 ID 또는 None)
    held_map = {base(k): v["app"] for k, v in unconfirmed.get(line, {}).items()}
    for raw in names:
        if base(raw) in {base(k) for k in excludes.get(line, {})}:
            continue
        if base(raw) in held_map:
            held.append(f"자료 '{raw}' → 앱 '{held_map[base(raw)]}' 유지")
            raw = held_map[base(raw)]
        i = idx.get(base(raw))
        slots.append((raw, i))
        if not i:
            res["missing"].append(raw); continue
        matched.append(i)
        s = stations[i]
        full = s.get("fullName") or s["name"]
        if base(raw) != base(s["name"]) and base(raw) != base(full):
            res["name"].append(f"본역명(자료가 앱 별칭과 같음): 앱 '{s['name']}' / 자료 '{raw}'")
        if sub(raw) != sub(full) and sub(raw):
            res["name"].append(f"부역명: 앱 '{full}' / 자료 '{raw}'")
        elif sub(full) and not sub(raw):
            res["name"].append(f"부역명 없음(자료): 앱 '{full}' / 자료 '{raw}'")
    # 자료에만 있는 역의 앞뒤 역이 앱에서 한 역을 사이에 두고 이웃하고, 그 역이 자료에 없으면 역명 변경 후보로 분류한다.
    renamed = set()
    for k, (raw, i) in enumerate(slots):
        if i or k == 0 or k == len(slots) - 1: continue
        a, c = slots[k - 1][1], slots[k + 1][1]
        if not a or not c: continue
        between = [x for x in neighbors_between(line, a, c) if x not in matched and x not in renamed]
        if len(between) == 1:
            x = between[0]
            renamed.add(x)
            res["missing"].remove(raw)
            res["rename"].append(f"앱 '{stations[x]['name']}' / 자료 '{raw}'")
    if not partial:
        res["extra"] = [stations[i]["name"] for i in ids if i not in matched and i not in renamed]
        # 순서가 없는 자료라도 자료에만 있는 역과 앱에만 있는 역이 하나씩이면 같은 역의 이름 차이로 본다.
        if len(res["missing"]) == 1 and len(res["extra"]) == 1:
            res["rename"].append(f"앱 '{res['extra'].pop()}' / 자료 '{res['missing'].pop()}'")
    if ordered:
        for a, b in zip(matched, matched[1:]):
            if a != b and not adjacent(line, a, b) and not any(x in renamed for x in neighbors_between(line, a, b)):
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
        for k, title in (("missing", "앱에 없음"), ("extra", "자료에 없음"), ("name", "이름"), ("order", "순서(비인접)"),
                         ("rename", "역명 변경 후보(시행 확인 필요)")):
            if res[k]: print(f"     - {title}: {', '.join(res[k])}")
        if held: print(f"     - 보류(시행 미확인, extra.json): {', '.join(held)}")
print(f"\n총 {total}건 중 일치 {total_ok}건")
renames = sorted({(line, r) for line, items in summary.items() for *_, res, _h in items for r in res["rename"]})
if renames:
    print("\n## 역명 변경 후보(시행 확인 필요) — 공공데이터만으로 반영 금지, README 규칙 참고")
    for line, r in renames: print(f"  - {line}: {r}")
