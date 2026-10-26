# -*- coding: utf-8 -*-
"""车牌识别上位机（Tkinter GUI）。

功能：
  - 导入单张图片或整个文件夹（可选递归）
  - 一键识别：车牌检测 + 字符/颜色识别
  - 左侧预览标注结果图，右侧表格展示车牌号、置信度、颜色、耗时
  - 导出 JSON / CSV 结果，标注图自动写入输出目录

运行：python plate_gui.py
"""

from __future__ import annotations

import queue
import sys
import threading
import traceback
from pathlib import Path
from typing import Any, Dict, List, Optional

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plate_engine import (  # noqa: E402
    APP_DIR,
    PlateRecognizer,
    default_output_dir,
    list_images,
    sample_images_dir,
    save_results_csv,
    save_results_json,
    write_image,
)
from plate_link import PlateSerialLink, UART_BAUD, list_serial_ports  # noqa: E402

try:
    from PIL import Image, ImageTk
except ImportError:  # pragma: no cover
    Image = ImageTk = None


class PlateApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("车牌识别上位机")
        self.root.geometry("1180x720")

        self.files: List[Path] = []
        self.records: List[Dict[str, Any]] = []  # 每张图一条 {image, image_path, plates, elapsed_ms, annotated}
        self.recognizer: Optional[PlateRecognizer] = None
        self.worker: Optional[threading.Thread] = None
        self.msg_queue: "queue.Queue[tuple]" = queue.Queue()
        self.preview_photo = None
        self.current_index: Optional[int] = None
        self.serial_link: Optional[PlateSerialLink] = None
        self.serial_tx_queue: "queue.Queue[Optional[tuple]]" = queue.Queue()
        self.serial_tx_thread = threading.Thread(target=self._serial_tx_loop, daemon=True)
        self.serial_tx_thread.start()

        self.var_recursive = tk.BooleanVar(value=False)
        self.var_color = tk.BooleanVar(value=True)
        self.var_auto_send = tk.BooleanVar(value=True)
        self.var_port = tk.StringVar(value="")
        self.var_outdir = tk.StringVar(value=str(default_output_dir()))
        self.var_status = tk.StringVar(value="就绪：请导入图片或文件夹")
        self.var_serial_status = tk.StringVar(value="串口未连接")

        self._build_ui()
        self.refresh_serial_ports()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(100, self._poll_queue)

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        toolbar = ttk.Frame(self.root, padding=(8, 6))
        toolbar.pack(side=tk.TOP, fill=tk.X)

        ttk.Button(toolbar, text="导入图片", command=self.on_pick_files).pack(side=tk.LEFT)
        ttk.Button(toolbar, text="导入文件夹", command=self.on_pick_dir).pack(side=tk.LEFT, padx=(6, 0))
        ttk.Button(toolbar, text="载入样例", command=self.on_load_samples).pack(side=tk.LEFT, padx=(6, 0))
        ttk.Button(toolbar, text="开始识别", command=self.on_start).pack(side=tk.LEFT, padx=(12, 0))
        ttk.Button(toolbar, text="清空", command=self.on_clear).pack(side=tk.LEFT, padx=(6, 0))
        ttk.Checkbutton(toolbar, text="递归子目录", variable=self.var_recursive).pack(side=tk.LEFT, padx=(12, 0))
        ttk.Checkbutton(toolbar, text="识别颜色", variable=self.var_color).pack(side=tk.LEFT, padx=(6, 0))

        serial_bar = ttk.Frame(self.root, padding=(8, 2))
        serial_bar.pack(side=tk.TOP, fill=tk.X)
        ttk.Label(serial_bar, text="HDMI 结果回显").pack(side=tk.LEFT)
        self.port_box = ttk.Combobox(
            serial_bar, textvariable=self.var_port, width=16, state="readonly"
        )
        self.port_box.pack(side=tk.LEFT, padx=(6, 4))
        ttk.Button(serial_bar, text="刷新端口", command=self.refresh_serial_ports).pack(side=tk.LEFT)
        self.serial_button = ttk.Button(
            serial_bar, text="连接 FPGA", command=self.toggle_serial
        )
        self.serial_button.pack(side=tk.LEFT, padx=(6, 0))
        ttk.Button(
            serial_bar, text="发送图像+结果", command=self.send_current_result
        ).pack(side=tk.LEFT, padx=(6, 0))
        ttk.Checkbutton(
            serial_bar, text="识别后自动发送标注图和车牌号", variable=self.var_auto_send
        ).pack(side=tk.LEFT, padx=(12, 0))
        ttk.Label(serial_bar, textvariable=self.var_serial_status, anchor="e").pack(
            side=tk.RIGHT, padx=(8, 0)
        )

        export_bar = ttk.Frame(self.root, padding=(8, 0))
        export_bar.pack(side=tk.BOTTOM, fill=tk.X)
        ttk.Label(export_bar, text="输出目录:").pack(side=tk.LEFT)
        ttk.Entry(export_bar, textvariable=self.var_outdir, width=46).pack(side=tk.LEFT, padx=(4, 6))
        ttk.Button(export_bar, text="选择目录", command=self.on_pick_outdir).pack(side=tk.LEFT)
        ttk.Button(export_bar, text="导出 JSON", command=self.on_export_json).pack(side=tk.LEFT, padx=(10, 0))
        ttk.Button(export_bar, text="导出 CSV", command=self.on_export_csv).pack(side=tk.LEFT, padx=(6, 0))

        status = ttk.Label(self.root, textvariable=self.var_status, anchor="w", padding=(10, 4))
        status.pack(side=tk.BOTTOM, fill=tk.X)

        paned = ttk.Panedwindow(self.root, orient=tk.HORIZONTAL)
        paned.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=8, pady=4)

        # 左：图片列表 + 预览
        left = ttk.Frame(paned)
        paned.add(left, weight=2)
        list_frame = ttk.LabelFrame(left, text="图片列表", padding=4)
        list_frame.pack(side=tk.TOP, fill=tk.X)
        self.listbox = tk.Listbox(list_frame, height=6, exportselection=False)
        self.listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scroll = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.listbox.yview)
        scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.listbox.configure(yscrollcommand=scroll.set)
        self.listbox.bind("<<ListboxSelect>>", self.on_select_image)

        canvas_frame = ttk.LabelFrame(left, text="预览（标注结果）", padding=4)
        canvas_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True, pady=(6, 0))
        self.canvas = tk.Canvas(canvas_frame, background="#202020", highlightthickness=0)
        self.canvas.pack(fill=tk.BOTH, expand=True)
        self.canvas.bind("<Configure>", lambda _e: self._render_preview())

        # 右：结果表
        right = ttk.Frame(paned)
        paned.add(right, weight=3)
        cols = ("image", "plate", "type", "det_conf", "rec_conf", "color", "color_conf", "ms")
        headers = {
            "image": "文件",
            "plate": "车牌号",
            "type": "类型",
            "det_conf": "检测分",
            "rec_conf": "识别分",
            "color": "颜色",
            "color_conf": "颜色分",
            "ms": "耗时(ms)",
        }
        widths = {"image": 130, "plate": 110, "type": 60, "det_conf": 66, "rec_conf": 66, "color": 60, "color_conf": 66, "ms": 74}
        table_frame = ttk.LabelFrame(right, text="识别结果", padding=4)
        table_frame.pack(fill=tk.BOTH, expand=True)
        self.tree = ttk.Treeview(table_frame, columns=cols, show="headings")
        for col in cols:
            self.tree.heading(col, text=headers[col])
            self.tree.column(col, width=widths[col], anchor="center")
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        tree_scroll = ttk.Scrollbar(table_frame, orient=tk.VERTICAL, command=self.tree.yview)
        tree_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree.configure(yscrollcommand=tree_scroll.set)
        self.tree.bind("<<TreeviewSelect>>", self.on_select_row)
        self._row_index: Dict[str, int] = {}

    # ------------------------------------------------------- 文件选择
    def on_pick_files(self) -> None:
        paths = filedialog.askopenfilenames(
            title="选择车牌图片",
            filetypes=[("图片", "*.jpg *.jpeg *.png *.bmp *.webp *.tif *.tiff"), ("全部文件", "*.*")],
        )
        if not paths:
            return
        self._add_files([Path(p) for p in paths])

    def on_pick_dir(self) -> None:
        directory = filedialog.askdirectory(title="选择图片文件夹")
        if not directory:
            return
        self._add_files(list_images(directory, recursive=self.var_recursive.get()))
        if not self.files:
            messagebox.showinfo("提示", "该目录下未找到图片文件。")

    def on_load_samples(self) -> None:
        samples_dir = sample_images_dir()
        if samples_dir is None:
            messagebox.showinfo("提示", "未找到样例图片目录，请手动导入图片。")
            return
        self._add_files(list_images(samples_dir))
        if not self.files:
            messagebox.showinfo("提示", f"样例目录为空：{samples_dir}")

    def on_pick_outdir(self) -> None:
        directory = filedialog.askdirectory(title="选择输出目录")
        if directory:
            self.var_outdir.set(directory)

    def _add_files(self, paths: List[Path]) -> None:
        existing = {str(p) for p in self.files}
        added = 0
        for path in paths:
            key = str(path)
            if key in existing:
                continue
            self.files.append(path)
            self.listbox.insert(tk.END, path.name)
            existing.add(key)
            added += 1
        self.var_status.set(f"已导入 {len(self.files)} 张图片（本次新增 {added}）")

    def on_clear(self) -> None:
        if self.worker and self.worker.is_alive():
            messagebox.showwarning("提示", "识别进行中，请等待完成。")
            return
        if self.serial_tx_queue.unfinished_tasks:
            self.var_serial_status.set("图片正在发送，等待传输队列完成后再清空")
            return
        self.files.clear()
        self.records.clear()
        self._row_index.clear()
        self.listbox.delete(0, tk.END)
        self.tree.delete(*self.tree.get_children())
        self.canvas.delete("all")
        self.preview_photo = None
        self.current_index = None
        self.var_status.set("已清空")
        if self.serial_link and self.serial_link.is_open:
            try:
                self.serial_link.clear()
            except Exception as exc:  # noqa: BLE001
                self.var_serial_status.set(f"清除 FPGA 显示失败：{exc}")

    # ------------------------------------------------------- 识别流程
    def on_start(self) -> None:
        if self.worker and self.worker.is_alive():
            messagebox.showwarning("提示", "识别正在进行中。")
            return
        if not self.files:
            messagebox.showinfo("提示", "请先导入图片或文件夹。")
            return
        self.tree.delete(*self.tree.get_children())
        self._row_index.clear()
        self.records.clear()
        out_dir = Path(self.var_outdir.get().strip() or str(default_output_dir()))
        out_dir.mkdir(parents=True, exist_ok=True)
        self.var_status.set("正在加载模型并识别 ...")
        self.worker = threading.Thread(
            target=self._worker_run,
            args=(list(self.files), out_dir, self.var_color.get()),
            daemon=True,
        )
        self.worker.start()

    def _worker_run(self, files: List[Path], out_dir: Path, is_color: bool) -> None:
        try:
            recognizer = PlateRecognizer(is_color=is_color)
            self.msg_queue.put(("device", str(recognizer.device)))
            for index, path in enumerate(files, 1):
                try:
                    annotated, results, elapsed_ms = recognizer.recognize_file(path)
                    write_image(out_dir / path.name, annotated)
                    self.msg_queue.put(("result", index, len(files), path, results, elapsed_ms, annotated))
                except Exception as exc:  # noqa: BLE001
                    self.msg_queue.put(("error", index, len(files), path, str(exc)))
        except Exception:  # noqa: BLE001
            self.msg_queue.put(("fatal", traceback.format_exc()))
        finally:
            self.msg_queue.put(("done", str(out_dir)))

    def _poll_queue(self) -> None:
        try:
            while True:
                msg = self.msg_queue.get_nowait()
                self._handle_message(msg)
        except queue.Empty:
            pass
        self.root.after(100, self._poll_queue)

    def _handle_message(self, msg: tuple) -> None:
        kind = msg[0]
        if kind == "device":
            self.var_status.set(f"使用设备 {msg[1]}，识别中 ...")
        elif kind == "serial_done":
            _, image_name, plate_no = msg
            result = plate_no if plate_no else "未检出车牌"
            self.var_serial_status.set(
                f"串口发送完成，板端待确认：{image_name} / {result}"
            )
        elif kind == "serial_error":
            _, image_name, error = msg
            self.var_serial_status.set(f"{image_name} 发送失败：{error}")
        elif kind == "result":
            _, index, total, path, results, elapsed_ms, annotated = msg
            self.records.append(
                {
                    "image": path.name,
                    "image_path": str(path),
                    "plates": results,
                    "elapsed_ms": round(elapsed_ms, 1),
                    "annotated": annotated,
                }
            )
            record_index = len(self.records) - 1
            if results:
                for plate in results:
                    row_id = self.tree.insert(
                        "",
                        tk.END,
                        values=(
                            path.name,
                            plate["plate_no"],
                            "双层" if plate["plate_type"] == 1 else "单层",
                            f"{plate['detect_conf']:.3f}",
                            f"{plate['rec_conf']:.3f}",
                            plate["plate_color"] or "-",
                            f"{plate['color_conf']:.3f}" if plate["plate_color"] else "-",
                            f"{elapsed_ms:.0f}",
                        ),
                    )
                    self._row_index[row_id] = record_index
            else:
                row_id = self.tree.insert(
                    "", tk.END, values=(path.name, "（未检出）", "-", "-", "-", "-", "-", f"{elapsed_ms:.0f}")
                )
                self._row_index[row_id] = record_index
            self.var_status.set(f"进度 {index}/{total}：{path.name} 检出 {len(results)} 个车牌")
            self._select_file(record_index)
            if self.var_auto_send.get() and self.serial_link and self.serial_link.is_open:
                self._send_record(record_index)
        elif kind == "error":
            _, index, total, path, err = msg
            # 失败也要占一条记录，保证 records 与 files 的索引一一对应
            self.records.append(
                {
                    "image": path.name,
                    "image_path": str(path),
                    "plates": [],
                    "elapsed_ms": 0.0,
                    "annotated": None,
                }
            )
            record_index = len(self.records) - 1
            row_id = self.tree.insert(
                "", tk.END, values=(path.name, f"（读取失败：{err}）", "-", "-", "-", "-", "-", "-")
            )
            self._row_index[row_id] = record_index
            self.var_status.set(f"进度 {index}/{total}：{path.name} 失败 - {err}")
        elif kind == "fatal":
            messagebox.showerror("识别失败", msg[1])
            self.var_status.set("识别失败，请查看错误提示")
        elif kind == "done":
            total_plates = sum(len(record["plates"]) for record in self.records)
            self.var_status.set(
                f"完成：{len(self.records)} 张图片，共 {total_plates} 个车牌；标注图已写入 {msg[1]}"
            )

    # ------------------------------------------------------- 预览与联动
    def refresh_serial_ports(self) -> None:
        try:
            ports = list_serial_ports()
        except Exception as exc:  # noqa: BLE001
            self.var_serial_status.set(f"串口枚举失败：{exc}")
            return
        values = [f"{device} - {description}" for device, description in ports]
        current = self.var_port.get().split(" - ", 1)[0]
        self.port_box.configure(values=values)
        if values:
            match = next((item for item in values if item.startswith(current + " - ")), values[0])
            self.var_port.set(match)
            self.var_serial_status.set(f"发现 {len(values)} 个串口")
        else:
            self.var_port.set("")
            self.var_serial_status.set("未发现串口；请检查 CH340 驱动和 USB")

    def toggle_serial(self) -> None:
        if self.serial_link and self.serial_link.is_open:
            if self.serial_tx_queue.unfinished_tasks:
                self.var_serial_status.set("图片正在发送，请等待队列完成后再断开")
                return
            self.serial_link.close()
            self.serial_link = None
            self.serial_button.configure(text="连接 FPGA")
            self.var_serial_status.set("串口已断开")
            return
        selected = self.var_port.get().split(" - ", 1)[0].strip()
        if not selected:
            messagebox.showinfo("串口", "先刷新并选择 USB-UART 的 COM 端口。")
            return
        try:
            self.serial_link = PlateSerialLink(selected, UART_BAUD)
        except Exception as exc:  # noqa: BLE001
            self.serial_link = None
            self.var_serial_status.set(f"连接失败：{exc}")
            messagebox.showerror("串口连接失败", str(exc))
            return
        self.serial_button.configure(text="断开串口")
        self.var_serial_status.set(f"已连接 {selected} @ {UART_BAUD} 8N1")

    def _serial_tx_loop(self) -> None:
        while True:
            job = self.serial_tx_queue.get()
            if job is None:
                self.serial_tx_queue.task_done()
                return

            _record_index, link, record = job
            try:
                plates = record["plates"]
                best = max(
                    plates,
                    key=lambda item: (item["detect_conf"] + item["rec_conf"]) / 2,
                ) if plates else None
                plate_no = best["plate_no"] if best else ""
                annotated = record.get("annotated")
                if annotated is None:
                    raise ValueError("没有可发送的标注图")

                link.send_image(annotated, plate_no, _record_index)
                if plate_no:
                    link.send_plate(plate_no)
                else:
                    link.clear()
                self.msg_queue.put(("serial_done", record["image"], plate_no))
            except Exception as exc:  # noqa: BLE001
                self.msg_queue.put(("serial_error", record["image"], str(exc)))
            finally:
                self.serial_tx_queue.task_done()

    def _send_record(self, record_index: int) -> None:
        if not self.serial_link or not self.serial_link.is_open:
            self.var_serial_status.set("串口未连接，识别结果未发送")
            return
        if not 0 <= record_index < len(self.records):
            return
        record = self.records[record_index]
        if record.get("annotated") is None:
            self.var_serial_status.set(f"{record['image']} 没有可发送的图像")
            return
        best = max(
            record["plates"],
            key=lambda item: (item["detect_conf"] + item["rec_conf"]) / 2,
        ) if record["plates"] else None
        plate_no = best["plate_no"] if best else "未检出车牌"
        self.serial_tx_queue.put((record_index, self.serial_link, record))
        pending = self.serial_tx_queue.unfinished_tasks
        self.var_serial_status.set(
            f"已排队发送 {record['image']} 标注图 + {plate_no}（队列 {pending}）"
        )

    def send_current_result(self) -> None:
        selected = self.tree.selection()
        if selected:
            record_index = self._row_index.get(selected[0])
        else:
            record_index = self.current_index
        if record_index is None or not 0 <= record_index < len(self.records):
            messagebox.showinfo("发送结果", "请先选中已完成识别的图片或结果行。")
            return
        self._send_record(record_index)

    def on_close(self) -> None:
        if self.serial_tx_queue.unfinished_tasks and not messagebox.askyesno(
            "退出确认", "图像仍在发送。现在退出会中断串口传输，确定退出吗？"
        ):
            return
        self.serial_tx_queue.put(None)
        if self.serial_link:
            self.serial_link.close()
            self.serial_link = None
        self.root.destroy()

    def _select_file(self, record_index: int) -> None:
        if record_index < 0 or record_index >= len(self.files):
            return
        self.current_index = record_index
        self.listbox.selection_clear(0, tk.END)
        self.listbox.selection_set(record_index)
        self.listbox.see(record_index)
        self._render_preview()

    def on_select_image(self, _event=None) -> None:
        selection = self.listbox.curselection()
        if selection:
            self.current_index = int(selection[0])
            self._render_preview()

    def on_select_row(self, _event=None) -> None:
        selected = self.tree.selection()
        if not selected:
            return
        record_index = self._row_index.get(selected[0])
        if record_index is not None and record_index != self.current_index:
            self.current_index = record_index
            self.listbox.selection_clear(0, tk.END)
            self.listbox.selection_set(record_index)
            self.listbox.see(record_index)
            self._render_preview()

    def _render_preview(self) -> None:
        if self.current_index is None or self.current_index >= len(self.files):
            return
        if Image is None or ImageTk is None:
            return
        import cv2

        annotated = None
        for record in self.records:
            if record["image_path"] == str(self.files[self.current_index]):
                annotated = record["annotated"]
                break
        if annotated is None:
            from plate_engine import read_image

            annotated = read_image(self.files[self.current_index])
            if annotated is None:
                return

        canvas_w = max(self.canvas.winfo_width(), 100)
        canvas_h = max(self.canvas.winfo_height(), 100)
        rgb = cv2.cvtColor(annotated, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(rgb)
        image.thumbnail((canvas_w - 8, canvas_h - 8))
        self.preview_photo = ImageTk.PhotoImage(image)
        self.canvas.delete("all")
        self.canvas.create_image(canvas_w // 2, canvas_h // 2, image=self.preview_photo, anchor="center")

    # ------------------------------------------------------- 导出
    def _collect_rows(self) -> List[Dict[str, Any]]:
        rows: List[Dict[str, Any]] = []
        for record in self.records:
            for plate in record["plates"]:
                row = dict(plate)
                row["image"] = record["image"]
                row["elapsed_ms"] = record["elapsed_ms"]
                rows.append(row)
        return rows

    def on_export_json(self) -> None:
        if not self.records:
            messagebox.showinfo("提示", "暂无可导出的识别结果。")
            return
        path = filedialog.asksaveasfilename(
            title="导出 JSON", defaultextension=".json", initialfile="plate_results.json",
            filetypes=[("JSON", "*.json")],
        )
        if not path:
            return
        payload = [
            {"image": r["image"], "image_path": r["image_path"], "elapsed_ms": r["elapsed_ms"], "plates": r["plates"]}
            for r in self.records
        ]
        save_results_json(payload, path, extra={"image_count": len(self.records), "plate_count": len(self._collect_rows())})
        self.var_status.set(f"已导出 JSON：{path}")

    def on_export_csv(self) -> None:
        rows = self._collect_rows()
        if not rows:
            messagebox.showinfo("提示", "暂无可导出的识别结果。")
            return
        path = filedialog.asksaveasfilename(
            title="导出 CSV", defaultextension=".csv", initialfile="plate_results.csv",
            filetypes=[("CSV", "*.csv")],
        )
        if not path:
            return
        save_results_csv(rows, path)
        self.var_status.set(f"已导出 CSV：{path}")


def run_selftest() -> int:
    """无界面自检：加载模型 → 识别样例图 → 把过程写入 selftest.log（返回码 0/1）。

    用于验证打包后的 exe 是否可用（打包产物无控制台，只能靠日志与返回码判断）。
    """
    log_path = APP_DIR / "selftest.log"
    lines = [
        f"frozen={getattr(sys, 'frozen', False)}",
        f"python={sys.version.split()[0]}",
        f"APP_DIR={APP_DIR}",
        f"RES_DIR={getattr(sys, '_MEIPASS', APP_DIR)}",
        f"sample_dir={sample_images_dir()}",
        f"default_output_dir={default_output_dir()}",
    ]
    ok = False
    try:
        recognizer = PlateRecognizer()
        lines.append(f"device={recognizer.device}")
        lines.append(f"detect_model={recognizer.detect_model_path}")
        lines.append(f"rec_model={recognizer.rec_model_path}")
        samples = list_images(sample_images_dir() or APP_DIR)[:3]
        if not samples:
            lines.append("未找到样例图片，仅完成模型加载校验")
            ok = True
        for path in samples:
            image, results, elapsed_ms = recognizer.recognize_file(path)
            plates = [r["plate_no"] for r in results]
            lines.append(f"{path.name} -> {plates} ({elapsed_ms:.0f} ms)")
            write_image(default_output_dir() / path.name, image)
            ok = ok or bool(plates)
        if not ok:
            lines.append("识别结果为空，判定为失败")
    except Exception:
        lines.append(traceback.format_exc())
    log_path.write_text("\n".join(lines), encoding="utf-8")
    return 0 if ok else 1


def main(argv: Optional[List[str]] = None) -> int:
    argv = list(sys.argv[1:]) if argv is None else list(argv)
    if "--selftest" in argv:
        return run_selftest()
    root = tk.Tk()
    PlateApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
