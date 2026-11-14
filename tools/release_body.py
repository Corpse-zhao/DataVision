"""生成 release 正文。

两个 job（iOS / Android）都会跑一遍，所以正文内容必须一模一样，
否则后跑完的那个会把前一个的说明覆盖掉。唯一的来源就是仓库根目录的 version.json。
"""

import json
import pathlib
import sys


def main() -> None:
    version = sys.argv[1] if len(sys.argv) > 1 else ""
    notes = ""
    page = "https://github.com/Corpse-zhao/DataVision/releases"

    path = pathlib.Path("version.json")
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            version = data.get("version") or version
            notes = (data.get("notes") or "").strip()
            page = data.get("page") or page
        except json.JSONDecodeError:
            pass

    lines = [
        f"数据视界 v{version}",
        "",
        notes if notes else "（这一版没写更新说明）",
        "",
        "**安装**",
        "- Android：直接装 APK，已用固定密钥签名，可覆盖升级",
        "- iOS：用全能签重签 IPA 安装，Bundle ID 保持不变即可覆盖、数据不丢",
        "",
        f"下载页：{page}",
        "",
        "控制器：凌博 / 远驱 / VESC 系　　保护板：蚂蚁 / 极空",
    ]

    pathlib.Path("release-body.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"release body written for v{version}")


if __name__ == "__main__":
    main()
