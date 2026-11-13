# 《Verilog/SystemVerilog 编程艺术》审阅修订初稿 v1.1

本书面向工业级 RTL 设计，以“系统解释优秀 RTL 为什么如此设计”为主线。全书六篇33章，附录A—H，附Timer、同步FIFO、受限AXI4-Lite CSR从设备三个案例。

## 阅读入口

| 文件 | 用途 |
|---|---|
| `RTL_Art_Reader.html` | 离线阅读版，含章节导航、全文浏览器查找与打印样式 |
| `RTL_Art_Manuscript.md` | 完整可编辑书稿 |
| `front_matter.md`、`part1.md`至各分篇文件 | 可编辑前言与分篇源 |
| `review_response_v1.1.md` | 外部审阅逐项处理记录 |
| `appendix_h.md` | 从配套源码自动纳入的完整RTL附录 |
| `bridge_case.md` | 最终综合案例正文 |
| `delivery_status.md` | 本次检查范围与尚未完成的出版审校项目 |
| `examples/` | 可运行RTL、自检TB、运行脚本与实际日志 |

## 复现案例

进入 `examples/`，按其README运行。基础工程需要Icarus Verilog；协议检查器单独需要支持相应SVA的工具，不放入默认Icarus构建。代码中的测试PASS文字只是执行成功时的输出，是否实际执行以日志与验证记录为准。

## 重建阅读版

安装Python包 `Markdown==3.11.3` 后，可运行：

```sh
python3 assemble_book.py
python3 build_reader.py
python3 validate_book.py
```

也可通过原书稿直接重建排版，不影响RTL仿真。阅读版无需联网；引用的外部规范链接需网络访问。v0.1文件保留为历史参考；当前构建使用front_matter及part1等分篇源。

## 版本和责任边界

v1.1落实首轮外部审阅，补齐书内完整RTL、兼容性与RAM推断、可复现通用综合微实验、活动率估算、离线公式与稳定目录。它仍是完整初稿，尚不是经过独立技术审稿、标准逐条校对和目标工艺实现验证的出版定稿。没有附带商业综合、STA、功耗、形式化或流片签核结论。

## 原始下载与历史版本

本仓库根目录展开 v1.1，便于阅读、检索与修改。ChatGPT 对话中下载的 7 个文件均保留在 [`downloads/`](downloads/)，包括 v0.1 初稿、v1.0/v1.1 的 Markdown 与 HTML，以及两个原始 ZIP。原始文件未修改；校验值见 [`downloads/SHA256SUMS`](downloads/SHA256SUMS)。

## 开源许可

本仓库原创书稿、配套代码与构建脚本采用 [MIT License](LICENSE)。引用的规范、商标及第三方资料仍归各自权利人所有，其许可不因本仓库的许可而改变。原始 ZIP 为历史交付文件，仓库根目录 LICENSE 说明本次开源授权。

本次发布核对了原始文件完整性与 v1.1 展开内容；未重新执行书稿中的仿真、综合或物理实现。随包日志记录原写作阶段的执行结果，具体边界见 `delivery_status.md`。
