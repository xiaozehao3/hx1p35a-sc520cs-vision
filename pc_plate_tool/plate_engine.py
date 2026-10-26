# -*- coding: utf-8 -*-
"""PC 车牌检测 + 识别核心引擎。

封装 vendor/Chinese_license_plate_detection_recognition-main 中的：
  - YOLOv5 车牌检测模型  weights/plate_detect.pt
  - CRNN 车牌字符/颜色识别模型  weights/plate_rec_color.pth

对外提供结构化结果（车牌号、逐字符置信度、检测置信度、车牌颜色、角点、耗时），
以及标注图绘制与 JSON/CSV 导出。中文标注使用仓库自带 platech.ttf 的绝对路径，
因此本模块不依赖当前工作目录。
"""

from __future__ import annotations

import csv
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

VENDOR_REPO = "Chinese_license_plate_detection_recognition-main"


def _resolve_dirs() -> Tuple[Path, Path, Path]:
    """解析运行目录，返回 (用户可见目录, 资源目录, vendor 目录)。

    - 源码运行：三者都位于本文件所在目录。
    - 打包运行（PyInstaller）：模型/字体等数据被放到 sys._MEIPASS 下，而用户可见目录
      是可执行文件所在目录，默认输出目录与样例目录都应基于它。
    """
    if getattr(sys, "frozen", False):
        app_dir = Path(sys.executable).resolve().parent
        res_dir = Path(getattr(sys, "_MEIPASS", app_dir))
        vendor_dir = res_dir / "vendor"
    else:
        app_dir = res_dir = Path(__file__).resolve().parent
        vendor_dir = res_dir / "vendor" / VENDOR_REPO
    return app_dir, res_dir, vendor_dir


APP_DIR, RES_DIR, VENDOR_DIR = _resolve_dirs()
DEFAULT_DETECT_MODEL = VENDOR_DIR / "weights" / "plate_detect.pt"
DEFAULT_REC_MODEL = VENDOR_DIR / "weights" / "plate_rec_color.pth"
FONT_PATH = VENDOR_DIR / "fonts" / "platech.ttf"

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}

if str(VENDOR_DIR) not in sys.path:
    sys.path.insert(0, str(VENDOR_DIR))

# 静态导入第三方推理代码：既保证运行期可用，也让打包工具能完整分析依赖图。
# 失败时不让模块导入直接崩溃，而是记录下来，由 PlateRecognizer 给出可读的错误提示。
try:
    import detect_plate as _vendor_detect
    from plate_recognition import plate_rec as _vendor_rec

    _VENDOR_IMPORT_ERROR: Optional[BaseException] = None
except BaseException as _exc:  # pragma: no cover - 依赖缺失时才会命中
    _vendor_detect = None
    _vendor_rec = None
    _VENDOR_IMPORT_ERROR = _exc

# 允许在 torch 2.6+ 上继续加载 yolov5 的旧式 checkpoint（内含 argparse.Namespace）。
try:  # pragma: no cover - 仅在较新 torch 上生效
    import torch as _torch

    if hasattr(_torch.serialization, "add_safe_globals"):
        import argparse as _argparse

        _torch.serialization.add_safe_globals([_argparse.Namespace, getattr(_torch, "device", object)])
except Exception:  # pragma: no cover
    pass


