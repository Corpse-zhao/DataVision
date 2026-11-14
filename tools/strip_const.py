"""去掉包含 AppColors 的 const 表达式（AppColors 现在是运行时 getter）。"""
import re
import sys
from pathlib import Path

ROOT = Path("C:/Users/Administrator/WorkBuddy/2026-11-14-13-24-47/DataVision")
FILES = sorted(ROOT.glob("lib/**/*.dart"))

OPEN = {"(": ")", "[": "]", "{": "}"}


def block_extent(src: str, start: int):
    """从 start（左括号位置）找到配对的右括号位置。"""
    depth = 0
    i = start
    while i < len(src):
        c = src[i]
        if c in OPEN:
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i
        elif c == "'" or c == '"':
            q = c
            i += 1
            while i < len(src):
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == q:
                    break
                i += 1
        i += 1
    return -1


def process(path: Path):
    src = path.read_text(encoding="utf-8")
    drops = []
    for m in re.finditer(r"\bconst\b", src):
        j = m.end()
        while j < len(src) and src[j] in " \n\t":
            j += 1
        # 读标识符
        k = j
        while k < len(src) and (src[k].isalnum() or src[k] in "_.$<>"):
            k += 1
        # 允许泛型后接括号
        while k < len(src) and src[k] in " \n\t":
            k += 1
        if k >= len(src) or src[k] not in "([{":
            continue  # 变量声明等，跳过
        end = block_extent(src, k)
        if end < 0:
            continue
        body = src[j:end + 1]
        if "AppColors." not in body:
            continue
        # 构造器声明（默认参数）不动
        if "this." in body or "super." in body or " required " in body:
            continue
        drops.append((m.start(), m.end()))

    if not drops:
        return 0
    out = []
    prev = 0
    for s, e in drops:
        out.append(src[prev:s])
        prev = e
    out.append(src[prev:])
    txt = "".join(out)
    txt = re.sub(r"[ \t]{2,}(?=\S)", lambda m: m.group(0), txt)  # 保留原样，仅去多余空白
    txt = txt.replace("const  ", "const ")
    path.write_text(txt, encoding="utf-8")
    return len(drops)


total = 0
for f in FILES:
    n = process(f)
    if n:
        print(f"{f.relative_to(ROOT)}: -{n} const")
    total += n
print("total", total)
