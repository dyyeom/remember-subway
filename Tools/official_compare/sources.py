# compare.py가 대조하는 data.go.kr 파일 목록. fetch.py도 이 목록으로 내려받는다.
# PK는 모두 문자열 상수로 적는다(계산식으로 만들지 않는다). 자릿수는 자료마다 다르다(예: 3077187은 7자리).
# usage: python3 -I Tools/official_compare/sources.py   # 내려받을 PK 목록 출력
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
for n, pk in zip("1234", ("15041037", "15041038", "15041039", "15041040")):
    add(f"busan-{n}", f"KRNA 부산{n}호선 역정보", pk, eq("선명", f"{n}호선"))
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
# 수도권 경전철. 김포골드라인 역명 파일(15064683)은 2026-06-30판 내용이 서해선이라 쓰지 않고 extra.json 운영사 노선안내로 대조한다.
add("uijeongbu-lrt", "KRNA 의정부경전철 역정보", "15041030", eq("선명", "의정부"), order="역번호")
add("uijeongbu-lrt", "KRNA 의정부경전철 역간거리", "15081852", eq("선명", "의정부"), order="seq")
add("uijeongbu-lrt", "KRNA 역명 2026-06-30", "15064659", ALL)
add("yongin-everline", "KRNA 에버라인 역정보(2025-06)", "15041035", eq("선명", "에버라인"), order="역번호")
add("yongin-everline", "KRNA 에버라인 역간거리", "15081850", eq("선명", "에버라인"), order="seq")
add("yongin-everline", "KRNA 역명 2026-06-30", "15064619", ALL)
add("suin-bundang", "KRNA 분당선 역명 2026-06-30", "15064054", ALL, partial=True)
add("suin-bundang", "KRNA 수인선 역명 2026-06-30", "15064055", ALL, partial=True)
add("daejeon-1", "대전교통공사 역명 및 주소", "15083331", ALL, name="한 글", order="역번호")

def pks():
    """대조에 쓰는 공공데이터 PK를 중복 없이 처음 나온 순서대로 돌려준다."""
    return list(dict.fromkeys(pk for _line, _label, pk, *_ in S))

if __name__ == "__main__":
    print(" ".join(pks()))
