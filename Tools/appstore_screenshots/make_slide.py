#!/usr/bin/env python3
"""App Store 스크린샷 한 장을 새 앱 캡처와 문구로 다시 만듭니다.

기존 슬라이드(현재 App Store에 올라간 같은 번호의 이미지)를 바탕으로 쓰고,
배경·노선 레일 모티프·디바이스 프레임·그림자는 그대로 둔 채
  1) 상단 캡슐 라벨, 헤드라인 2줄, 서브카피를 지우고 다시 그리고
  2) 디바이스 화면 영역을 새 시뮬레이터 캡처로 바꿉니다.
글자 크기·기준선·캡슐 치수는 크기별로 기존 이미지에서 측정한 값(SPECS)입니다.

사용법 예시 (4번 장, 싱글플레이 홈):
  python3 Tools/appstore_screenshots/make_slide.py \\
    --base-dir  <현재 스크린샷 폴더>   # <DISPLAY_TYPE>/NN.png 구조 (ASC에서 내려받은 것)
    --slide 04 \\
    --capture   <1320x2868 시뮬레이터 캡처.png> \\
    --label "노선 선택" \\
    --headline "5개 지역 35개 노선" --headline "1,093개 역" \\
    --subtitle "수도권·부산·대구·광주·대전 노선을 골라 도전" \\
    --out-dir   <출력 폴더>        # <DISPLAY_TYPE>/NN.png 로 저장
  선택: --label-color 0052A4 (기본값은 바탕 이미지의 캡슐 색을 그대로 씀)
        --sizes APP_IPHONE_67 APP_IPHONE_47 (기본값은 SPECS의 6개 크기 전부)

캡처는 iPhone 17 Pro Max(1320x2868), 한국어, 상태 막대 9:41로 찍은 것을 씁니다.
출력은 알파 없는 RGB PNG입니다. 가격·프로모션 문구는 넣지 않습니다.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
BOLD, MEDIUM = 6, 2  # AppleSDGothicNeo.ttc face index
BG = (242, 247, 250)
HEAD_COLOR = (10, 18, 31)
SUB_COLOR = (77, 87, 102)
WHITE = (255, 255, 255)

# 크기별 측정값. head=(글자 크기, 1줄 기준선 y, 2줄 기준선 y), sub=(크기, 기준선 y)
# label: 글자 크기·기준선, 캡슐 위 y·높이, 왼쪽 여백, 점 너비·높이·위 여백, 점-글자 간격, 오른쪽 여백(글자 진행 폭 기준)
SPECS = {
    "APP_IPHONE_67": dict(size=(1320, 2868), head=(126, 369, 539), sub=(59, 666),
                          label=dict(size=51, base=188, top=129, h=82, pad_l=34, dot=28, dot_h=29, dot_top=26, gap=18, pad_r=34)),
    "APP_IPHONE_65": dict(size=(1284, 2778), head=(123, 359, 525), sub=(57, 647),
                          label=dict(size=50, base=183, top=125, h=80, pad_l=33, dot=28, dot_h=28, dot_top=26, gap=17, pad_r=34)),
    "APP_IPHONE_61": dict(size=(1206, 2622), head=(115, 337, 493), sub=(54, 608),
                          label=dict(size=47, base=173, top=118, h=75, pad_l=31, dot=26, dot_h=26, dot_top=24, gap=16, pad_r=32)),
    "APP_IPHONE_58": dict(size=(1125, 2436), head=(108, 314, 461), sub=(50, 568),
                          label=dict(size=43, base=159, top=110, h=69, pad_l=29, dot=24, dot_h=24, dot_top=22, gap=14, pad_r=30)),
    "APP_IPHONE_55": dict(size=(1242, 2208), head=(106, 284, 428), sub=(50, 535),
                          label=dict(size=44, base=136, top=84, h=73, pad_l=32, dot=25, dot_h=26, dot_top=23, gap=16, pad_r=32)),
    "APP_IPHONE_47": dict(size=(750, 1334), head=(64, 173, 260), sub=(30, 325),
                          label=dict(size=27, base=82, top=51, h=45, pad_l=19, dot=16, dot_h=16, dot_top=14, gap=9, pad_r=20)),
}


def font(size: int, face: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size, index=face)


def ink_box(text: str, f: ImageFont.FreeTypeFont):
    """기준선 왼쪽 끝(anchor 'ls') 기준 실제 잉크 영역 (x0, y0, x1, y1)."""
    s = f.size
    canvas = Image.new("L", (int(f.getlength(text)) + 4 * s, 4 * s), 0)
    ImageDraw.Draw(canvas).text((2 * s, 3 * s), text, font=f, fill=255, anchor="ls")
    ys, xs = np.where(np.array(canvas) > 40)
    return xs.min() - 2 * s, ys.min() - 3 * s, xs.max() - 2 * s + 1, ys.max() - 3 * s + 1


def hex_rgb(value: str):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def label_color_from(base: Image.Image, spec) -> tuple:
    lab = spec["label"]
    x = spec["size"][0] // 2
    y = lab["top"] + 4
    return base.getpixel((x, y))


def draw_label(img: Image.Image, spec, text: str, color):
    lab = spec["label"]
    W = spec["size"][0]
    f = font(lab["size"], BOLD)
    width = int(lab["pad_l"] + lab["dot"] + lab["gap"] + f.getlength(text) + lab["pad_r"])
    left = int((W - width) / 2 + 0.5)
    # 기존 이미지처럼 안티에일리어싱 없이 그립니다.
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((left, lab["top"], left + width - 1, lab["top"] + lab["h"] - 1), radius=lab["h"] // 2, fill=color)
    dx, dy = left + lab["pad_l"], lab["top"] + lab["dot_top"]
    d.ellipse((dx, dy, dx + lab["dot"] - 1, dy + lab.get("dot_h", lab["dot"]) - 1), fill=WHITE)
    tx = left + lab["pad_l"] + lab["dot"] + lab["gap"]
    ImageDraw.Draw(img).text((tx, lab["base"]), text, font=f, fill=WHITE, anchor="ls")


def find_screen(base: np.ndarray):
    """디바이스 프레임 안쪽 화면 영역 (x0, y0, x1, y1), 양끝 포함."""
    H, W, _ = base.shape
    dark = base.sum(2) < 250
    col = dark[:, W // 2]
    top = next(y for y in range(H // 6, H) if col[y])
    y0 = next(y for y in range(top, H) if not col[y])
    bottom = next(y for y in range(H - 1, 0, -1) if col[y])
    y1 = next(y for y in range(bottom, 0, -1) if not col[y])
    mid = (y0 + y1) // 2
    row = dark[mid]
    left = next(x for x in range(W) if row[x])
    x0 = next(x for x in range(left, W) if not row[x])
    right = next(x for x in range(W - 1, 0, -1) if row[x])
    x1 = next(x for x in range(right, 0, -1) if not row[x])
    return x0, y0, x1, y1


def replace_screen(img: Image.Image, capture: Image.Image):
    base = np.array(img).astype(np.float32)
    x0, y0, x1, y1 = find_screen(base.astype(int))
    w, h = x1 - x0 + 1, y1 - y0 + 1
    shot = np.array(capture.convert("RGB").resize((w, h), Image.LANCZOS)).astype(np.float32)

    # 둥근 화면 모서리: 프레임(어두운 테두리)으로 둘러싸인 안쪽만 새 화면으로 채우고,
    # 테두리에 닿는 2px 띠는 기존 픽셀 밝기로 비율을 구해 테두리 색과 섞습니다(안티에일리어싱 보존).
    m = 8
    region = base[y0 - m:y1 + m + 1, x0 - m:x1 + m + 1]
    seed_bezel = (m // 2, (h + 2 * m) // 2)  # 왼쪽 테두리 위의 점 (x, y)
    seed_screen = (m + w // 2, m + h // 2)

    def flood(binary: np.ndarray, seed) -> np.ndarray:
        img_ = Image.fromarray(binary.astype(np.uint8) * 255).copy()  # fromarray 결과는 읽기 전용이라 copy 필요
        ImageDraw.floodfill(img_, seed, 128)
        return np.array(img_) == 128

    core = flood(region.astype(int).sum(2) < 400, seed_bezel)
    screen = flood(~core, seed_screen)
    near = np.zeros_like(core)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            near |= np.roll(np.roll(core, dy, 0), dx, 1)
    ring = screen & near
    bezel = np.median(region[core & (region.astype(int).sum(2) < 120)], axis=0)
    old_bg = base[(y0 + y1) // 2, x0 + 3]
    lum = lambda a: a @ np.array([0.299, 0.587, 0.114], np.float32)
    alpha = np.clip((lum(region) - lum(bezel)) / max(1.0, float(lum(old_bg) - lum(bezel))), 0, 1)

    new = region.copy()
    new_screen = np.zeros_like(region)
    new_screen[m:m + h, m:m + w] = shot
    fill = screen & ~ring
    new[fill] = new_screen[fill]
    a = alpha[ring][:, None]
    new[ring] = bezel * (1 - a) + new_screen[ring] * a
    base[y0 - m:y1 + m + 1, x0 - m:x1 + m + 1] = new
    return Image.fromarray(np.clip(base + 0.5, 0, 255).astype(np.uint8))


def make(display: str, base_path: Path, capture: Image.Image, label: str, headline: list[str],
         subtitle: str, label_color=None) -> Image.Image:
    spec = SPECS[display]
    img = Image.open(base_path).convert("RGB")
    assert img.size == spec["size"], (display, img.size)
    color = label_color or label_color_from(img, spec)
    W = spec["size"][0]
    hs, b1, b2 = spec["head"]
    ss, sb = spec["sub"]

    # 텍스트 영역(캡슐 위 ~ 서브카피 아래)을 배경색으로 지웁니다.
    # 서브카피 줄은 디바이스 그림자 윗부분과 겹칠 수 있어, 위·아래 행을 세로로 보간해 그림자를 살립니다.
    clear_top = spec["label"]["top"] - 6
    sub_top = sb - ss - 2
    clear_bottom = sb + int(ss * 0.32)
    ImageDraw.Draw(img).rectangle((0, clear_top, W - 1, sub_top - 1), fill=BG)
    arr = np.array(img).astype(np.float32)
    above, below = arr[sub_top - 1], arr[clear_bottom + 1]
    n = clear_bottom - sub_top + 2
    for i, y in enumerate(range(sub_top, clear_bottom + 1), start=1):
        arr[y] = above + (below - above) * (i / n)
    img = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8))

    img = replace_screen(img, capture)

    draw_label(img, spec, label, color)
    d = ImageDraw.Draw(img)
    hf = font(hs, BOLD)
    for text, baseline in zip(headline, (b1, b2)):
        d.text((W / 2, baseline), text, font=hf, fill=HEAD_COLOR, anchor="ms")
    d.text((W / 2, sb), subtitle, font=font(ss, MEDIUM), fill=SUB_COLOR, anchor="ms")
    return img.convert("RGB")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--base-dir", required=True, type=Path)
    p.add_argument("--slide", required=True, help="장 번호, 예: 04")
    p.add_argument("--capture", required=True, type=Path)
    p.add_argument("--label", required=True)
    p.add_argument("--headline", required=True, action="append", help="두 번 지정 (1줄, 2줄)")
    p.add_argument("--subtitle", required=True)
    p.add_argument("--label-color", help="캡슐 색 hex. 생략하면 바탕 이미지 색 유지")
    p.add_argument("--out-dir", required=True, type=Path)
    p.add_argument("--sizes", nargs="*", default=list(SPECS))
    a = p.parse_args()
    if len(a.headline) != 2:
        p.error("--headline 을 정확히 두 번 지정하세요")
    capture = Image.open(a.capture)
    color = hex_rgb(a.label_color) if a.label_color else None
    for display in a.sizes:
        out = make(display, a.base_dir / display / f"{a.slide}.png", capture, a.label, a.headline, a.subtitle, color)
        path = a.out_dir / display / f"{a.slide}.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        out.save(path, optimize=True)
        print(display, out.size, out.mode, path)


if __name__ == "__main__":
    main()
