# PC 车牌识别上位机

图片导入 → 车牌检测 → 车牌字符/颜色识别 → 置信度与结果图保存的完整工具，含命令行与图形界面。

- 检测：YOLOv5 车牌检测模型 `weights/plate_detect.pt`（0.45 M 参数）
- 识别：CRNN 车牌字符 + 颜色识别模型 `weights/plate_rec_color.pth`（0.18 M 参数），支持 12 类中国车牌（蓝/黄/绿/白警/教练/武警/双层/使馆/港澳/民航/危险品等）
- 工程中虽有另一套 LPRNet RTL（`user_source/hdl_source/lprnet/top_lprnet.sv`），但本上位机使用 YOLO/CRNN 在 PC 上识别；识别出的车牌文本可通过 CH340 发给 FPGA 做 HDMI OSD 回显。图片像素和模型推理仍留在 PC，不参与 FPGA 板级推理。

## 目录结构

```
pc_plate_tool/
├── plate_engine.py     # 核心引擎：模型加载、推理、中文标注、JSON/CSV 导出
├── plate_cli.py        # 命令行入口
├── plate_gui.py        # Tkinter 图形界面入口（含 --selftest 无界面自检）
├── run_cli.bat         # Windows 命令行快捷启动（自动使用 .venv）
├── run_gui.bat         # Windows 图形界面快捷启动
├── requirements.txt
├── .venv/              # 独立虚拟环境（--system-site-packages，复用系统 torch/cv2/PIL）
├── vendor/Chinese_license_plate_detection_recognition-main/   # 第三方模型与权重（GPL-3.0）
├── packaging/          # 打包配置（图标生成、PyInstaller spec、一键发布脚本）
└── outputs/            # 默认输出目录（标注图 + result.json + result.csv）
```

## 环境

虚拟环境已创建完毕，无需重复安装。若需在其它机器重建：

```bash
python -m venv --system-site-packages .venv
# 本机 pip 的 HTTPS 通道被中间层阻断，必须使用 HTTP 镜像
.venv/Scripts/python.exe -m pip install -i http://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com scipy psutil thop
```

## 命令行用法

```bash
# 单张图片（标注图与结果写入 outputs/）
.venv/Scripts/python.exe plate_cli.py --input car.jpg

# 整个目录，递归子目录，并导出 JSON + CSV
.venv/Scripts/python.exe plate_cli.py --input imgs/ --recursive --json outputs/result.json --csv outputs/result.csv

# 不识别颜色 + 过滤识别置信度低于 0.6 的结果
.venv/Scripts/python.exe plate_cli.py --input imgs/ --no-color --min-conf 0.6
```

Windows 下也可直接用 `run_cli.bat`（等价于上面命令，自动带上 `.venv`）：

```bat
run_cli.bat --input imgs --recursive --json outputs/result.json --csv outputs/result.csv
```

主要参数：`--input`（文件或目录，必填）、`--output`（输出目录，默认 `outputs`）、`--img-size`（默认 640）、`--no-color`、`--min-conf`、`--recursive`、`--json`、`--csv`、`--device`（cpu/cuda）、`--detect-model`、`--rec-model`。

## 图形界面用法

双击 `run_gui.bat`，或：

```bash
.venv/Scripts/python.exe plate_gui.py
```

1. 「导入图片」或「导入文件夹」（可勾选“递归子目录”）
2. 可切换“识别颜色”，设置输出目录
3. 点「开始识别」，右侧表格实时显示车牌号、单双层、检测分、识别分、颜色、耗时；左侧显示标注后的结果图
4. 如需同步显示到 FPGA HDMI，先连接 CH340 串口，再识别图片；勾选「识别后自动发送标注图和车牌号」时，程序会先发送标注图，再发送车牌文字。也可识别完成后选中结果，点「发送图像+结果」
5. 点「导出 JSON」/「导出 CSV」保存结果（标注图已在识别时自动写入输出目录）

其中「载入样例」会载入随包样例图片，用于快速确认程序本身是否正常。

