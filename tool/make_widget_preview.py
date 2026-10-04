"""生成桌面小组件的静态预览图（`android/.../res/drawable-nodpi/widget_preview.png`）。

为什么需要它：`android:previewImage` 是「添加小组件」界面在老系统上唯一能拿到的画面。
少了它（且没有 previewLayout 时）用户看到的就是一张白卡 —— v1.1.8 的实况。

这张图是**示意**，不是真实截图：内容与 `widget_today.xml` 的配色/字号保持一致，
尺寸按 4×2 格、2 倍密度画（约 250dp × 120dp ⇒ 500 × 240 像素）。

跑法（用 DSH 自带的 Python）：
    python tool/make_widget_preview.py
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFont

SCALE = 2
W, H = 250 * SCALE, 126 * SCALE
RADIUS = 20 * SCALE
BORDER = "#E5E7EB"
BG = "#FFFFFF"

# 与 lib/theme.dart 的 AppTheme.courseColors / widget_today.xml 一致
INK = "#111827"
WEEK = "#6366F1"
LOC = "#6B7280"
TIME = "#374151"
FOOT = "#9CA3AF"
BARS = ["#F59E0B", "#10B981", "#3B82F6"]

# 两行就够示意了：4×2 格的卡片高度放不下三行 + 页脚（真实小组件里超出的行本来也会被裁掉）
ROWS = [
    ("人工智能导论", "明德楼B216", "08:00"),
    ("高等数学Ⅰ（上）", "明德楼A203", "10:00"),
]

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyhbd.ttc",
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    raise SystemExit("找不到可用的中文字体，检查 FONT_CANDIDATES")


def main() -> None:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 白卡 + 圆角 + 描边（对应 res/drawable/widget_bg.xml）
    d.rounded_rectangle(
        [(1, 1), (W - 2, H - 2)], radius=RADIUS, fill=BG, outline=BORDER, width=SCALE
    )

    pad = 12 * SCALE
    bold = load_font(13 * SCALE)
    small = load_font(10 * SCALE)
    tiny = load_font(9 * SCALE)

    # 第一行：日期（左）+ 周次（右）
    d.text((pad, pad - 2), "10月8日 周三", font=bold, fill=INK)
    week = "第3周"
    d.text(
        (W - pad - d.textlength(week, font=small), pad), week, font=small, fill=WEEK
    )

    # 三行课程
    y = pad + 22 * SCALE
    for (name, loc, time), color in zip(ROWS, BARS):
        bar_h = 28 * SCALE
        d.rounded_rectangle(
            [(pad, y + 2), (pad + 3 * SCALE, y + bar_h)], radius=2 * SCALE, fill=color
        )
        x = pad + 8 * SCALE
        d.text((x, y), name, font=bold, fill=INK)
        d.text((x, y + 15 * SCALE), loc, font=small, fill=LOC)
        d.text(
            (W - pad - d.textlength(time, font=small), y + 4 * SCALE),
            time,
            font=small,
            fill=TIME,
        )
        y += bar_h + 6 * SCALE

    # 页脚
    foot = "共 2 门 · 点开看全部"
    d.text((pad, H - pad - 11 * SCALE), foot, font=tiny, fill=FOOT)

    out = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "android",
        "app",
        "src",
        "main",
        "res",
        "drawable-nodpi",
        "widget_preview.png",
    )
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print(f"OK {out} {os.path.getsize(out)} bytes {W}x{H}")


if __name__ == "__main__":
    main()
