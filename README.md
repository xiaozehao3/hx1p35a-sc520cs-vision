# HX1P35B / PH1P35 FPGA 摄像头视频处理与 PC 图片 HDMI 显示

工程可用 SC520CS MIPI 摄像头实时采集，也支持从 PC 导入车牌图片：上位机识别并叠加车牌框后，经 115200 baud UART 发送静态图片到 FPGA，FPGA 校验并放大后经 HDMI 显示。车牌检测和 OCR 在 PC 执行，FPGA 负责图像接收、缓存、显示及 OSD。

本仓库是面向 GitHub 的干净归档：包含 FPGA 源码、约束、最终工程/bit、仿真用例、PC 上位机源码和模型、竞赛提交材料。Python 虚拟环境、上位机大型打包构建目录和本地识别输出未纳入仓库；PC 上位机可按 `pc_plate_tool/README.md` 从源码启动或重建。

项目过程复盘、已完成范围、遗留问题和后续建议见 [PROJECT_RETROSPECTIVE.md](PROJECT_RETROSPECTIVE.md)。第三方许可提醒见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 竞赛提交材料

- [A1 竖版作品海报 PDF（含 GitHub 仓库二维码）](docs/submission/05_%E4%BD%9C%E5%93%81%E6%B5%B7%E6%8A%A5_A1%E7%AB%96%E7%89%88_GitHub%E4%BA%8C%E7%BB%B4%E7%A0%81.pdf)
- [A1 竖版作品海报 PPTX 源文件](docs/submission/04_%E4%BD%9C%E5%93%81%E6%B5%B7%E6%8A%A5_A1%E7%AB%96%E7%89%88_GitHub%E4%BA%8C%E7%BB%B4%E7%A0%81.pptx)

仓库为私有库。海报二维码打开仓库首页，浏览项目文件需要使用已获授权的 GitHub 账号登录。

## 视频处理模式

在“视频处理”页面使用 K1/K2 切换，算法在帧边界更新：

| 屏幕名称 | 处理 |
|---|---|
| Model1：彩色 | 彩色画面 |
| Model2：二值化 | 亮度阈值二值化 |
| Model3：边缘检测 | Sobel 边缘检测 |
| Model4：灰度 | 灰度变换 |

## 主菜单功能

| 菜单项 | 当前 RTL 实现 |
|---|---|
| 区域填充与风格化 | 开关控制的颜色量化风格化和固定 ROI 亮度阈值填充 |
| 目标跟踪与坐标 | 红色高饱和颜色目标框选、帧间平滑与坐标显示；不是通用目标识别 |
| 运动目标检测 | 低分辨率帧差检测，显示运动区域框 |
| 图像质量调节 | 基于逐帧采样的数字亮度/通道偏置校正；不是传感器自动曝光或直方图均衡 |
| 帧率与延迟 | 显示 FPS、采集/显示帧计数和帧级计数差 |
| 自主伪彩 | 将亮度映射为四段伪彩色 |
| PC 图片显示 | 接收上位机发送的 160×90 RGB565 标注图，CRC16 校验通过后放大到 1280×720 HDMI 显示；状态栏显示接收字节数、成功帧和车牌文本 |

PC 图片显示是静态图片导入，不是实时视频串流；车牌检测和号码识别由 PC 上位机完成。串口 TX 外部控制当前未启用。

## 按键与开关

按键低电平有效，管脚来自 `user_source/constraints_source/pin.adc`：

| 控件 | 管脚 | 菜单操作 | 页面操作 |
|---|---|---|---|
| K1 | D5 | 上一项 | 视频处理页切换到上一种模式 |
| K2 | A9 | 下一项 | 视频处理页切换到下一种模式 |
| K3 | B9 | 进入 | — |
| K4 | C7 | — | 返回主菜单；在 PC 图片页退出图片显示 |

SW1-SW4 的管脚分别为 A4、B4、E11、D11。它们经顶层反相后送入处理逻辑：SW1 控制风格化，SW2 控制 ROI 填充，SW3 选择伪彩风格映射，SW4 切换填充颜色。SW5/SW6 不用于本视频 UI。

## 下载与工程文件

本次提交工程文件为 `td_project_submission_pc_image_20261025/hx1p35a_sc520cs_vision_ui.al`，构建脚本为 `td_project_submission_pc_image_20261025/build_submission.tcl`，生成文件为 `td_project_submission_pc_image_20261025/hx1p35a_sc520cs_submission_pc_image_20261025.bit`。旧 bit 不含 PC 图片接收、菜单入口和视频源切换逻辑。

约束文件分工：

- `user_source/constraints_source/pin.adc`：开发板顶层 IO 管脚。
- `user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc`：DDR2 IP 管脚。
- `user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc`：DDR2 IP 时序。
- `I_uart_rx` 使用 FPGA V1，对应扩展口 J1-2；图传接线和操作步骤见 `PC_IMAGE_TRANSFER.md`。

FPGA 综合、布线和图像包仿真已通过；本地没有连接开发板，HDMI 显示与 CH340 电气连接仍需在目标板上验收。若板子此前接 CH340 后仍有异响、发热或无法启动，先不要再次连接或上电测试。

本次归档保留的时序报告仍含 SCL 与摄像头时钟网的混合扇出警告，bit 虽然已生成，时钟结构仍需进一步复核。板卡先完成硬件状态检查，再做实物验收。
