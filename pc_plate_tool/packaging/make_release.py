# -*- coding: utf-8 -*-
"""一键构建绿色免安装发布包。

流程：生成图标 → PyInstaller 打包 → 组装发布目录 → 压成 zip

用法（在 pc_plate_tool 目录下，用自带 venv 的 python 运行）：
  .venv/Scripts/python.exe packaging/make_release.py              # 完整构建
  .venv/Scripts/python.exe packaging/make_release.py --skip-build # 只重新组装与压缩

产物：
  packaging/release/车牌识别上位机/                绿色版目录（可直接运行）
  packaging/release/车牌识别上位机_v1.0.0_win64.zip 分发给队友的压缩包
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parent
ROOT = BASE.parent
VENDOR = ROOT / "vendor" / "Chinese_license_plate_detection_recognition-main"

DIST_DIR = BASE / "dist"
BUILD_DIR = BASE / "build"
RELEASE_DIR = BASE / "release"
APP_NAME = "车牌识别上位机"
EXE_NAME = "PlateRecognizer"
VERSION = "1.0.0"

# 复制第三方源码用于 GPL 合规时跳过的目录（二进制/无关内容）
SOURCE_SKIP_DIRS = {
    "__pycache__",
    ".git",
    "imgs",
    "image",
    "readme",
    "weights",
    "widerface_evaluate",
    "torch2trt",
    "data",
    "runs",
    "fonts",
}

USAGE_TEXT = """车牌识别上位机 v{version} 使用说明
========================================

一、运行环境
----------------------------------------
  - Windows 10 / 11 64 位
  - 无需安装 Python，无需联网（模型已随包携带）
  - 纯 CPU 推理，单张图片约 0.2 - 0.5 秒（首次识别需加载模型，约 2 - 5 秒）

二、快速开始
----------------------------------------
  1.（建议）双击「创建桌面快捷方式.bat」，之后双击桌面上的「车牌识别上位机」即可打开；
     也可以直接双击本目录里的 PlateRecognizer.exe
  2. 点「载入样例」可直接载入随包的样例车牌图片，用来自检程序是否正常
     （也可以点「导入图片」或「导入文件夹」选自己的图片）
  3. 点「开始识别」，左侧显示标注后的结果图，右侧表格显示车牌号与各项置信度
  4. 结果自动保存：标注图写入本目录下的 outputs\\ 里
     如需汇总数据，再点「导出 JSON」或「导出 CSV」

  重要：整个文件夹要一起保留。请把 zip 解压到固定位置（例如 D:\\车牌识别上位机）后再用，
  不要在压缩包内直接双击；也不要只把小 exe 单独复制出去，它需要 _internal 文件夹。

三、界面说明
----------------------------------------
  导入图片 / 导入文件夹 : 选择待识别的图片（可勾选「递归子目录」）
  载入样例              : 载入随包样例图片，用于快速验证程序可用
  开始识别              : 加载模型并逐张识别，进度显示在底部状态栏
  清空                  : 清空列表与结果
  识别颜色              : 是否同时识别车牌颜色（蓝/黄/绿/白等）
  输出目录              : 标注图保存位置，默认是本程序旁边的 outputs
  导出 JSON / 导出 CSV  : 把识别结果汇总导出（含车牌号、置信度、颜色、耗时）
  结果表格              : 点某一行可跳到对应图片的预览

四、识别结果含义
----------------------------------------
  车牌号      : 识别出的完整车牌（含省份简称与 学/警/港/澳/使/领 等后缀）
  类型        : 单层 / 双层
  检测分      : 车牌定位的把握程度
  识别分      : 字符识别的整体把握程度（逐字符置信度均值）
  颜色 / 颜色分: 车牌颜色及该判断的置信度
  耗时        : 单张图片检测 + 识别的耗时（毫秒）

  识别分低于约 0.85 或字符数不是 7 / 8 位时，建议人工复核。

五、常见问题
----------------------------------------
  Q: 桌面快捷方式怎么建？
  A: 双击「创建桌面快捷方式.bat」即可，脚本会在桌面生成「车牌识别上位机」图标。
     如果之后移动了程序文件夹，重新双击一次这个 bat 重建即可。

  Q: 双击没反应？
  A: 首次启动需要解压运行库，请等待数秒；若仍无窗口，检查是否被杀毒软件拦截，
     可把整个文件夹加入白名单。

  Q: 提示缺少 xxx.dll / 程序闪退？
  A: 请确认解压时保留了 _internal 文件夹（不能只复制 exe），
     并且解压路径不要出现异常字符。

  Q: 识别不出来？
  A: 车牌在图中过小、模糊、强反光或角度过大都会影响效果；
     可先点「载入样例」确认程序本身正常，再换更清晰的正视图片试。

六、第三方组件与许可
----------------------------------------
  本程序使用开源项目 Chinese_license_plate_detection_recognition
  （车牌检测 YOLOv5 + 车牌字符识别 CRNN），该项目以 GPL-3.0 许可发布。
  对应的许可证全文与该项目的完整 Python 源码随包提供，见：
      第三方许可与源码\\
  该项目的模型由公开数据集训练，如需更高精度模型或商用授权，请联系原作者。

  本程序自身代码位于工程目录 pc_plate_tool\\（plate_engine.py / plate_gui.py 等）。
