"""生成 App 图标：深蓝底 + 电池轮廓 + 心跳线（控制器/保护板数据的意思）。

用法：python tools/make_icon.py
输出：
  android/app/src/main/res/mipmap-*/ic_launcher.png
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png
  assets/icon/icon-1024.png（母版，改设计只改这里）
"""

import json
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER = 1024


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def draw_master(size=MASTER):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 圆角方块 + 竖向渐变
    radius = int(size * 0.22)
    grad = Image.new("RGB", (1, size))
    top = (9, 20, 38)
    bottom = (18, 52, 96)
    for y in range(size):
        grad.putpixel((0, y), lerp(top, bottom, y / max(size - 1, 1)))
    grad = grad.resize((size, size))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # 电池轮廓
    bw, bh = int(size * 0.52), int(size * 0.34)
    bx, by = (size - bw) // 2 - int(size * 0.03), (size - bh) // 2
    stroke = int(size * 0.055)
    d.rounded_rectangle(
        [bx, by, bx + bw, by + bh],
        radius=int(size * 0.07),
        outline=(235, 245, 255, 255),
        width=stroke,
    )
    # 正极凸起
    nub_w, nub_h = int(size * 0.055), int(size * 0.13)
    nx = bx + bw + int(size * 0.012)
    d.rounded_rectangle(
        [nx, by + (bh - nub_h) // 2, nx + nub_w, by + (bh + nub_h) // 2],
        radius=int(size * 0.02),
        fill=(235, 245, 255, 255),
    )

    # 心跳线（数据流）
    cy = by + bh // 2
    pts = [
        (bx + int(size * 0.06), cy),
        (bx + int(size * 0.16), cy),
        (bx + int(size * 0.22), cy - int(size * 0.10)),
        (bx + int(size * 0.30), cy + int(size * 0.10)),
        (bx + int(size * 0.38), cy - int(size * 0.03)),
        (bx + int(size * 0.43), cy),
        (bx + int(size * 0.45), cy),
    ]
    d.line(pts, fill=(64, 224, 208, 255), width=int(size * 0.045), joint="curve")

    # 底部三根小柱子（像电量格 / 数据条）
    bar_w = int(size * 0.035)
    gap = int(size * 0.028)
    base_y = by + bh + int(size * 0.10)
    total = 3 * bar_w + 2 * gap
    sx = (size - total) // 2
    for i in range(3):
        h = int(size * (0.035 + 0.022 * i))
        x = sx + i * (bar_w + gap)
        d.rounded_rectangle(
            [x, base_y - h, x + bar_w, base_y],
            radius=bar_w // 2,
            fill=(64, 224, 208, 235),
        )

    return img


def main():
    master = draw_master()
    os.makedirs(os.path.join(ROOT, "assets", "icon"), exist_ok=True)
    master.save(os.path.join(ROOT, "assets", "icon", "icon-1024.png"))

    android = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in android.items():
        out = os.path.join(ROOT, "android", "app", "src", "main", "res", folder, "ic_launcher.png")
        master.resize((px, px), Image.LANCZOS).save(out)
        print("android", out, px)

    icon_dir = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    contents = json.load(open(os.path.join(icon_dir, "Contents.json"), encoding="utf-8"))
    for entry in contents["images"]:
        size = entry.get("size")
        scale = entry.get("scale")
        if not size or not scale:
            continue
        base = float(size.split("x")[0])
        px = int(round(base * int(scale.rstrip("x"))))
        name = entry.get("filename") or f"Icon-App-{size}@{scale}.png"
        entry["filename"] = name
        flat = Image.new("RGB", (px, px), (9, 20, 38))
        flat.paste(master.resize((px, px), Image.LANCZOS), (0, 0), master.resize((px, px), Image.LANCZOS))
        flat.save(os.path.join(icon_dir, name))
        print("ios", name, px)
    json.dump(contents, open(os.path.join(icon_dir, "Contents.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
