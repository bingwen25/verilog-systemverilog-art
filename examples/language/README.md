# 第5章位选择符号性微测试

用 `./run.sh` 编译并运行，需要Icarus Verilog；支持`IVERILOG`、`VVP`、`IVERILOG_BACKEND`覆盖。RTL按SystemVerilog模式编译。

检查一维 `logic signed [7:0] s` 作为完整变量、完整part-select、显式`$signed(part-select)`三种九位扩展的差别。

本次Icarus 12.0实际结果见`logs/run.log`：

```text
s=ff: whole=-1 slice=255 recast=-1
s=80: whole=-128 slice=128 recast=-128
PASS part-select signedness
```

这是针对标准规则的最小反例，不替代全部表达式的位宽与上下文推导检查。
