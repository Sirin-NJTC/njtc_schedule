#!/usr/bin/env python3
"""生成 OCR / PDF 用的测试图片（真机与模拟器上的原生 E2E 夹具）。

内容刻意用「星期X + 课名 + 地点 + (节次)周次」这种课表里最常见的写法：
既能验证 OCR 认不认中文，也能顺手跑通 DocumentParser.parse 的整条链路。

用法（需要 Pillow）：
    python tool/make_ocr_fixture.py
产物：
    test/fixtures/ocr_sample.png   给 recognizeImage 用
    test/fixtures/ocr_sample.pdf   给 recognizePdf 用（同一张图存成 PDF）

真机/模拟器上跑 E2E 之前，把两个文件推进去：
    adb push test/fixtures/ocr_sample.png /sdcard/Download/ocr_sample.png
    adb push test/fixtures/ocr_sample.pdf /sdcard/Download/ocr_sample.pdf
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "test" / "fixtures"

# 课表里两门课的写法（一行一门，OCR 后正好能走 parseFreeText）
LINES = [
    "星期一 高等数学 明德楼A103 (3-4节)7-18周",
    "星期二 Python程序设计 格致楼205 (5-6节)7-18周",
]

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",  # 微软雅黑
    r"C:\Windows\Fonts\msyhbd.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
]


def pick_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if pathlib.Path(path).exists():
            return ImageFont.truetype(path, size)
    raise SystemExit("找不到中文字体，请把 FONT_CANDIDATES 里的路径改成机器上存在的字体")


def render() -> Image.Image:
    font = pick_font(44)
    pad, gap = 40, 28
    # 先量一下最宽的一行，图片别留太多空白（OCR 更喜欢紧凑的版面）
    probe = ImageDraw.Draw(Image.new("RGB", (10, 10), "white"))
    widths = [probe.textlength(line, font=font) for line in LINES]
    width = int(max(widths)) + pad * 2
    line_h = font.size + gap
    height = pad * 2 + line_h * len(LINES)

    img = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(img)
    for i, line in enumerate(LINES):
        draw.text((pad, pad + i * line_h), line, font=font, fill="black")
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img = render()

    png = OUT / "ocr_sample.png"
    img.save(png)
    print(f"{png}  {png.stat().st_size:,} B  {img.width}x{img.height}")

    pdf = OUT / "ocr_sample.pdf"
    img.save(pdf, "PDF", resolution=150.0)
    print(f"{pdf}  {pdf.stat().st_size:,} B")


if __name__ == "__main__":
    main()