class PlateRecognizer:
    """车牌检测 + 识别封装（模型只加载一次，可重复调用）。"""

    def __init__(
        self,
        detect_model: Optional[str] = None,
        rec_model: Optional[str] = None,
        img_size: int = 640,
        is_color: bool = True,
        device: Optional[str] = None,
    ) -> None:
        import torch

        if _vendor_detect is None or _vendor_rec is None:
            raise RuntimeError(f"未能加载车牌推理代码，请检查依赖与 vendor 目录: {_VENDOR_IMPORT_ERROR}")
        self._detect_module = _vendor_detect
        self._rec_module = _vendor_rec

        self.detect_model_path = Path(detect_model) if detect_model else DEFAULT_DETECT_MODEL
        self.rec_model_path = Path(rec_model) if rec_model else DEFAULT_REC_MODEL
        if not self.detect_model_path.is_file():
            raise FileNotFoundError(f"检测模型不存在: {self.detect_model_path}")
        if not self.rec_model_path.is_file():
            raise FileNotFoundError(f"识别模型不存在: {self.rec_model_path}")

        self.img_size = int(img_size)
        self.is_color = bool(is_color)
        if device:
            self.device = torch.device(device)
        else:
            self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        self.detect_model = self._detect_module.load_model(str(self.detect_model_path), self.device)
        self.rec_model = self._rec_module.init_model(
            self.device, str(self.rec_model_path), is_color=self.is_color
        )

    # ------------------------------------------------------------------ 推理
    def recognize(self, image) -> List[Dict[str, Any]]:
        """对 BGR 图像做检测+识别，返回结构化结果列表。"""
        import numpy as np

        raw = self._raw_recognize(image)
        results: List[Dict[str, Any]] = []
        for item in raw:
            rec_conf = item.get("rec_conf")
            if rec_conf is None:
                char_confs: List[float] = []
            else:
                char_confs = [round(float(x), 4) for x in np.asarray(rec_conf).ravel()]
            plain = item["plate_no"]
            results.append(
                {
                    "plate_no": plain,
                    "plate_plain": plain,
                    "char_count": len(plain),
                    "detect_conf": round(float(item["detect_conf"]), 4),
                    "rec_conf": round(float(np.mean(char_confs)), 4) if char_confs else 0.0,
                    "min_char_conf": round(min(char_confs), 4) if char_confs else 0.0,
                    "char_confs": char_confs,
                    "plate_color": item.get("plate_color", "") or "",
                    "color_conf": round(float(item.get("color_conf", 0.0) or 0.0), 4),
                    "plate_type": int(item.get("plate_type", 0)),
                    "rect": [int(v) for v in item["rect"]],
                    "landmarks": [[int(p[0]), int(p[1])] for p in item["landmarks"]],
                }
            )
        results.sort(key=lambda r: (r["rect"][0], r["rect"][1]))
        return results

    def _raw_recognize(self, image) -> List[Dict[str, Any]]:
        return self._detect_module.detect_Recognition_plate(
            self.detect_model,
            image.copy(),
            self.device,
            self.rec_model,
            self.img_size,
            is_color=self.is_color,
        )

    def recognize_file(self, image_path) -> Tuple[Any, List[Dict[str, Any]], float]:
        """识别单张图片，返回 (标注图, 结果列表, 耗时毫秒)。"""
        import cv2

        image = read_image(image_path)
        if image is None:
            raise ValueError(f"无法读取图片: {image_path}")
        started = time.time()
        results = self.recognize(image)
        elapsed_ms = (time.time() - started) * 1000.0
        annotated = self.annotate(image, results)
        return annotated, results, elapsed_ms

    # ------------------------------------------------------------------ 绘制
    def annotate(self, image, results: List[Dict[str, Any]]):
        """在图像上绘制车牌框、角点与识别文本，返回新图。"""
        import cv2

        colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)]
        canvas = image.copy()
        h_img, w_img = canvas.shape[:2]
        for res in results:
            x1, y1, x2, y2 = res["rect"]
            pad_w = 0.05 * (x2 - x1)
            pad_h = 0.11 * (y2 - y1)
            bx1 = max(0, int(x1 - pad_w))
            by1 = max(0, int(y1 - pad_h))
            bx2 = min(w_img, int(x2 + pad_w))
            by2 = min(h_img, int(y2 + pad_h))
            for i, point in enumerate(res["landmarks"]):
                cv2.circle(canvas, (int(point[0]), int(point[1])), 5, colors[i % 4], -1)
            cv2.rectangle(canvas, (bx1, by1), (bx2, by2), (0, 0, 255), 2)

            label = res["plate_no"]
            if res["plate_color"]:
                label += f" {res['plate_color']}"
            if res["plate_type"] == 1:
                label += " 双层"
            label += f" {res['rec_conf']:.2f}"

            text_size = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)[0]
            if bx1 + text_size[0] > w_img:
                bx1 = int(w_img - text_size[0]) - 2
            top = int(by1 - round(1.6 * text_size[1]))
            cv2.rectangle(
                canvas,
                (bx1, top),
                (bx1 + int(round(1.2 * text_size[0])), by1 + text_size[1]),
                (255, 255, 255),
                cv2.FILLED,
            )
            canvas = draw_chinese_text(canvas, label, bx1, top, (0, 0, 0), 21)
        return canvas


# ---------------------------------------------------------------------- 工具函数
def sample_images_dir() -> Optional[Path]:
    """返回样例图片目录；优先用随包分发的「样例图片」，其次用 vendor 自带的 imgs。"""
    for candidate in (APP_DIR / "样例图片", VENDOR_DIR / "imgs"):
        if candidate.is_dir():
            return candidate
    return None


def default_output_dir() -> Path:
    """默认输出目录：可执行文件（或源码）旁边的 outputs。"""
    return APP_DIR / "outputs"


def draw_chinese_text(img, text: str, left: int, top: int, color=(0, 0, 0), text_size: int = 20):
    """用仓库自带中文字体绘制文本（绝对路径，不依赖 cwd）。"""
    import cv2
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont

    if isinstance(img, np.ndarray):
        img = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype(str(FONT_PATH), text_size, encoding="utf-8")
    except OSError:
        font = ImageFont.load_default()
    draw.text((left, top), text, color, font=font)
    return cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)


def read_image(path) -> Optional[Any]:
    """读取图片，兼容中文路径与 4 通道 PNG。"""
    import cv2
    import numpy as np

    path = str(path)
    data = np.fromfile(path, dtype=np.uint8)
    if data.size == 0:
        return None
    image = cv2.imdecode(data, cv2.IMREAD_COLOR)
    return image


def write_image(path, image) -> bool:
    """写出图片，兼容中文路径。"""
    import cv2

    ext = Path(path).suffix or ".jpg"
    ok, buffer = cv2.imencode(ext, image)
    if not ok:
        return False
    buffer.tofile(str(path))
    return True


def list_images(target, recursive: bool = False) -> List[Path]:
    """列出文件或目录下的图片路径。"""
    target = Path(target)
    if target.is_file():
        return [target]
    if not target.is_dir():
        return []
    it = target.rglob("*") if recursive else target.glob("*")
    files = [p for p in it if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES]
    return sorted(files)


def save_results_json(results: List[Dict[str, Any]], path, extra: Optional[Dict[str, Any]] = None) -> None:
    payload: Dict[str, Any] = {"results": results}
    if extra:
        payload.update(extra)
    Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


CSV_FIELDS = [
    "image",
    "plate_plain",
    "plate_color",
    "plate_type",
    "detect_conf",
    "rec_conf",
    "min_char_conf",
    "color_conf",
    "rect",
    "elapsed_ms",
]


def save_results_csv(rows: List[Dict[str, Any]], path) -> None:
    with open(path, "w", newline="", encoding="utf-8-sig") as fp:
        writer = csv.DictWriter(fp, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for row in rows:
            out = {k: row.get(k, "") for k in CSV_FIELDS}
            out["rect"] = " ".join(str(v) for v in row.get("rect", []))
            writer.writerow(out)