"""

# 桌面快捷方式的一键脚本。.bat 内容刻意保持纯 ASCII：中文注释在 cp936 控制台下会乱码。
SHORTCUT_BAT = """@echo off
rem Create a desktop shortcut for this portable build.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0create_shortcut.ps1" -AppDir "%~dp0."
echo.
pause
"""


def step_icon() -> None:
    icon = BASE / "app.ico"
    if icon.is_file():
        print(f"[1/4] 图标已存在：{icon}")
        return
    print("[1/4] 生成应用图标 ...")
    subprocess.run([sys.executable, str(BASE / "app_icon.py")], check=True, cwd=str(ROOT))


def step_build() -> None:
    print("[2/4] PyInstaller 打包（首次约需数分钟）...")
    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--distpath",
        str(DIST_DIR),
        "--workpath",
        str(BUILD_DIR),
        str(BASE / "PlateRecognizer.spec"),
    ]
    subprocess.run(cmd, check=True, cwd=str(ROOT))

    built = DIST_DIR / EXE_NAME / f"{EXE_NAME}.exe"
    if not built.is_file():
        raise SystemExit(f"打包失败：未找到 {built}")
    print(f"      已生成 {built}")


def copy_vendor_source(dest: Path) -> None:
    """复制第三方项目的 Python 源码与许可证，满足 GPL-3.0 的源码提供要求。"""
    dest.mkdir(parents=True, exist_ok=True)
    for current, dirs, files in os.walk(VENDOR):
        dirs[:] = [d for d in dirs if d not in SOURCE_SKIP_DIRS]
        rel = Path(current).relative_to(VENDOR)
        (dest / rel).mkdir(parents=True, exist_ok=True)
        for name in files:
            if name.endswith((".py", ".txt", ".md")) or name == "LICENSE":
                shutil.copy2(Path(current) / name, dest / rel / name)


def step_assemble() -> Path:
    print("[3/4] 组装发布目录 ...")
    if RELEASE_DIR.exists():
        shutil.rmtree(RELEASE_DIR)
    app_dir = RELEASE_DIR / APP_NAME
    app_dir.mkdir(parents=True)

    # 主程序
    shutil.copytree(DIST_DIR / EXE_NAME, app_dir, dirs_exist_ok=True)

    # 样例图片（放到用户可见目录，供界面「载入样例」使用）
    samples_src = VENDOR / "imgs"
    samples_dst = app_dir / "样例图片"
    samples_dst.mkdir()
    count = 0
    for item in sorted(samples_src.iterdir()):
        if item.is_file() and item.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp"}:
            shutil.copy2(item, samples_dst / item.name)
            count += 1

    # 输出目录
    (app_dir / "outputs").mkdir()

    # 第三方源码与许可
    copy_vendor_source(app_dir / "第三方许可与源码" / VENDOR.name)

    # 桌面快捷方式（脚本随包，队友解压后双击 bat 自助创建）
    shutil.copy2(BASE / "create_shortcut.ps1", app_dir / "create_shortcut.ps1")
    (app_dir / "创建桌面快捷方式.bat").write_text(SHORTCUT_BAT, encoding="ascii")

    # 使用说明
    (app_dir / "使用说明.txt").write_text(
        USAGE_TEXT.format(version=VERSION), encoding="utf-8-sig"
    )

    print(f"      样例图片 {count} 张，程序目录 {app_dir}")
    return app_dir


def zip_tree(src_dir: Path, zip_path: Path, root_name: str) -> None:
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for current, dirs, files in os.walk(src_dir):
            rel = Path(current).relative_to(src_dir)
            arc_dir = (Path(root_name) / rel).as_posix()
            if not dirs and not files:  # 保留空目录（如 outputs）
                archive.writestr(arc_dir.rstrip("/") + "/", b"")
            for name in files:
                file_path = Path(current) / name
                archive.write(file_path, (Path(arc_dir) / name).as_posix())


def step_zip(app_dir: Path) -> Path:
    print("[4/4] 压缩发布包 ...")
    zip_path = RELEASE_DIR / f"{APP_NAME}_v{VERSION}_win64.zip"
    if zip_path.exists():
        zip_path.unlink()
    zip_tree(app_dir, zip_path, APP_NAME)
    size_mb = zip_path.stat().st_size / 1048576
    print(f"      完成：{zip_path}  ({size_mb:.0f} MB)")
    return zip_path


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="构建车牌识别上位机绿色发布包")
    parser.add_argument("--skip-build", action="store_true", help="跳过 PyInstaller，只用已有 dist 重新组装")
    args = parser.parse_args(argv)

    if not VENDOR.is_dir():
        raise SystemExit(f"未找到第三方代码目录：{VENDOR}")

    step_icon()
    if args.skip_build:
        print("[2/4] 跳过打包（--skip-build）")
        if not (DIST_DIR / EXE_NAME).is_dir():
            raise SystemExit(f"未找到已有产物：{DIST_DIR / EXE_NAME}")
    else:
        step_build()
    app_dir = step_assemble()
    step_zip(app_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
