import zipfile, re, xml.etree.ElementTree as ET
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
def col(ref):
    n = 0
    for c in re.match(r"[A-Z]+", ref).group(0): n = n * 26 + ord(c) - 64
    return n - 1
def rows(path):
    z = zipfile.ZipFile(path)
    ss = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", NS):
            ss.append("".join(t.text or "" for t in si.iter("{%s}t" % NS["m"])))
    sheet = sorted(n for n in z.namelist() if n.startswith("xl/worksheets/sheet"))[0]
    out = []
    for r in ET.fromstring(z.read(sheet)).iter("{%s}row" % NS["m"]):
        vals = {}
        for c in r.findall("m:c", NS):
            v = c.find("m:v", NS); t = c.get("t")
            if t == "inlineStr": s = "".join(x.text or "" for x in c.iter("{%s}t" % NS["m"]))
            elif v is None: s = ""
            elif t == "s": s = ss[int(v.text)]
            else: s = v.text
            vals[col(c.get("r"))] = s.strip()
        if vals: out.append([vals.get(i, "") for i in range(max(vals) + 1)])
    return out
