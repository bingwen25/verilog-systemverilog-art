# 第 23 章：流水线加法微实验

这个微实验比较 `a+b+c+d mod 2^32` 的单级输出寄存器实现与两级流水实现。二者每拍最多接受一个 `in_valid` 元组、无背压，II=1；复位为同步低有效，`out_valid` 随数据经过流水级。按采样输入的上升沿计，基线延迟 1 拍，两级流水延迟 2 拍。

## 复现

在本目录执行 `./run.sh`。可用 `IVERILOG`、`VVP`、`IVERILOG_BACKEND` 和 `YOSYS` 覆盖工具位置。脚本优先找系统工具，其次找 `../build/iverilog-root/usr/bin`，再用本目录工具解包路径。若没有 Yosys，可通过系统包安装，或执行 `python3 -m pip install yowasp-yosys`。Icarus 被解包使用时，`IVERILOG_BACKEND` 应指向其中 `ivl` 后端目录。

本次环境中原先约定的 `examples/build/iverilog-root/usr/bin` 不存在，因此从 Debian `iverilog 12.0-2+b1` 包下载并解包到 `tools/iverilog/root`；Icarus 后端路径为 `tools/iverilog/root/usr/lib/x86_64-linux-gnu/ivl/`。Yosys 使用 Python 包 `yowasp-yosys 0.71.0.0.post1285`，运行时 `yowasp-runtime 1.96`。版本、命令和完整输出见 `logs/`。

仿真 TB 分别核对基线一拍和流水两拍的有效信号/数据期望，并将流水输出与前一拍的基线输出作延迟对齐比较；没有把两个设计误判为逐周期等价。固定种子随机流、定向溢出及连续满速输入共检查 238 个有效事务。实际输出：

```text
PASS add4 transactions=238 baseline_latency=1 pipeline_latency=2 extra_latency=1
```

## Generic synthesis 统计

两边都用同版本 Yosys 的 `synth -noabc` 默认 generic 流程，再执行 `stat`。`-noabc` 保留 Yosys 的 generic gate primitives，不进行目标工艺映射。寄存器数按 `$_SDFF*`、`$_SDFFE*` 统计；组合 cell 数为总 cell 数减去这些寄存器。

| 实现 | 寄存器 cells | 组合 cells | 总 generic cells | 延迟 | II |
|---|---:|---:|---:|---:|---:|
| 单级基线 | 33 | 526 | 559 | 1 拍 | 1 |
| 两级流水 | 98 | 660 | 758 | 2 拍 | 1 |

这些数据只说明本次 generic synthesis 的 cell 计数。环境没有目标标准单元库、工艺角、约束文件、布局布线或 STA；因此它**不是真实 PPA 数据**，也不能据此声称频率提升、时序收敛或功耗/面积优势。流水线通过增加寄存器和一级延迟切分组合运算；实际最高频率需在同一目标库、同一约束下完成映射、物理实现及 STA 后测量。
