# RTL 书配套示例

本目录包含可运行的计时器、同步 FIFO，以及一个受限 AXI4-Lite CSR 示例。

## 模块

- `timer.sv`：W 位倒计时器，低有效同步复位。仅在空闲且 `start=1`、`cancel=0`、`period!=0` 时接受请求。接受后经过 N 个后续上升沿拉高单周期 `done`；`cancel` 优先于终值完成，忙时的 `start` 忽略。W=8 的测试覆盖最大周期 255、完成沿 `start` 和 `start` 持续为高的情况。
- `sync_fifo.sv`：任意正深度的 ready/valid FIFO，支持深度 1 和非 2 的幂。满态不接收新写，即使同沿发生读操作也不例外；空态不直通；读数据是当前读地址的组合数组输出。
- `bridge/axi4lite_csr.sv`：有限容量 AXI4-Lite CSR 从机示例。可用 `./bridge/run.sh` 单独运行。
- `protocol_checkers.sv`：验证专用的 ready/valid SVA 检查器，不属于默认 Icarus 文件集。

## 运行计时器和 FIFO 自检

安装 Icarus Verilog 后，在本目录运行：

```sh
./run.sh
```

脚本默认使用 `PATH` 中的 `iverilog` 和 `vvp`，也可通过 `IVERILOG`、`VVP` 环境变量指定可执行文件。若从 deb 解包运行，脚本会尝试从绝对 `IVERILOG` 路径推导 Icarus 后端目录；也可显式设置 `IVERILOG_BACKEND`。

FIFO testbench 在深度 1、3、4 下运行 scoreboard，覆盖填满、满态拒写、满态同时读写、排空和伪随机流量。源端在 valid 被背压时保持 `valid` 和 `data`，包括定向阶段切换和最后排空阶段。

## 当前验证记录

本交付环境最初无法系统安装 Icarus：`apt-get update` 默认目录不可写，`apt-get install` 因无 root 权限失败。随后使用用户目录中的 apt 列表成功下载 `iverilog 12.0-2+b1`，解包到临时目录后完成了真实编译和仿真；未进行系统级安装。

主案例实际仿真输出：

```text
PASS timer directed cases
PASS fifo depth=1 sent=628 received=628
PASS fifo depth=3 sent=948 received=948
PASS fifo depth=4 sent=979 received=979
PASS all examples
```

Pyslang 12.1 对 `timer.sv`、`sync_fifo.sv`、`tb.sv` 的静态语法和语义检查为 0 errors、0 diagnostics。AXI4-Lite CSR 案例也已单独通过 Icarus 仿真及 Pyslang 检查；Icarus 对其 `always_comb` 常量选择给出工具限制提示，但编译和自检均成功。

SVA 检查器单独通过 Pyslang 静态语法和语义检查（0 errors、0 diagnostics），但**未运行这些性质**；默认 `run.sh` 不包含 `protocol_checkers.sv`，也不执行 formal/property 仿真。

完整命令和输出保存在 `logs/`：

- `run.log`：计时器和 FIFO 的 Icarus 编译、仿真输出。
- `pyslang.log`：计时器和 FIFO 的静态检查结果。
- `bridge-iverilog.log`、`bridge-pyslang.log`：桥接案例的独立验证输出。
- `sva-syntax.log`：SVA checker 的静态编译结果；不代表性质已执行。
- `apt-update.log`、`apt-install.log`：默认安装尝试的失败输出；`apt-unprivileged.log`：用户目录下载 deb 成功的输出。
- `SHA256SUMS`：与上述验证日志对应的 HDL 源文件校验值。

## v1.1 新增微实验

`language/` 检查完整part-select的unsigned语义，Icarus自检通过；`ppa/`包含单级与两级求和RTL、238事务延迟对齐自检和Yosys 0.71通用综合报告。通用cell计数不是目标库面积或物理PPA结果，详见各目录README和日志。
