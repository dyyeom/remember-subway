# data.go.kr 파일데이터를 PK로 내려받는다(로그인 불필요).
# usage: python3 -I Tools/official_compare/fetch.py OUTDIR PK [PK...]
import sys, re, json, urllib.request, urllib.parse, http.cookiejar, os
out = sys.argv[1]
cj = http.cookiejar.CookieJar()
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.addheaders = [("User-Agent", "Mozilla/5.0"), ("X-Requested-With", "XMLHttpRequest")]
def get(url, data=None):
    return op.open(url, data=urllib.parse.urlencode(data).encode() if data else None, timeout=60).read()
for pk in sys.argv[2:]:
    page = get(f"https://www.data.go.kr/data/{pk}/fileData.do").decode()
    m = re.search(r"fn_fileDataDown\('(\d+)', '([^']+)', '([^']*)','(\d+)', '(\d+)'\)", page)
    upd = re.search(r'수정일</strong>\s*<div class="value">([^<]+)', page)
    title = re.search(r"<title>([^<]+)", page).group(1)
    if not m:
        print(pk, "no download button", title); continue
    j = json.loads(get("https://www.data.go.kr/tcs/dss/selectFileDataDownload.do", dict(publicDataPk=pk, publicDataDetailPk=m.group(2), fileDetailSn=m.group(4), publicDataTyCode="PR0051")))
    if not j.get("status"):
        print(pk, "fail", j.get("error")); continue
    a, sn = j["atchFileId"], j["fileDetailSn"]
    lim = json.loads(get("https://www.data.go.kr/cmm/cmm/check-limit.json", dict(atchFileId=a, fileDetailSn=sn)))
    if lim.get("needCaptcha"):
        print(pk, "captcha"); continue
    data = get(f"https://www.data.go.kr/cmm/cmm/fileDownload.do?atchFileId={a}&fileDetailSn={sn}")
    ext = "csv" if data[:2] != b"PK" else "xlsx"
    path = os.path.join(out, f"{pk}.{ext}")
    open(path, "wb").write(data)
    print(pk, upd.group(1) if upd else "?", title.strip()[:60], len(data), path)