### FPGA HDMI 车牌回显

1. 车牌回显使用带 UART 接收的 bit 文件；下载路径见工程根目录 README 的“最新 bit 文件”。注意，车牌文本回显与图片 UART 是两种协议。
2. 用 3.3 V UART 电平 CH340 连接：`TXD -> 开发板 J1 pin 2 / FPGA V1`，`GND -> J1 pin 12 或 pin 30`。不要接 CH340 `VCC`，不要接 5 V TTL。
3. 运行 `run_gui.bat`（使用源码版本），选择 CH340 的 COM 口并点「连接 FPGA」。
4. 导入图片并开始识别。默认会在识别完成后自动将标注图和最高置信度车牌号依次发送到 FPGA；也可手动点「发送图像+结果」。未识别到车牌时会发送标注图和清除文字命令。

串口参数为 `115200, 8N1`。图片使用 `55 AA 5A A5 ... CRC16` 帧，文字使用 `A5 5A CMD LEN DATA CRC8` 帧；GUI 在同一个串口上先后发送两帧，不会并发交错。单独运行图片发送脚本时，必须先退出 GUI；同一 COM 口不能同时被 GUI、SSCOM 和其他脚本占用。使用串口前关闭 SSCOM；板上 CH340 电平和接线请先断电确认，若适配器或排线发热，立即断电并检查 VCC/TXD 接线。

### FPGA HDMI 静态图片显示与接收诊断

当前 FPGA 图片链路用于“导入一张图片并在 HDMI 上循环显示”，不是实时图传。通常直接使用上面的 GUI 流程即可；需要单独验证传输时，先退出 GUI 和 SSCOM，再下载工程根目录 README 中的最新图片 UART bit，并运行：

```bat
.venv\Scripts\python.exe pc_image_sender.py --port COM7 --input D:\test\target.jpg
```

图片会缩放为 `160x90 RGB565`，总帧长固定 `28,818` 字节，通过 CH340 以 `115200, 8N1` 发送；FPGA 收到 CRC16 正确的一帧后，将其放大为 `1280x720`。进入主菜单第 7 项 `PC IMAGE` 后，完整接收的图片才会切到 HDMI 循环显示；离开该页会在帧边界切回摄像头。该页可查看 `RX/IMG/OK/ER`：独立发送一张图片后 `RX` 至少应为十六进制 `7092`；`RX=0000` 表示 FPGA 没采到串口字节，`RX` 增长但 `OK=0000` 表示帧头、波特率或 CRC 未通过，`IMG:OK` 且 HDMI 仍显示摄像头则继续检查视频切源/显示链路。传输约需 2.5 秒；不要让 SSCOM 和发送脚本同时占用同一个 COM 口。GUI 发送图片后还会发送一条车牌文本帧，因此 `RX` 会略高于 `7092`。

新版源码 GUI 的发送状态会显示“串口发送完成，板端待确认”；这不是 FPGA 回执，板端是否验收以 `PC IMAGE` 页的 `RX/IMG/OK/ER` 为准。

新版 GUI 源码启动方式：

```bat
cd pc_plate_tool
run_gui.bat
```

本次生成的 bit 文件位于工程提交目录：

```
`td_project_submission_pc_image_20261025/hx1p35a_sc520cs_submission_pc_image_20261025.bit`
```

这条图片协议与上面的车牌文本协议不同：图片使用 `pc_image_sender.py` 的 RGB565/CRC16 帧，车牌文本使用 GUI 的 115200/CRC8 帧。新版 GUI 会通过同一 COM 口先后发送图片和文本，不会并发交错。PC 显示串口发送完成不等于 FPGA 已收到，需以 HDMI `PC IMAGE` 页中的 `RX/IMG/OK/ER` 状态为准。

## 无界面自检

打包产物没有控制台，用自检模式验证模型与依赖是否完整（返回码 0 为通过，过程写入
`selftest.log`）：

