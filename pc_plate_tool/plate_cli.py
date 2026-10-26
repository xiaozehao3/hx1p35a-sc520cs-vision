# -*- coding: utf-8 -*-
"""车牌识别命令行工具。

示例：
  # 单张图片，标注图与结果写入 outputs/
  python plate_cli.py --input car.jpg

  # 整个目录（含子目录），同时导出 JSON 与 CSV
  python plate_cli.py --input imgs/ --recursive --json outputs/result.json --csv outputs/result.csv

  # 只识别不识别颜色，并过滤低置信度
  python plate_cli.py --input imgs/ --no-color --min-conf 0.6
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plate_engine import (  # noqa: E402
    PlateRecognizer,
    default_output_dir,
    list_images,
    save_results_csv,
    save_results_json,
    write_image,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="车牌检测与识别（图片/文件夹）")
    parser.add_argument("--input", required=True, help="图片文件或图片目录")
    parser.add_argument("--output", default=str(default_output_dir()), help="标注图与结果输出目录（默认为程序旁的 outputs）")
    parser.add_argument("--detect-model", default=None, help="检测模型路径，默认使用内置权重")
    parser.add_argument("--rec-model", default=None, help="识别模型路径，默认使用内置权重")
    parser.add_argument("--img-size", type=int, default=640, help="检测网络输入尺寸（默认 640）")
    parser.add_argument("--no-color", action="store_true", help="不识别车牌颜色")
    parser.add_argument("--min-conf", type=float, default=0.0, help="识别置信度下限，低于该值的结果不导出")
    parser.add_argument("--recursive", action="store_true", help="目录模式下递归子目录")
    parser.add_argument("--json", default=None, help="结果 JSON 输出路径")
    parser.add_argument("--csv", default=None, help="结果 CSV 输出路径")
    parser.add_argument("--device", default=None, help="cpu / cuda，默认自动选择")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)

    files = list_images(args.input, recursive=args.recursive)
    if not files:
        print(f"[ERROR] 未找到图片: {args.input}")
        return 2

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"加载模型 ... (device={args.device or 'auto'}, img_size={args.img_size})")
    recognizer = PlateRecognizer(
        detect_model=args.detect_model,
        rec_model=args.rec_model,
        img_size=args.img_size,
        is_color=not args.no_color,
        device=args.device,
    )

    csv_rows = []
    all_results = []
    total_hits = 0
    for index, path in enumerate(files, 1):
        try:
            annotated, results, elapsed_ms = recognizer.recognize_file(path)
        except Exception as exc:  # noqa: BLE001 - 单张失败不应中断批处理
            print(f"[{index}/{len(files)}] {path.name} 处理失败: {exc}")
            continue

        kept = [r for r in results if r["rec_conf"] >= args.min_conf]
        total_hits += len(kept)
        write_image(out_dir / path.name, annotated)

        plates = " | ".join(f"{r['plate_no']}({r['plate_color']},{r['rec_conf']:.2f})" for r in kept)
        print(f"[{index}/{len(files)}] {path.name}  {len(kept)} 个车牌  {elapsed_ms:.0f} ms  {plates}")

        for r in kept:
            row = dict(r)
            row["image"] = path.name
            row["elapsed_ms"] = round(elapsed_ms, 1)
            csv_rows.append(row)
        all_results.append(
            {
                "image": path.name,
                "image_path": str(path),
                "elapsed_ms": round(elapsed_ms, 1),
                "plates": kept,
            }
        )

    if args.json:
        save_results_json(
            all_results,
            args.json,
            extra={"image_count": len(files), "plate_count": total_hits},
        )
        print(f"JSON -> {args.json}")
    if args.csv:
        save_results_csv(csv_rows, args.csv)
        print(f"CSV  -> {args.csv}")

    print(f"完成：处理 {len(files)} 张图片，识别出 {total_hits} 个车牌，标注图位于 {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
