# 临时脚本（不进仓库）：生成一张「演示用纸质课表照片」，用来在模拟器上拍 README 的 OCR 截图。
# 内容全部虚构（示例老师 / 明德楼A101 之类），不含任何真实课程与教师。
import sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else r"D:\DSH\shots\demo_timetable_photo.png"

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\msyhbd.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
]


def load_font(size):
    for p in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    raise SystemExit("no font")


W, H = 1240, 1650
img = Image.new("RGB", (W, H), (250, 249, 246))
d = ImageDraw.Draw(img)

f_title = load_font(56)
f_sub = load_font(34)
f_row = load_font(38)
f_small = load_font(26)

d.text((60, 70), "2026-2027 学年第一学期课表", font=f_title, fill=(30, 30, 30))
d.text((60, 150), "演示专业（示例数据）", font=f_sub, fill=(90, 90, 90))
d.line((60, 210, W - 60, 210), fill=(120, 120, 120), width=2)

rows = [
    "星期一  高等数学    明德楼A101  (1-2节) 1-18周",
    "星期一  大学英语    明德楼B203  (3-4节) 1-18周",
    "星期二  程序设计基础 格致楼205   (1-4节) 1-18周",
    "星期二  大学物理    明德楼B314  (5-6节) 1-18周",
    "星期三  体育        田径场      (3-4节) 1-18周",
    "星期三  中国近现代史纲要 明德楼A203 (7-8节) 1-18周",
    "星期四  数据结构    格致楼113   (1-2节) 1-18周",
    "星期四  电路分析    实验楼301   (5-6节) 1-18周",
    "星期五  形势与政策   培训中心    (1-2节) 1-8周",
    "星期五  大学物理实验 实验楼202   (3-4节) 9-18周",
    "星期六  线性代数    明德楼A105  (1-2节) 1-9周",
]
y = 290
for r in rows:
    d.text((70, y), r, font=f_row, fill=(40, 40, 40))
    d.line((60, y + 62, W - 60, y + 62), fill=(215, 215, 215), width=1)
    y += 82

d.text((70, y + 60), "本表为演示数据，仅用于界面示意。", font=f_small, fill=(140, 140, 140))

img.save(OUT)
print(f"saved {OUT} {img.size} {len(open(OUT, 'rb').read())} bytes")