```bash
.venv/Scripts/python.exe plate_gui.py --selftest     # 源码模式
PlateRecognizer.exe --selftest                        # 打包模式（日志写在 exe 旁）
```

## 打包为绿色免安装包（分发给队友）

```bash
.venv/Scripts/python.exe packaging/make_release.py              # 完整构建
.venv/Scripts/python.exe packaging/make_release.py --skip-build  # 只重新组装与压缩
```

流程：生成图标 → PyInstaller 打包 → 组装发布目录 → 压成 zip。产物：

```
packaging/release/车牌识别上位机/                  绿色版目录（可直接运行）
packaging/release/车牌识别上位机_v1.0.0_win64.zip   分发给队友的压缩包
```

发布目录内容：`PlateRecognizer.exe`（图形界面）、`_internal/`（运行库，勿删）、
`样例图片/`、`outputs/`、`使用说明.txt`、`第三方许可与源码/`。队友解压后双击
`PlateRecognizer.exe` 即可，无需安装 Python、无需联网。

注意事项：
- 打包必须在 `pc_plate_tool` 目录下的 `.venv` 里进行（PyInstaller 与 torch 都在里面）。
- 体积主要由 PyTorch 决定（torch 本体约 1.1 GB，其中 `torch/lib` 的 DLL 约 1 GB）。
- 打包配置见 `packaging/PlateRecognizer.spec`，模型权重与字体通过 `datas` 随包携带，
  运行时由 `plate_engine._resolve_dirs()` 从 `sys._MEIPASS` 解析。
- 第三方项目为 **GPL-3.0**，因此发布包内附带其许可证与完整 Python 源码（`第三方许可与源码/`）；
  若要把本工具对外分发或商用，需遵守 GPL-3.0 并注意模型作者的授权说明。

## 结果字段

| 字段 | 含义 |
| --- | --- |
| `plate_plain` | 车牌号（含中文省份简称与“学/警/港/澳/使/领/民航/危险品”等后缀） |
| `detect_conf` | 检测框置信度 |
| `rec_conf` | 逐字符置信度均值（整体识别把握） |
| `min_char_conf` | 最低单字符置信度（用于判断可疑字符） |
| `char_confs` | 逐字符置信度数组 |
| `plate_color` / `color_conf` | 车牌颜色及颜色分类置信度 |
| `plate_type` | 0 单层 / 1 双层 |
| `rect` / `landmarks` | 车牌框与 4 个角点在原图上的坐标 |
| `elapsed_ms` | 单张图检测+识别耗时（毫秒） |

## 实测（本机 CPU，img_size=640）

以仓库自带 15 张样例图为回归集，全部识别正确，覆盖单/双层、蓝/黄/绿、白警、武警、教练、使馆、港澳、危险品等类型，单张耗时约 130–280 ms：

```
double_yellow.jpg   京EA5331(黄色, 双层)
hongkang1.jpg       粤ZR066港(黑色)
moto.png            沪AN9241(黄色, 双层)
police.jpg          鄂F8888警(白色)
shi_lin_guan.jpg    沪A1707领(黑色)
single_blue.jpg     浙B2V9L7 / 辽DU4356(蓝色)
single_green.jpg    沪AF71017(绿色)
single_yellow.jpg   皖K66666(黄色)
tmp8F1F.png         危险品(黄色)
tmpA5E3.png         WJ1693015(白色)
xue.jpg             琼A6716学(黄色)
```

## 已知限制

- 仅 CPU 推理（`torch 2.4.1+cpu`），无 CUDA；单张 130–280 ms，视频实时性需 GPU 或改用 ONNX/TensorRT 版本。
- 识别网络为 CRNN 结构，与工程内 LPRNet RTL 不是同一网络，两者误差不可直接互相标定。
- 双层车牌按上下分割拼接后识别；极端角度/强反光时角点回归可能不准，进而影响透视校正后的识别结果。
- 首次加载模型约 1–2 s；`torch.load` 会打印 `weights_only` 的 FutureWarning，属正常提示。
