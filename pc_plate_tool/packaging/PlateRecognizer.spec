# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller 打包配置：把车牌识别上位机打成 onedir 绿色版。

用法（在 pc_plate_tool 目录下）：
  python -m PyInstaller --noconfirm --clean ^
      --distpath packaging/dist --workpath packaging/build packaging/PlateRecognizer.spec

产物：packaging/dist/PlateRecognizer/PlateRecognizer.exe
"""

import os

ROOT = os.path.dirname(os.path.abspath(SPECPATH))
VENDOR = os.path.join(ROOT, "vendor", "Chinese_license_plate_detection_recognition-main")

# 打包时需要随程序携带的运行时数据（模型权重、中文字体）
datas = [
    (os.path.join(VENDOR, "weights"), "vendor/weights"),
    (os.path.join(VENDOR, "fonts"), "vendor/fonts"),
]

# 第三方代码里是函数内 import，显式声明更稳妥
hiddenimports = [
    "detect_plate",
    "plate_recognition",
    "plate_recognition.plate_rec",
    "plate_recognition.plateNet",
    "plate_recognition.double_plate_split_merge",
    "models",
    "models.common",
    "models.experimental",
    "models.yolo",
    "utils",
    "utils.autoanchor",
    "utils.cv_puttext",
    "utils.datasets",
    "utils.general",
    "utils.google_utils",
    "utils.metrics",
    "utils.plots",
    "utils.torch_utils",
    "yaml",
    "tqdm",
    "requests",
    "pandas",
    "seaborn",
    "matplotlib",
    "matplotlib.pyplot",
    "scipy.cluster.vq",
    "scipy.signal",
    "thop",
    "psutil",
    "torchvision",
    "serial",
    "serial.tools",
    "serial.tools.list_ports",
]

# 与本工具无关、体积可观的模块，排除以缩小包体
excludes = [
    "IPython",
    "ipykernel",
    "jupyter",
    "jupyter_client",
    "jupyter_core",
    "nbconvert",
    "nbformat",
    "notebook",
    "qtpy",
    "PyQt5",
    "PyQt6",
    "PySide2",
    "PySide6",
    "wx",
    "pytest",
    "sphinx",
    "docutils",
    "matplotlib.backends.backend_qt5agg",
    "matplotlib.backends.backend_qtagg",
    "matplotlib.backends.backend_webagg",
]

a = Analysis(
    [os.path.join(ROOT, "plate_gui.py")],
    pathex=[ROOT, VENDOR],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="PlateRecognizer",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=os.path.join(ROOT, "packaging", "app.ico"),
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="PlateRecognizer",
)
