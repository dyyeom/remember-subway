#!/usr/bin/env python3
"""App Store 크리에이티브 에셋(제품 페이지 헤더·검색 결과·통합 에셋)을 만듭니다.

규격 (App Store Connect 'Creative assets specifications' 표와
App Store Connect API `GET /v1/appAssetLibraryRefData`의 imageSpecs로 확인):
  - 제품 페이지 헤더  21:9  3840x1646  PNG          안전 영역 1646x661  (x 1097, y 493)
  - 검색 결과         3:2   1920x1280~3840x2560     안전 영역 최대 2168x1030 (x 836, y 765)
                            JPEG/PNG (여기서는 최대 해상도 3840x2560 PNG)
  - 통합(universal)   16:9  5244x2950  PNG          안전 영역 1402x962  (x 1921, y 660)
  알파 채널 없음. 가격·할인·URL·다른 플랫폼 로고·Apple 수상 표기 금지.

통합 에셋의 안전 영역 y 660은 세로 가운데(y 994)가 아니라서, 문서 값과
가운데 정렬 값 둘 다를 만족하도록 두 영역이 겹치는 1402x628 (x 1921, y 994)
안에 핵심 그림(문구+표지판)을 넣습니다.

디자인: 딥 틸 바탕에 여러 노선색 레일이 지나가고, 2호선 초록 레일 위에
'사당 ‹ ? › 서울대입구' 역 안내판(가운데 노랑 ? 원)이 놓입니다. 위에 짧은 문구 한 줄.

사용법:
  python3 Tools/appstore_screenshots/make_header.py --out-dir <출력 폴더>
  선택: --lang ko en (기본 둘 다), --no-text (문구 없는 판)
출력: header-<lang>.png, search-<lang>.png, universal-<lang>.png 와 각각의 *-safe-preview.png
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

KO_FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
KO_BOLD, KO_SEMI = 6, 4
EN_BOLD = "/Library/Fonts/SF-Pro-Display-Bold.otf"
EN_SEMI = "/Library/Fonts/SF-Pro-Display-Semibold.otf"

BG = (0x12, 0x4A, 0x50)          # 딥 틸 (전체 노선 색)
BG_GLOW = (0x1B, 0x5E, 0x65)
GRID = (0x16, 0x53, 0x59)
INK = (0x0A, 0x12, 0x1F)
INK_SUB = (0x4D, 0x57, 0x66)
WHITE = (0xFF, 0xFF, 0xFF)
YELLOW = (0xF2, 0xC3, 0x00)      # Action
LINE2 = (0x00, 0xA8, 0x4D)
LINE1 = (0x00, 0x52, 0xA4)
LINE3 = (0xEF, 0x7C, 0x1C)
LINE4 = (0x00, 0xA5, 0xDE)
SINBUNDANG = (0xD4, 0x00, 0x3B)
LINE5 = (0x99, 0x6C, 0xAC)
LINE9 = (0xBD, 0xB0, 0x92)

# 형식별 캔버스와 핵심 그림 영역(문구+표지판이 들어갈 상자)
FORMATS = {
    "header": dict(size=(3840, 1646), safe=(1097, 493, 1646, 661), docs_safe=[(1097, 493, 1646, 661)]),
    "search": dict(size=(3840, 2560), safe=(836, 765, 2168, 1030), docs_safe=[(836, 765, 2168, 1030)]),
    "universal": dict(size=(5244, 2950), safe=(1921, 994, 1402, 628),
                      docs_safe=[(1921, 660, 1402, 962), (1921, 994, 1402, 962)]),
}

TAGLINE = {
    "ko": [("두 역 사이, ", WHITE), ("이 역은?", YELLOW)],
    "en": [("What's the stop ", WHITE), ("in between?", YELLOW)],
}
# 2호선: 서울대입구 - 낙성대(정답) - 사당
PREV = ("사당", "Sadang")
NEXT = ("서울대입구", "Seoul Nat'l Univ.")

SS = 2  # 슈퍼샘플링 배율

# 레일: 캔버스 가운데 기준, 단위 v = 캔버스 높이의 절반. (색, 꼭짓점들, 굵기 배율)
RAILS = [
    (LINE5, [(-1.95, -3), (-1.95, 3)], 1.0),
    (LINE9, [(1.9, -3), (1.9, 3)], 1.0),
    (LINE1, [(-4, -0.62), (-1.25, -0.62), (-0.95, -0.92), (-0.95, -3)], 1.0),
    (LINE3, [(-4, 0.6), (-1.6, 0.6), (-1.2, 1.0), (-1.2, 3)], 1.0),
    (LINE4, [(1.1, -3), (1.1, -0.85), (1.35, -0.6), (4, -0.6)], 1.0),
    (SINBUNDANG, [(1.25, 3), (1.25, 0.95), (1.6, 0.6), (4, 0.6)], 1.0),
    (LINE2, [(-4, 0.0), (4, 0.0)], 1.3),
]
TRANSFERS = [(-1.95, 0), (1.9, 0), (-1.95, -0.62), (-1.95, 0.6), (1.9, -0.6), (1.9, 0.6)]
STOPS = [  # (x, y, 노선색)
    (-1.4, 0, LINE2), (1.4, 0, LINE2), (-2.5, 0, LINE2), (2.45, 0, LINE2), (-3.0, 0, LINE2), (3.0, 0, LINE2),
    (-1.55, -0.62, LINE1), (-0.95, -1.25, LINE1), (-2.5, -0.62, LINE1),
    (-1.2, 1.3, LINE3), (-2.5, 0.6, LINE3),
    (1.1, -1.2, LINE4), (2.5, -0.6, LINE4),
    (1.25, 1.25, SINBUNDANG), (2.5, 0.6, SINBUNDANG),
    (-1.95, -1.1, LINE5), (-1.95, 1.1, LINE5), (1.9, -1.1, LINE9), (1.9, 1.1, LINE9),
]


def ko_font(size, face=KO_BOLD):
    return ImageFont.truetype(KO_FONT, max(1, int(size)), index=face)


def en_font(size, path=EN_BOLD):
    return ImageFont.truetype(path, max(1, int(size)))


def fillet(points, r):
    """꺾이는 꼭짓점을 반지름 r 정도의 곡선으로 바꾼 점 목록."""
    out = [points[0]]
    for i in range(1, len(points) - 1):
        (x0, y0), (x1, y1), (x2, y2) = points[i - 1], points[i], points[i + 1]
        def toward(ax, ay, bx, by):
            dx, dy = bx - ax, by - ay
            d = (dx * dx + dy * dy) ** 0.5
            t = min(r, d / 2) / d
            return ax + dx * t, ay + dy * t
        a = toward(x1, y1, x0, y0)
        b = toward(x1, y1, x2, y2)
        for k in range(17):
            t = k / 16
            out.append(((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * x1 + t * t * b[0],
                        (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * y1 + t * t * b[1]))
    out.append(points[-1])
    return out


def draw_background(size):
    W, H = size[0] * SS, size[1] * SS
    v = H / 2
    cx, cy = W / 2, H / 2
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # 은은한 격자
    step = v * 0.25
    gw = max(1, int(v * 0.004))
    k = 0
    while cx + k * step < W:
        for x in (cx + k * step, cx - k * step):
            d.line([(x, 0), (x, H)], fill=GRID, width=gw)
        k += 1
    k = 0
    while cy + k * step < H:
        for y in (cy + k * step, cy - k * step):
            d.line([(0, y), (W, y)], fill=GRID, width=gw)
        k += 1
    # 가운데 은은한 빛
    glow = Image.new("L", (W // 8, H // 8), 0)
    ImageDraw.Draw(glow).ellipse((W / 16 - v / 8 * 1.6, H / 16 - v / 8 * 0.8, W / 16 + v / 8 * 1.6, H / 16 + v / 8 * 0.8), fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(v / 8 * 0.35)).resize((W, H), Image.BILINEAR)
    img = Image.composite(Image.new("RGB", (W, H), BG_GLOW), img, glow)
    d = ImageDraw.Draw(img)

    P = lambda x, y: (cx + x * v, cy + y * v)
    lw = v * 0.055
    for color, pts, mul in RAILS:
        pts = fillet([P(x, y) for x, y in pts], v * 0.22)
        w = int(lw * mul)
        d.line(pts, fill=color, width=w, joint="curve")
    for x, y, color in STOPS:
        px, py = P(x, y)
        r = v * 0.036
        d.ellipse((px - r, py - r, px + r, py + r), fill=WHITE, outline=color, width=int(v * 0.014))
    for x, y in TRANSFERS:
        px, py = P(x, y)
        r = v * 0.058
        d.ellipse((px - r, py - r, px + r, py + r), fill=WHITE, outline=INK, width=int(v * 0.016))
    return img.resize(size, Image.LANCZOS)


def text_width(parts, f):
    return sum(f.getlength(t) for t, _ in parts)


def draw_sign(w, h, lang):
    """흰 역 안내판 RGBA (w, h는 최종 픽셀)."""
    W, H = int(w * SS), int(h * SS)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, W - 1, H - 1), radius=int(H * 0.14), fill=WHITE + (255,))
    # 초록 노선 띠
    band_cy = H * 0.42
    band_h = H * 0.30
    bx0, bx1 = W * 0.045, W * 0.955
    d.rounded_rectangle((bx0, band_cy - band_h / 2, bx1, band_cy + band_h / 2), radius=int(band_h / 2), fill=LINE2 + (255,))
    # 가운데 ? 원
    R = H * 0.37
    cx = W / 2
    d.ellipse((cx - R, band_cy - R, cx + R, band_cy + R), fill=WHITE + (255,))
    r2 = R * 0.90
    d.ellipse((cx - r2, band_cy - r2, cx + r2, band_cy + r2), fill=LINE2 + (255,))
    r3 = R * 0.74
    d.ellipse((cx - r3, band_cy - r3, cx + r3, band_cy + r3), fill=YELLOW + (255,))
    qf = en_font(r3 * 1.45, "/Library/Fonts/SF-Pro-Rounded-Black.otf")
    d.text((cx, band_cy + r3 * 0.04), "?", font=qf, fill=INK + (255,), anchor="mm")
    # 앞뒤 역 이름 (띠 위 흰 글씨)
    name_size = band_h * 0.56
    nf = ko_font(name_size)
    arrow_f = en_font(name_size * 1.05, EN_SEMI)
    left_edge, right_edge = bx0 + band_h * 0.42, bx1 - band_h * 0.42
    inner_l, inner_r = cx - R - band_h * 0.25, cx + R + band_h * 0.25
    ty = band_cy + name_size * 0.02
    # 왼쪽: ‹ 사당
    d.text((left_edge, ty), "‹", font=arrow_f, fill=WHITE + (255,), anchor="lm")
    aw = arrow_f.getlength("‹") + name_size * 0.25
    lx = (left_edge + aw + inner_l) / 2
    d.text((lx, ty), PREV[0], font=nf, fill=WHITE + (255,), anchor="mm")
    # 오른쪽: 서울대입구 ›
    d.text((right_edge, ty), "›", font=arrow_f, fill=WHITE + (255,), anchor="rm")
    rx = (inner_r + right_edge - aw) / 2
    nf_r = nf
    while nf_r.getlength(NEXT[0]) > (right_edge - aw - inner_r) * 0.96:
        nf_r = ko_font(nf_r.size - 2)
    d.text((rx, ty), NEXT[0], font=nf_r, fill=WHITE + (255,), anchor="mm")
    # 영문 보조 이름 (안내판 아래쪽, 잉크 회색)
    sub_f = en_font(H * 0.105, EN_SEMI)
    sy = band_cy + band_h / 2 + (H - (band_cy + band_h / 2)) * 0.5
    d.text((lx, sy), PREV[1], font=sub_f, fill=INK_SUB + (255,), anchor="mm")
    d.text((rx, sy), NEXT[1], font=sub_f, fill=INK_SUB + (255,), anchor="mm")
    # 위쪽 노선 배지 (2호선)
    br = H * 0.075
    bxc, byc = W * 0.075 + br, H * 0.13
    if byc + br < band_cy - band_h / 2 - H * 0.02:
        d.ellipse((bxc - br, byc - br, bxc + br, byc + br), fill=LINE2 + (255,))
        d.text((bxc, byc), "2", font=en_font(br * 1.4), fill=WHITE + (255,), anchor="mm")
    return img.resize((int(w), int(h)), Image.LANCZOS)


def tagline_image(lang, height, max_w):
    parts = TAGLINE[lang]
    size = height
    mk = (lambda s: ko_font(s)) if lang == "ko" else (lambda s: en_font(s))
    f = mk(size * SS)
    while text_width(parts, f) > max_w * SS:
        size -= 2
        f = mk(size * SS)
    tw = int(text_width(parts, f)) + 4
    th = int(size * SS * 1.4)
    img = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = 0
    for t, color in parts:
        d.text((x, th / 2), t, font=f, fill=color + (255,), anchor="lm")
        x += f.getlength(t)
    return img.resize((max(1, tw // SS), max(1, th // SS)), Image.LANCZOS)


def compose(kind, lang, text=True):
    spec = FORMATS[kind]
    size = spec["size"]
    sx, sy, sw, sh = spec["safe"]
    # 안전 영역 가장자리에서 4%씩 띄웁니다.
    sx, sy, sw, sh = sx + sw * 0.02, sy + sh * 0.04, sw * 0.96, sh * 0.92
    img = draw_background(size).convert("RGBA")

    # 세로 배치: 문구(18%) + 간격(6%) + 표지판(나머지)
    tag_h = sh * 0.17 if text else 0
    gap = sh * 0.07 if text else 0
    sign_h = min(sh - tag_h - gap, sw / 2.9)
    sign_w = min(sw, sign_h * 3.4)
    block_h = tag_h + gap + sign_h
    top = sy + (sh - block_h) / 2
    # 표지판이 2호선 레일 위에 오도록, 가능하면 표지판 띠를 캔버스 가운데 높이에 맞춥니다.
    want_sign_top = size[1] / 2 - sign_h * 0.42
    sign_top = min(max(want_sign_top, top + tag_h + gap), sy + sh - sign_h)
    tag_top = sign_top - gap - tag_h
    if tag_top < sy:  # 안전 영역을 벗어나면 블록 전체를 안전 영역 안 가운데로
        sign_top = top + tag_h + gap
        tag_top = top

    sign = draw_sign(sign_w, sign_h, lang)
    sxp = int(sx + (sw - sign_w) / 2)
    syp = int(sign_top)
    # 그림자
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    alpha = sign.split()[3].point(lambda a: int(a * 0.45))
    blk = Image.new("RGBA", sign.size, (4, 20, 24, 255))
    blk.putalpha(alpha)
    shadow.alpha_composite(blk, (sxp, syp + int(sign_h * 0.06)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sign_h * 0.06))
    img.alpha_composite(shadow)
    img.alpha_composite(sign, (sxp, syp))
    if text:
        tag = tagline_image(lang, tag_h * 0.78, sw)
        img.alpha_composite(tag, (int(sx + (sw - tag.width) / 2), int(tag_top + (tag_h - tag.height) / 2)))
    return img.convert("RGB")


def safe_preview(img, kind):
    spec = FORMATS[kind]
    W, H = img.size
    over = Image.new("RGBA", (W, H), (255, 0, 80, 90))
    d = ImageDraw.Draw(over)
    sx, sy, sw, sh = spec["docs_safe"][0]
    d.rectangle((sx, sy, sx + sw, sy + sh), fill=(0, 0, 0, 0))
    out = Image.alpha_composite(img.convert("RGBA"), over)
    d = ImageDraw.Draw(out)
    lw = max(4, W // 600)
    colors = [(255, 230, 0, 255), (0, 230, 255, 255)]
    for i, (x, y, w, h) in enumerate(spec["docs_safe"]):
        d.rectangle((x, y, x + w, y + h), outline=colors[i % 2], width=lw)
    if kind == "universal":
        # 통합 에셋이 헤더(21:9)·검색 결과(3:2)로 잘릴 때의 가운데 틀
        hh = W * 9 / 21
        d.rectangle((0, (H - hh) / 2, W - 1, (H + hh) / 2), outline=(255, 255, 255, 255), width=lw)
        sw_ = H * 3 / 2
        d.rectangle(((W - sw_) / 2, 0, (W + sw_) / 2, H - 1), outline=(255, 140, 0, 255), width=lw)
    return out.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--lang", nargs="+", default=["ko", "en"])
    ap.add_argument("--no-text", action="store_true")
    a = ap.parse_args()
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    langs = ["notext"] if a.no_text else a.lang
    for kind in FORMATS:
        for lang in langs:
            img = compose(kind, "ko" if lang == "notext" else lang, text=not a.no_text)
            assert img.mode == "RGB" and img.size == FORMATS[kind]["size"]
            p = out / f"{kind}-{lang}.png"
            img.save(p, optimize=True)
            safe_preview(img, kind).save(out / f"{kind}-{lang}-safe-preview.png", optimize=True)
            print(p, img.size)


if __name__ == "__main__":
    main()
