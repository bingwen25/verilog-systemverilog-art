# 第三篇：工业 RTL 的控制与数据通路

本篇代码片段默认采用 SystemVerilog，单时钟域、上升沿触发、同步低有效复位 `rst_n`；未另行说明时，复位在时钟沿采样。片段是可综合设计的局部示例，端口和参数需由集成环境补齐。`valid/ready` 表示在同一采样沿完成传输；`valid` 持续到握手成功，除非接口契约另有说明。计数器采用无符号定宽逻辑，比较与加减均须按声明位宽审查。下文引用厂商文档只用于确认其文档明确覆盖的器件或工具行为，不把某家 FPGA 的推断习惯当成所有综合器的语言规则。

## 第12章 有限状态机：让控制流程可读、可证明

有限状态机（FSM）把“当前处于什么阶段”显式编码，再依据输入决定下一阶段及输出。它的价值不是把所有控制逻辑硬塞进 `case`，而是让状态空间、转移条件、非法状态行为都能被枚举和审查。工业设计中，状态名常常承载协议含义：`IDLE` 表示可以接收命令，`WAIT_RSP` 表示请求已发而响应未到，`RESP` 表示响应保持到被接收。若把状态写成含糊的 `S1/S2`，代码虽可综合，评审和波形调试却失去语义锚点。

以下是一个两阶段请求应答控制器。请求只在 `IDLE` 且 `req_valid && req_ready` 时接受；响应阶段 `rsp_valid` 保持，直到 `rsp_ready` 同周期为 1。当前示例中 `req_ready = (state_q == IDLE)`，因此在 `IDLE` 内用 `req_valid` 转移与显式检查 `req_valid && req_ready` 等价；显式写出握手条件有助于和副作用共用一个接受事件。若以后 `req_ready` 还受 FIFO 空间、资源占用等条件限制，只检查 `req_valid` 就会在 ready 为 0 时错误离开 `IDLE`。这里用 Moore 风格输出，使 `rsp_valid` 只由寄存状态决定，隔离输入组合毛刺；状态寄存器和译码仍有物理延迟，因此 Moore 输出本身不保证无毛刺。同步复位在时钟沿将状态置为 `IDLE`。

```systemverilog
typedef enum logic [1:0] {IDLE, WAIT_RSP, RESP} state_t;
state_t state_q, state_d;

always_comb begin
  state_d = state_q;
  unique case (state_q)
    IDLE:    if (req_valid && req_ready) state_d = WAIT_RSP;
    WAIT_RSP: if (core_done) state_d = RESP;
    RESP:    if (rsp_ready) state_d = IDLE;
    default: state_d = IDLE;
  endcase
end

always_ff @(posedge clk) begin
  if (!rst_n) state_q <= IDLE;
  else        state_q <= state_d;
end

assign req_ready = (state_q == IDLE);
assign rsp_valid = (state_q == RESP);
```

请求接受条件统一记为 `req_fire = req_valid && req_ready`，状态转移及所有接受请求的副作用都由它驱动。这样当前例子显式对应协议握手，也能避免将来 ready 加入资源条件后漏改状态转移。

状态编码选择可先按路径和资源目标决策，再用综合报告确认工具结果：

|编码|优先考虑的场景|主要代价与检查点|
|---|---|---|
|二进制|状态较少、触发器面积敏感，译码路径有余量|触发器少，状态译码可能较深；检查译码是否进入关键路径|
|one-hot|时序优先、状态数适中，状态译码处于关键路径|状态位和时钟/复位负载较多；检查面积、复位扇出和目标器件资源|
|工具自动|希望让综合器按目标器件和约束选择|结果可能随工具版本或约束变化；检查报告中的识别结果和实际编码|

AMD Vivado 文档说明其综合流程可选择 FSM 编码方式，并提供 `FSM_ENCODING` 属性控制；这是特定工具能力，属性应和目标综合器版本一起管理。工具若未识别 FSM，常见原因包括状态寄存器被算术改写、多处驱动、状态信号对外可观察、复位/默认逻辑不完整。应看综合报告确认实际识别和编码，而非从源代码猜测。

同步复位与异步复位的取舍要从系统复位架构出发。同步复位容易保持时序路径一致，但复位必须覆盖有效时钟沿；异步复位可在时钟停止时立即置位，却要求释放时满足恢复/移除时间，跨域释放需要同步处理。不能在 FSM 中混用无意的异步事件和同步数据路径。`always_ff` 用于表达唯一时序过程，`always_comb` 用于完整组合赋值；组合块先给所有输出默认值，避免遗漏分支推断锁存器。`unique case` 是设计意图和仿真检查提示，不等于自动修复非法状态；若工具对 `unique` 有不同解释，应依据语言标准和工具手册确认。

非法状态处理也是安全设计决策。`default: state_d = IDLE` 只能使下一个时钟沿回到空闲，不能保证非法状态下组合输出安全，所以输出解码也要有安全默认值。若错误状态可能造成外部副作用（例如重复发起写入），应直接规定“非合法状态时禁止 `valid`、写使能和提交脉冲”，再由故障检测或复位策略处理。若为形式验证加入状态合法性断言，应明确复位解除后的适用窗口，避免把复位期间的未知值误判成设计缺陷。

周期推演：复位沿后 `state_q=IDLE`；周期 A 中 `req_valid=1`、`req_ready=1`，该沿接受请求并进入 `WAIT_RSP`；周期 B 等待核心完成；若 `core_done` 在 B 采样为 1，沿后进入 `RESP`；周期 C 即使 `rsp_ready=0`，`rsp_valid` 继续为 1；当某一沿 `rsp_ready=1`，传输完成并沿后回 `IDLE`。响应数据必须在整个 `rsp_valid && !rsp_ready` 区间保持稳定，否则消费者看到的数据会随背压漂移。

设计检查清单：逐项列出状态、进入条件、离开条件和状态输出；确认每个请求/响应只在握手时发生一次；组合块有默认赋值并无锁存器；复位后状态与副作用输出都安全；非法状态的恢复路径明确；状态是否暴露给模块边界；综合报告是否识别预期 FSM；状态覆盖与转移覆盖包含等待、背压、同时事件和非法状态。安全关键路径还应审查状态翻转导致的瞬态输出，以及是否需要寄存输出。

练习：上例在 `RESP` 期间若 `core_done` 再次脉冲，是否会额外生成响应？答案：不会，因为当前状态只检查 `rsp_ready`，完成脉冲没有状态转移效果；但若核心可能每周期改变响应数据，必须在 `core_done` 时锁存响应数据，并在 RESP 背压期间保持。练习二：将 `req_ready` 改成 `state_q==IDLE` 后，如果上游在 ready 拉高时下周期撤销 valid，是否算已提交？答案：不算。提交发生在实际采样沿上的 valid 与 ready 同时为 1，不能由“ready 曾经拉高”推断。

## 第13章 计数器、定时器与事件：把时间契约写进位宽

本章定时器实现称为**案例 A（Timer）**。

计数器看似只是 `count <= count + 1`，真正的工程问题却是：从哪个沿开始计时、边界值是否包含、溢出时发生什么、事件输出是一拍还是电平、配置何时生效。把这些语义写清楚，能够避免典型的一拍偏差。本文定时器契约固定如下：同步低有效复位；空闲态遇到 `start` 时接受并锁存输入 `N`，要求 `N>=1`；接受沿之后的 N 个时钟沿完成；取消优先于完成；忙时 `start` 忽略；`done` 是单周期脉冲。输入 `N` 在接受时采样，之后变化不影响当前定时。

下面的实现采用“剩余沿数”计数：接受 start 的沿只锁存 N，尚不计为 N 个后续沿；此后每个忙态采样沿消耗一个周期。若剩余数为 1，在该沿产生 `done` 并回到空闲。因此 N=1 时，启动沿后紧接的下一个有效沿完成。取消在该沿优先，哪怕倒计数恰为 1，也不产生 done。

```systemverilog
parameter int unsigned W = 16; // 要求 W>=1
logic busy_q;
logic [W-1:0] left_q;
logic done_q;

always_ff @(posedge clk) begin
  if (!rst_n) begin
    busy_q <= 1'b0;
    left_q <= '0;
    done_q <= 1'b0;
  end else begin
    done_q <= 1'b0;
    if (!busy_q) begin
      if (start && !cancel && (n_in != '0)) begin
        left_q <= n_in;
        busy_q <= 1'b1;
      end
    end else if (cancel) begin
      busy_q <= 1'b0;
      left_q <= '0;
    end else if (left_q == 1) begin
      busy_q <= 1'b0;
      left_q <= '0;
      done_q <= 1'b1;
    end else begin
      left_q <= left_q - 1'b1;
    end
  end
end
assign done = done_q;
assign busy = busy_q;
```

片段假定 `n_in` 宽度正好为 W，且 `W>=1`。`left_q` 是无符号向量，和无尺寸十进制整数常量 `1` 比较时，SystemVerilog 按表达式尺寸规则扩展到比较宽度，并按无符号值比较。上面为突出意图，`N=0` 被忽略，接口契约要求调用者给非零值。若要将 0 定义为“立即完成”或“禁用定时”，必须改写行为并验证边界。

周期表如下，其中 `N=3`，`A` 为接受 start 的时钟沿；`cancel` 取值为 0：

|采样沿|沿前状态|动作|沿后状态|done|
|---|---|---|---|---|
|A|空闲，start=1|锁存 3|忙，left=3|0|
|A+1|忙，left=3|消耗第 1 个后续沿|忙，left=2|0|
|A+2|忙，left=2|消耗第 2 个后续沿|忙，left=1|0|
|A+3|忙，left=1|消耗第 3 个后续沿|空闲|1|

错误推演：若在 `start` 同一时钟沿进入忙态，并在 `busy` 分支的同一时序块里立即对旧 `left_q` 减一，非阻塞赋值右值读到的是沿前的旧计数；第一次运行可能从 X 或先前任务残值开始。即便额外用分支绕过 X，若启动沿也当作第一个计时沿，N=3 会在 A+2 完成，违反契约。另一种常见错误是 `if (left_q==0) done<=1; else left_q<=left_q-1;`：从 N 开始会先减到 0，之后才完成，实际产生 N+1 个后续沿。定时器须先定义计数表示，再从 N=1 手工走波形。

取消优先意味着 `cancel` 与终点同时为 1 时，不发 done。若产品需求是“已到期不可取消”，优先级反过来，并且系统上游必须知道这一点。忙时忽略 start 也意味着不能简单地把 `start` 当成重新装载；如果需要可重触发，另设 `restart` 或明确 `start` 对当前事务的作用。配置输入锁存使启动后软件改写周期值不扰动运行中的定时。

定时器和事件脉冲有不同职责。`done_q` 是寄存器，默认每拍清零，仅完成分支置一，所以单周期；若将 `done` 写成 `busy && left_q==1` 的组合信号，它会在完成沿之前整个周期有效，语义可能仍可用，但相邻逻辑采样时序和取消优先更易出错。跨时钟域不能直接采样单周期脉冲，脉冲可能比目的域时钟短或落在采样边沿之间；应使用脉冲展宽、toggle 同步、请求应答握手或异步 FIFO，选择取决于吞吐率和能否背压。

计数器位宽要由最大值推导。表示 0 到 M 的计数至少需要 `$clog2(M+1)` 位，但 `$clog2(1)=0` 会生成零宽向量，需封装 `localparam CW = (M < 2) ? 1 : $clog2(M+1);`。若只数 1 到 M，还要确认终值、减法回绕和加载值。事件累计器如果每拍可能同时发生多个事件，单比特增量不足；若一个周期可发生最多 K 个事件，应加 K 或使用分组计数，定义饱和还是回绕，并算出最长未清读窗口内的最大总量。

实现权衡：倒计数比较终值 1，易对应“还剩几个沿”的契约；上计数器比较 N，则要保存目标值和当前值，比较器可能在关键路径；预分频器可减低主计数器翻转，但会引入分频相位与重配置语义。共享计数器能节省面积，却让多个事件的独立暂停、取消、装载相互耦合。对于必须精确到输入周期的定时，应直接使用同一时钟域计数，不把逻辑分频器误当成新时钟树。

检查清单：文档写明 N=1、N=0、最大 N；start/cancel 同拍优先级；busy 状态 start 的处理；计数器的接受沿是否计入；done 是否只打一拍；复位时是否清 done 和 busy；参数宽度是否出现零宽；减一是否可能回绕；动态输入是否已锁存；跨域事件是否经过可靠传递。练习：N=4 且在 A+2 沿 cancel=1，done 在哪一拍？答案：A+2 沿取消生效，busy 清零且 done 保持 0；后续不再产生完成。练习二：如需忙时 start 忽略但记录一次待办，增加一个 pending 位，并在当前完成/取消后的空闲周期决定是否用已锁存参数启动，不能偷偷改变原本 start 接受契约。

## 第14章 握手协议：让每次传输都有唯一的采样点

ready/valid 是同步数据接口的一种常用协议。源端以 `valid=1` 表示当前有一个可传输项目，并在未握手期间保持 `valid` 和负载稳定；宿端以 `ready=1` 表示当前周期愿意接收。只有采样沿上 `valid && ready` 同时为真才发生一次传输。此规则看似简单，却决定了计数、FIFO 写使能、地址递增、标签分配都必须统一由同一个 `fire` 条件驱动。把 valid 的上升沿、ready 的上升沿或状态改变当作传输事件，会在背压下重放、丢弃或错配数据。

```systemverilog
logic fire;
assign fire = valid && ready;

always_ff @(posedge clk) begin
  if (!rst_n) begin
    accepted_q <= '0;
    payload_q  <= '0;
  end else if (fire) begin
    accepted_q <= accepted_q + 1'b1;
    payload_q  <= data;
  end
end
```

握手发生在采样沿。若周期 P 的组合值为 `valid=1, ready=0`，没有事务；源端必须保持数据，宿端可在 P+1 拉高 ready，随后沿上才采样一次。若源端在 P+1 握手前就撤销 valid，即使它“看到之前 ready 低”，也违反承诺。若宿端在一次握手之后立刻保持 ready 高，源端可以在相邻周期送另一个项目，实现每周期一笔；valid 不必回到 0 作为分隔符。`valid` 表示一个持续存在的项目，不是脉冲事件。

反压设计要看组合路径。纯组合地把下游 `ready` 穿透多个模块，会形成长组合链；反过来若每级只在本地寄存 ready，却没有容量吸收迟到的一拍，可能发生溢出。一个简单单槽寄存器采用“当前空，或当前数据会被取走”作为 ready：`in_ready = !full_q || out_ready`。同拍旧数据握手并接收新数据时，存储寄存器更新成新数据，满位维持 1，从而无气泡接续。

```systemverilog
assign in_ready = !full_q || out_ready;
assign out_valid = full_q;
always_ff @(posedge clk) begin
  if (!rst_n) begin
    full_q <= 1'b0;
  end else begin
    unique case ({in_valid && in_ready, out_valid && out_ready})
      2'b10: begin full_q <= 1'b1; data_q <= in_data; end
      2'b01: full_q <= 1'b0; end
      2'b11: begin full_q <= 1'b1; data_q <= in_data; end
      default: ;
    endcase
  end
end
assign out_data = data_q;
```

这里 `out_data` 在 `out_valid=0` 时无意义。若下游把无效数据也视为安全敏感信息，应将数据复位或屏蔽，但这会增加复位扇出和面积；协议本身不要求无效负载为零。上述 `in_ready` 直接组合依赖 `out_ready`，在单级可接受，在多个模块直串时可能形成组合环路或时序路径过长。可用 skid buffer、两项弹性缓冲或寄存切断 ready 链，但需保证“下游 ready 已下降而上游本周期仍送来的一项”有落点。

错误推演：模块以 `if (valid) count++` 计收包数量，消费端 ready 连续拉低三拍。源端按照协议保持 valid 与 data，这三拍中模块把同一包计三次。正确条件是 `valid && ready`。另一种错误是 `valid` 只打一拍，碰上 `ready=0` 就消失：该事务无论后续 ready 如何都丢失。第三种错误是数据在 `valid && !ready` 时更新，消费者最终握手到的是不同于源端初次声明的数据；这是一种协议级竞态，而不是单纯的仿真波形问题。

多通道协议要定义独立握手还是原子组合。若地址、数据、字节使能在不同通道，则每个通道分别有 valid/ready，不能假设地址握手必然意味着数据握手；协议可能允许两者先后到达。若一个命令的多个字段必须原子接受，应在内部缓冲独立通道并在所有字段齐备时组装，或者采用单一打包通道。AXI 等标准总线有自己的时序、响应和 outstanding 规则，不能从简化 ready/valid 示例直接推断全部总线行为，应查对应官方规范。

`valid` 和 `ready` 的产生逻辑还要避免组合环。两个模块若各自 `valid = !peer_ready`、`ready = !peer_valid`，可能出现环路或无法初始化。工程规范通常要求源端的 valid 不依赖对端 ready，方便组合审查；具体协议也可能允许局部组合依赖，但系统需验证不存在零延迟循环。吞吐率由每周期握手数决定，延迟则由寄存级数决定；增加缓冲通常提升容忍背压能力，可能增加最坏延迟，但并不必然降低稳态吞吐。

检查清单：只有 `fire` 驱动副作用；停顿期间 valid 和负载稳定；复位时 valid 清零；同拍出入是否支持；ready 反压是否能传播或被缓冲；是否有组合环和过长 ready 链；多个逻辑副作用是否使用完全相同的握手条件；协议空闲周期的 data 是否允许任意。练习：valid 连续为 1 四拍，ready 为 1、0、0、1，则传输了几笔？答案：两笔，分别在第 1 与第 4 个采样沿。练习二：当缓冲满且本拍下游 ready=1、上游 valid=1，是否能同拍出旧值、入新值？答案：可以；旧数据被消费，新数据写入缓冲，沿后仍满且输出变成新值。

## 第15章 流水线与弹性缓冲：在吞吐、延迟和背压之间取舍

流水线把长组合运算切成若干级，用寄存器分隔逻辑深度。流水线能够提高可达到的时钟频率，并在填满后每拍接收/产生一笔，但“流水线每拍输出一个结果”只在没有停顿且每级可以推进时成立。加入反压后，必须阻止上游覆盖未消费数据，或提供额外存储接住已经在路上的项目。弹性流水级以 valid 标记寄存数据是否有意义，以 ready 表示本级有空间接收新数据。数据、valid 和 sideband 标签（例如 ID、错误标志、最后一拍）必须作为一个整体推进。

单级弹性寄存器的核心条件是 `in_ready = !valid_q || out_ready`。当本级为空时可以接收；本级满但下游同拍取走，也能用新数据替换。代码见第14章单槽示例。把它扩展到多级，若每级的 ready 组合反传，延迟可低而组合链增长；若 ready 寄存化，则每级多一拍反压传播延迟，通常需 skid buffer 保存额外一笔。设计目标不是抽象地追求“零泡”，而是给出可实现的频率、容量、延迟和最大反压延迟契约。

两级管线的一个推演：P0 时两级皆空，上游在沿 0 握手输入 A，沿后第一级存 A；沿 1 第一级把 A 推进到第二级，同时上游握手输入 B，沿后第二级为 A、第一级为 B；沿 2 下游握手 A，同时 B 推进到第二级、上游握手输入 C，沿后第二级为 B、第一级为 C。无背压时，首结果在沿 2 可见，随后每拍都能完成一笔输出并接受一笔输入，展示了两级管线的满吞吐。若沿 2 下游 ready=0，第二级必须保留 A；第一级也不能把 B 覆盖掉，因此反压回到上游，或者局部额外容量保存 B。一个看似“只要停住最后一级”的改法，会让第一级仍在推进并覆盖多个在途事务，数据丢失。

拆分组合逻辑时，还要明确每一级的运算延迟和标签对齐。若乘法结果流水化两拍，而异常标志只打一拍，异常标志就会和错误的数据配对。用结构体打包字段可以减少漏接风险：

```systemverilog
typedef struct packed {
  logic [31:0] result;
  logic        overflow;
  logic [3:0]  tag;
} pipe_item_t;
pipe_item_t stage_q;
logic stage_valid_q;
```

每个被接受的 item 应满足顺序不变、恰好输出一次，除非模块明确允许丢弃或取消。若设计包括 flush（分支错误、复位或事务取消），必须说明 flush 清掉哪些级、同拍新输入是否接受、已对外承诺的响应如何处理。仅清 valid 通常足以使内部数据无效，但若输出 valid 已对消费者握手，就不能再撤销该笔事务。flush 若跨越多级组合网络，应检查所有有效位同步清除以及清除优先级。

弹性缓冲和传统固定延迟流水线各有适用场景。固定延迟流水线的控制简单、时序行为可预测，适合每拍必有数据或整体停机的运算核；ready/valid 弹性流水线适合上下游速率不一致、突发输入或系统级反压，但控制逻辑和形式性质更多。弹性级可以插入到已有路径切断时序，不必修改事务语义；但如果外部协议要求固定时延，插入缓冲改变可观察行为，需要评估。宽数据总线上的多个小 buffer 会消耗寄存器面积，RAM FIFO 更节省面积却可能有同步读延迟和不同满空语义。

错误推演：有一条 3 级管线，每级仅在自身 `valid` 时更新数据，且第二级停顿时第一级继续工作。第一级连续送 A、B、C，第二级被阻塞；第一级寄存器从 A 覆盖为 B、再覆盖为 C，而第二级仍保持旧项。没有任何错误仿真语法，但 A、B 已丢失。正确策略是让每一级使用同一套局部握手 `stage_fire = valid_q && downstream_ready`，并按可用空间生成 `ready`；或用中心控制冻结整条管线，但要冻结所有数据、valid、标签寄存器，并定义输入端行为。

信用（credit）流控是另一种选择：接收端预先告知可容纳的项目数，发送端在信用为零时停发。它减少逐周期 ready 链路依赖，适合长距离或高频片上互连，但信用的初值、回补时机、回路延迟和复位一致性需精确设计。若延迟窗口内可有多个在途项目，credit 深度须覆盖该窗口与接收缓冲，不能用单拍 ready 的直觉替代。无论采用何种流控，必须保证“发送方认为可发送”的数量永不超过“接收方实际剩余容量”。

检查清单：接口握手定义明确；valid 停顿时数据与 sideband 稳定；每一级有明确空间判定；同拍出入逻辑无覆盖；ready 链组合深度可接受或有 skid buffer；复位/flush 处理所有有效位；已握手事务不可撤销；顺序、恰好一次和标签对齐可验证；吞吐、首结果延迟和反压延迟分别记录。练习：两级管线的第二级满且 out_ready=0，一级满且新输入 valid=1，应如何响应？答案：若没有可用额外项，一级 `in_ready=0`，上游保持该输入；一级和二级数据均保持。若设计额外一项 skid 存储，则可接受一项，但必须证明深度确实含有这笔空间。练习二：一个 item 的数据与 tag 同拍推进但 overflow 标志只在原输入路径组合计算，为什么可能错位？答案：计算延迟和寄存级数不一致，标志可能描述相邻事务；应作为 item 同步通过同样的有效级。

## 第16章 FIFO 与存储接口：指针、计数、容量和碰撞语义

本章 FIFO 实现称为**案例 B（FIFO）**。

FIFO 把先入先出顺序抽象成写端和读端。同步单时钟 FIFO 的核心状态是存储阵列、读指针、写指针、占用计数；空条件为 count=0，满条件为 count=DEPTH。指针自然二进制回绕仅适用于 DEPTH 为 2 的幂。若参数允许非 2 幂，必须显式在 `DEPTH-1` 回到 0；否则三位指针用于深度 6 时会访问地址 6、7，越界，计数与实际存储也会脱节。DEPTH=1 是独立边界：地址宽应至少 1 位，读写指针没有可观察的多地址序列，满空判定仍由占用计数负责。

本章 FIFO 契约固定为单时钟、同步写、组合首字可见读：`dout=mem[rd_ptr]`，只在 `!empty` 时有效；空态没有输入到输出的直通旁路，因此空态同拍读写只写入、不读出。读请求只在非空时接受。写请求只在非满时接受；满态即使同拍读出也不接受该拍写入。若端口用 ready/valid 表达，满态 `in_ready=0`，源端未完成握手，必须保持 valid 和数据并重试，不能把这称为已接收或要求源端丢弃。该规则使满态读写同拍仅消费旧队首；若需无气泡“满态出入同时接受”，需把写接受条件定义为 `wr_en && (!full || rd_fire)` 并仔细处理同地址读写的数据碰撞与指针更新。

```systemverilog
localparam int AW = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
logic [WIDTH-1:0] mem [0:DEPTH-1];
logic [AW-1:0] wr_ptr_q, rd_ptr_q;
localparam int CW = (DEPTH < 2) ? 1 : $clog2(DEPTH+1); // DEPTH>=1
logic [CW-1:0] count_q;
logic wr_fire, rd_fire;
assign full  = (count_q == DEPTH);
assign empty = (count_q == 0);
assign wr_fire = wr_en && !full;
assign rd_fire = rd_en && !empty;
assign dout = mem[rd_ptr_q];

function automatic logic [AW-1:0] bump(input logic [AW-1:0] p);
  if (p == AW'(DEPTH-1)) bump = '0;
  else                  bump = p + 1'b1;
endfunction

always_ff @(posedge clk) begin
  if (!rst_n) begin
    wr_ptr_q <= '0; rd_ptr_q <= '0; count_q <= '0;
  end else begin
    if (wr_fire) begin mem[wr_ptr_q] <= din; wr_ptr_q <= bump(wr_ptr_q); end
    if (rd_fire) rd_ptr_q <= bump(rd_ptr_q);
    unique case ({wr_fire, rd_fire})
      2'b10: count_q <= count_q + 1'b1;
      2'b01: count_q <= count_q - 1'b1;
      default: ;
    endcase
  end
end
```

计数器位宽先由受保护的 `CW` 推导，再声明向量，避免 DEPTH=1 时出现零宽。另需在模块参数检查中拒绝 `DEPTH<1`，否则数组声明和比较没有有效含义。`AW'(DEPTH-1)` 是尺寸转换写法，目标工具对 SystemVerilog 的支持应确认；也可使用显式参数化常量函数。代码未复位存储阵列，因为 count=0 时数据无效，清整块 RAM 通常不需要且可能阻止 RAM 推断；复位指针和计数已使 FIFO 逻辑为空。

状态转移表（本章的保守满态规则）：

|沿前计数|wr_en|rd_en|wr_fire|rd_fire|沿后计数|
|---:|---:|---:|---:|---:|---:|
|0（空）|1|1|1|0|1|
|中间值|1|1|1|1|不变|
|DEPTH（满）|1|1|0|1|DEPTH-1|
|0（空）|0|1|0|0|0|

**现象：** DEPTH=6、AW=3，指针若只靠 3 位自然回绕，写入六项后指针变成 6，后续访问 `mem[6]` 越界；仿真可能显示 X，综合结果不可依赖。

**根因：** 二进制自然回绕只匹配 2 的幂深度；此外，若读写分别在两个独立分支给 `count_q` 赋值，同拍读写会由最后一条非阻塞赋值覆盖前一条，计数无法抵消。

**修复：** 指针在 `DEPTH-1` 显式回到 0；把 `{wr_fire, rd_fire}` 合并为一个 `case` 更新计数，或使用扩展位宽的净变化计算。

**检查点：** 覆盖 DEPTH=1、2、非 2 的幂、最大配置，并检查同拍读写后计数保持不变、指针始终小于 DEPTH。

### RAM 推断：模板、复位与报告核验

RAM 是否被推断取决于 HDL 结构、目标器件的存储资源和工具版本。以下模板说明常见表达方式，不承诺跨厂商、跨器件都映射为同一种宏。

**同步读、单写端口：**

```systemverilog
logic [WIDTH-1:0] mem [0:DEPTH-1];
logic [WIDTH-1:0] rdata_q;

always_ff @(posedge clk) begin
  if (wr_en)
    mem[wr_addr] <= wr_data;
  if (rd_en)
    rdata_q <= mem[rd_addr];
end
assign rd_data = rdata_q;
```

读地址和读使能在时钟沿采样，输出由寄存器保持；接口需接受该读延迟。AMD UG901 将异步读与同步读映射到不同存储资源特征，具体映射仍由器件和综合条件决定。

**组合读、单写端口：**

```systemverilog
always_ff @(posedge clk)
  if (wr_en) mem[wr_addr] <= wr_data;

assign rd_data = mem[rd_addr];
```

组合读便于构造低延迟小阵列，但可能映射为分布式 RAM 或逻辑单元，不能据此假定会使用块 RAM。

**寄存器堆多读端口：**多个并行的组合读端口可写成 `assign rdata0 = regs[raddr0];`、`assign rdata1 = regs[raddr1];` 等形式。寄存器堆通常由触发器和读选择网络实现；若工具或器件支持多端口 RAM，也可能采用特定结构。读端口数量、写端口数量、旁路和端口冲突规则都会影响面积与时序，应以综合结果为准。

**复位影响：**通常只复位读输出寄存器、有效位、指针或状态控制；逐字清零整块存储阵列可能不符合目标 RAM 的复位能力，导致阵列改用触发器实现。若系统必须复位内容，可用初始化/清扫过程或独立有效位表示空值，并检查其是否仍能满足接口语义和目标宏支持。

**Read-during-write：**同周期同地址读写可能表现为旧值、新值或保持输出，且同端口与跨端口行为可能不同。先在接口契约里规定碰撞结果，再用明确旁路实现所需语义，或禁止该碰撞；不能把某次 RTL 仿真观察当作器件保证。

**报告核验：**综合后检查每个数组是否被识别为 RAM、类型/端口模式/深宽是否符合预期、同步输出寄存器和读延迟是否保留、同地址读写模式是否匹配契约，并核对 RAM、LUT/逻辑单元和触发器用量。Vivado 可查看综合日志与 `report_ram_utilization`；Quartus 可查看 Analysis & Synthesis 的 RAM Summary 及 Fitter 资源报告。若数组意外变为触发器，回看复位、异步读、端口数量、写使能结构和数组访问方式。AMD 与 Intel 文档给出的模板和限制只适用于各自目标器件及版本，跨器件设计仍要在所选器件上复核。

本 FIFO 示例采用组合首字可见读，因而其存储实现和可达时序需结合深度、宽度及目标器件评估；同地址读写若在改版中变为可同时接受，须按上面的 Read-during-write 规则明确返回值并核验目标宏映射。

同步 FIFO 和异步 FIFO 不可混用指针逻辑。异步 FIFO 两边时钟不同，通常用 Gray 编码指针跨域同步，以降低多位二进制指针跨域同时变化带来的不一致采样风险；满空判断和复位释放都需要 CDC 专门处理。不能把二进制指针直接过两级同步器后就称为异步 FIFO。若不熟悉 Gray 指针满判断、指针同步延迟、复位域和物理约束，优先使用经过验证的厂商 FIFO 宏或经过验证的开源实现，并遵循其复位后等待 busy 信号等接口要求。深度不是 2 的幂时异步 FIFO 的 Gray 指针构造更复杂，不要随意套用只适用于 2 的幂深度的公式。

实现取舍：计数器法直观且任意深度都可用，但 count 到 full/empty 的组合比较可能进入状态路径；额外一位环绕位的读写指针可以区分空满，适合 2 的幂深度和特定存储架构；每槽 valid 位可实现小容量高弹性队列，但占用面积较大。FIFO 的接口也要决定是否允许满态读写替换、空态旁路、读请求是否弹出、是否提供 occupancy 和 almost-full。几种设计的 `full` 时序、读延迟不同，不应仅凭端口同名就互换。

检查清单：DEPTH>=1；DEPTH=1、2、非 2 幂与最大深度参数均合法；读写指针显式回绕；满态同拍读写规则写明；空态同拍读写规则写明；计数同拍更新正确；存储读延迟和碰撞模式符合目标 RAM；无效数据不被消费；复位只清必要控制状态；异步 FIFO 使用 CDC 方案和目标文档。练习：DEPTH=3 时指针序列应是什么？答案：0→1→2→0→1…，不能用 2 位自然溢出的 0→1→2→3→0。练习二：按本文规则，满态 `wr_en=rd_en=1` 后新写数据是否入队？答案：不入队，旧队首被读走，计数减一；若希望同时替换，必须更改 `wr_fire` 契约并验证 RAM 同地址读写。

## 第17章 仲裁：公平性、优先级和资源占用时间

仲裁器决定多个请求者中谁得到共享资源。设计前要先说清资源究竟在哪个事件上被占用：若资源每周期只完成一次操作，授予可以是一拍；若授予后要等返回完成，仲裁结果必须锁存直到事务终止；若请求本身是 ready/valid 流，则被选中的请求者只在 grant 与 valid 的握手沿完成传输。只在组合逻辑里产生 winner，却让请求者在背压期间改变请求，会导致一笔事务中途换主人。公平性也要定义指标：严格优先允许低优先级永远饥饿；轮询在持续竞争时限制最大等待，但请求保持、资源占用和取消规则都影响上界。

固定优先级适用于紧急级别有明确不同的控制，如错误恢复高于后台维护。可组合生成最高优先请求：

```systemverilog
always_comb begin
  grant = '0;
  if      (req[3]) grant[3] = 1'b1;
  else if (req[2]) grant[2] = 1'b1;
  else if (req[1]) grant[1] = 1'b1;
  else if (req[0]) grant[0] = 1'b1;
end
```

此示例默认 `req[3]` 优先且 grant 仅表示当前组合候选，不代表事务已经被接收。若 grant 一旦给出就构成对请求者的承诺，`ready=0` 时必须锁存 owner，不能因更高优先级的新请求到来而换人；否则需把接口明确定义为可变候选，只有 `grant && ready` 才提交，且请求负载须随当前候选稳定。组合优先链随着端口数增长会形成较深路径，可以用树形编码、分级仲裁或寄存仲裁结果改善时序，但加寄存会改变可见延迟。

轮询仲裁器维护一个起始优先级指针 `rr_q`。每次成功授予后，指针移到获胜者之后；如果只是请求存在而没有资源握手，不能推进。更关键的是，仅保持 `rr_q` 并不能保证 `grant` 稳定：等待期间若出现新的高优先候选，组合选择仍可能换 winner。若 grant 一旦展示就必须持续到接收，必须显式锁存 `owner_q`/`grant_q`，直到握手或协议允许的撤销事件，再解除锁定；锁定期间不得因新请求改变 owner。以 4 路为例，未锁定时指针为 0 扫描 0、1、2、3；指针为 2 时扫描 2、3、0、1。实际逻辑可以展开成循环扫描函数或优先编码网络，需避免综合工具无法展开的动态循环。完成事务时刻而非授予时刻更新指针，取决于资源定义：对于每拍独立数据传输，在 `grant && ready` 后更新；对于一笔跨多拍的非抢占事务，在完成/释放事件后更新。

锁定逻辑的结构可写成：空闲时从 `req` 和 `rr_q` 选出候选者；当候选有效时置 `owner_valid_q` 并锁存 `owner_q`；`grant` 在锁定期间只由 owner 产生；握手或明确定义的撤销才清 `owner_valid_q`，成功握手后推进 `rr_q`。如果接口规定 grant 只是随时可变的候选而非承诺，则可以不锁定，但请求方必须等到独立的握手事件才提交，且所有相关负载必须跟随同一个 winner。

周期推演：四个请求持续为 1，成功传输的序列应为 0、1、2、3、0…（若初始指针 0）；每个请求在持续竞争条件下最多等待 3 次其他授予。若第二个 requester 被 grant 但资源 ready=0，仲裁指针保持原值、grant 锁定为该请求者，直到握手或明确撤销。若 ready=0 时仍每拍推进指针，波形可能显示轮流 grant，所有申请者却都无法完成；若某 requester 的请求在等待时因协议允许撤销，应在锁定策略中定义撤销后如何释放，否则可永久占住 grant。

错误推演：设计将 `rr_q` 在 `grant_valid` 时递增，其中 `grant_valid` 只是 req 非零。下游连续 backpressure 五拍，指针每拍移动，请求者 0 的数据没有被接收，下一拍 grant 给 1，之后给 2、3；当下游恢复，仲裁器可能交付请求 1 的数据，错误地把一个尚未完成的授权换成另一个。正确事件应是 `grant_fire = grant_valid && downstream_ready`，或者显式锁定 `owner_q` 直到事务完成。

优先级仲裁和轮询仲裁可以结合：先按流量类别选高优先类，再在类内轮询；但若高优先类永远有请求，低优先类依旧会饿死。老化（等待越久优先级越高）能提供更强服务保障，却要维护等待年龄并决定饱和行为。带宽分配仲裁器（如加权轮询）按权重发放一批 grant，需决定权重单位是事务数、字节数还是占用周期；变长事务若只按事务计数，耗时长的 requester 可能占用更多实际带宽。工程规格最好以可测量服务指标描述，例如持续竞争下每个请求在 K 次仲裁成功内获得至少一次服务，而不只写“公平”。

仲裁策略还要配合死锁分析。若请求者拿着资源 A 等待资源 B，而另一路拿着 B 等 A，单个仲裁器公平并不能打破资源环路。若仲裁授予跨域传播，应检查 CDC；通常把仲裁放在资源的时钟域，跨域请求/响应通过握手或异步 FIFO传递。多个请求同拍撤销、复位、错误取消如何处理，都要定义 owner 状态的释放条件。复位直接清 owner 可能让未完成事务被遗忘，系统上游需要共同复位或具备重试/错误响应方案。

检查清单：grant 是候选还是已接受；成功事件明确；backpressure 时 owner 是否锁定；请求撤销如何释放；公平性指标和最坏等待可证明；固定优先是否容许饥饿；变长操作按何种资源成本计权；指针复位顺序定义；复位时未完成事务如何上报；仲裁路径是否进入关键时序。练习：固定优先级中 `req[3]` 始终为 1，`req[0]` 何时得到服务？答案：不会，除非系统对高优先请求有限流或设置抢占/老化，固定优先本身不提供无饥饿保证。练习二：ready=0 时是否可以推进轮询指针？答案：若 grant 是不可撤销候选就不可以；若架构允许无状态候选扫描、且 requester 保持事务直到单独握手，则需要另行证明不会丢失或错配，不能只凭“轮询更公平”决定。

## 第18章 CSR：寄存器映射是一份软件可见契约

本章 AXI4-Lite CSR 相关示例称为**案例 C（AXI4-Lite CSR）**；简化总线写法仅示范 CSR 副作用规则，完整通道时序仍以 AXI4-Lite 规范为准。

控制与状态寄存器（CSR）连接软件、固件或管理处理器和硬件逻辑。地址偏移、字段位宽、访问权限、复位值、写副作用、读副作用、保留位行为、字节使能、并发更新优先级，都是外部可观察行为；改动任何一项都可能破坏软件兼容性。CSR 并不是“几个 `logic` 加地址 case”那么简单，因为读写事务可能有等待周期，寄存器字段可能和硬件事件同拍更新，也可能跨时钟域。

先建立表格化的寄存器定义，再生成或手工实现 RTL。举例：`CTRL` 在偏移 0x00，bit0 为启动写 1 脉冲，bit1 为软件中断使能；`STATUS` 在 0x04，bit0 为忙状态只读，bit1 为完成 sticky 标志，写 1 清除（W1C）；`COUNT` 在 0x08 只读。保留位读零、写忽略。总线是否按 32 位访问、是否支持 byte strobe、读数据返回延迟、未对齐地址响应错误，必须由具体 bus 协议规定。不要假设任意 CSR 总线都和 APB、AXI-Lite 一样。

写数据应使用寄存后的事务接受脉冲驱动，而不是在 `write_enable` 长时间为高时每拍重复触发。`write_fire` 对应总线完成写传输的唯一采样事件。典型的 W1C 逻辑还需确定硬件置位与软件清除同拍时谁优先。下面假设硬件事件置位优先，软件写 1 清除只在没有同拍新完成事件时生效：

```systemverilog
always_ff @(posedge clk) begin
  if (!rst_n) begin
    done_sticky_q <= 1'b0;
    start_pulse_q <= 1'b0;
    irq_en_q      <= 1'b0;
  end else begin
    start_pulse_q <= 1'b0;
    if (write_fire && addr == CTRL_ADDR) begin
      if (wstrb[0] && wdata[0]) start_pulse_q <= 1'b1;
      if (wstrb[0]) irq_en_q <= wdata[1];
    end
    if (write_fire && addr == STATUS_ADDR && wstrb[0] && wdata[1])
      done_sticky_q <= 1'b0;
    if (engine_done)
      done_sticky_q <= 1'b1;
  end
end
```

非阻塞赋值遵循“同一变量同一过程里后面的有效赋值覆盖前面的有效赋值”行为，因此这里 engine_done 分支放在最后，置位优先。若把顺序反过来，软件清除优先；这并非无关紧要的代码风格，而是并发事件的硬件契约。为避免审阅者依赖赋值顺序，也可先计算 `status_next`，再只赋值一次。复位后 sticky=0、irq_en=0、start pulse=0，复位值应与软件手册一致。

错误推演：软件发起一次写事务，`write_enable` 因从设备等待而连续保持 3 拍。若 `start_pulse` 直接等于 `write_enable && wdata[0]`，启动信号会持续三拍；若下游模块把每拍高电平视为新 start，就会重复启动三次。正确实现要根据总线协议生成一个 `write_fire`，或只在写握手沿上更新寄存器，并将副作用做成寄存单周期脉冲。另一错误是 W1C 采用 `status <= status & ~wdata; if (event) status <= status | event_mask;` 但两条赋值位置不清，可能丢掉同拍事件。先定义同拍优先级并用 next-state 表达式更易审计。

字节使能会让软件单字节写入时只更新指定 lane。若 bus 支持 `WSTRB`，所有可写字段都要与其对应字节使能相与；若不支持则接口需固定全字写。对 W1C 位来说，未选中的字节不能清状态。保留位常见约定为写忽略读零，但某些标准定义保留位写回原值或必须写零，需按平台手册决定。读清状态（read-to-clear）副作用会让调试器、轮询软件和非侵入性观察相互影响，应尽量避免；如必须采用，定义清除发生在请求接收还是响应交付，避免响应因等待而重复清除。

寄存器宽度跨时钟域时，不能逐位对多位总线使用双触发器同步并假设数据原子一致；不同 bit 可能在不同时间稳定，出现撕裂值。对于静态配置，可采用源端保持数据、同步 toggle 握手、目的端捕获完整总线；对于事件流使用异步 FIFO。对于硬件状态跨域回读，采用返回握手或在目的域生成镜像。硬件和软件同时改写同一字段时，定义哪个值优先、是否采用 set/clear alias、是否写一清零。CSR 的软件可见原子性也涉及 64 位寄存器在 32 位总线上的拆分读写，需要 shadow/latch 或软件高低顺序约定。

CSR 代码适合从一份寄存器描述源生成 C 头文件、文档和 RTL，但生成链也需版本控制和审查。若手写，确保地址译码默认响应有定义，未映射地址不会意外读出上次数据；不要让 `rdata` 在没有读请求时组合依赖浮动地址而形成外部侧信道或功耗问题。同步读常需一拍响应，接口必须允许 wait/ready；异步组合读会增加地址到数据的组合路径。读写同时对同地址发生时，规定读回旧值还是新值。对外部可观察的寄存器变更通常需要版本和兼容性评审。

检查清单：地址偏移、访问权限和复位值与文档逐位一致；byte strobe 正确；副作用仅在握手沿发生一次；W1C、读清、硬件事件同拍优先级明确；非法地址响应定义；读延迟定义；宽寄存器跨时钟域/总线宽度处理原子性；保留位行为明确；软件头文件和 RTL 的单一真源策略可追踪。练习：状态位在本拍由 0 收到硬件事件置 1，同时软件 W1C 写 1，本文规定结果是什么？答案：1，因为硬件置位优先；写清除不会吞掉新事件。练习二：CPU 写事务等待时，start 信号保持三拍是否安全？答案：一般不安全；将 bus 写事务完成事件变成单周期脉冲，并确保下游也按脉冲接受。

## 第19章 事务管理：命令、标签、响应和取消边界

事务管理器负责把命令送入执行资源、追踪未完成请求、把响应匹配回发起者，并处理乱序、超时、取消、复位和错误。简单的控制 FSM 往往假设“发出请求后等一个结果”，但一旦允许多个 outstanding 请求，状态就不再只是一条线，而是一张带标签的资源表。每个已接受请求占用一个槽位，直到对应响应被消费或明确终止；槽位数量、标签空间、重复 ID 规则和乱序映射都是协议的一部分。

接受请求的唯一事件是 `cmd_valid && cmd_ready`。在该沿为请求分配 tag/slot，锁存命令字段，并令该槽进入 `PENDING`。发给执行单元的请求可能再次有 ready/valid 握手；只有那个握手发生后，管理器才能把槽标成 `SENT`。响应回来时使用 tag 找到槽，检查它确实有效且仍在等待，锁存结果并把槽转为 `DONE`。对上游提供响应时，只有 `rsp_valid && rsp_ready` 释放槽。若内部执行响应可乱序，不能用单一先进先出响应队列强行按请求序号匹配，除非协议确实保证响应顺序。

一个事务槽至少需要 valid/状态、tag、目的端/源端标识、写入数据或结果存储、错误状态、超时计数（若支持超时）。有些字段可通过外部命令保持到完成而不落寄存，但必须考虑源端何时能撤销。slot allocation 和 free 同拍发生时，容量应允许无气泡替换还是采用保守空一拍规则；这与 FIFO 满态策略类似，需要写清。若响应能够与新命令在同一时钟沿返回，必须定义 slot tag 的复用时机，避免同 tag 旧响应误命中新事务。

**现象：** 管理器同时接受请求 A、B；A 先返回时，系统却把 A 的响应发给 B 的发起者。

**根因：** 管理器只用 `pending_count` 记录总数，并以最近一次 tag 保存目的地。接受 B 后，A 的映射已被覆盖；乱序响应暴露了这一缺陷。

**修复：** 每笔被接受事务分配独立 slot，完整保存其 tag 和目的地；响应按标签查表，只在响应握手后释放对应 slot。只有下游协议明确保证严格顺序时，才可用 FIFO 保存顺序映射。

**检查点：** 用 A、B 两笔请求交错发出并反序返回；验证每个响应只命中有效 slot、目的地正确、slot 只释放一次，且 tag 复用不会接收旧响应。

事务状态机要处理终止竞争。若响应和 timeout 同拍，哪者优先？可选策略：响应优先，避免丢掉及时到达结果；超时优先，把此事务定为失败并忽略晚响应；或者报告竞态错误并保留诊断信息。若取消与响应同拍也类似。任意选一种都会影响系统行为，写入接口文档并使软件可观察。若超时后释放 tag，而下游允许晚响应，就不能立即复用同 tag，除非响应有 epoch/generation 区分或下游在取消时保证清空；否则旧响应会被误认为新事务。常用策略是墓碑槽（tombstone）保留到晚响应抵达、generation tag、复位整个下游事务域，或协议级取消确认。有限位数的 generation 也会回绕，因此仍需限定迟到响应的最长生存时间、回绕前的复用间隔，或取得清空确认；增加一位代际并不能无条件消除陈旧响应风险。

跨模块交接要区分“已被本模块接受”和“已被执行端接受”。本模块如果在 `cmd_fire` 后就向上游承诺负责，则必须在内部保存完整命令，不能只保存 tag 而依赖源端保持数据。下游若阻塞，槽位仍占用并能回压新请求；发送 valid 在 ready 低时保持数据和 tag。响应数据也必须保持至上游握手。若内部单个执行单元非抢占，调度策略会影响延迟；若多个目标并行，标签空间和完成顺序管理要覆盖所有子通道。

资源规模必须有上界。槽数为 O 时至少需要 `ceil(log2(O))` 位 slot index，但 tag 可能包含 generation 位；若 `O=1`，索引位宽仍需至少 1 位。占用位图可快速找到空槽，但优先编码较深；自由槽 FIFO 可以提高分配时序，但复位和并发分配/释放更复杂。响应 CAM 按外部 tag 查表可并行但面积随 O 增长。对小 O，显式 case 可能最清楚；对大 O，存储映射或 bank 化要查看综合后结构。不要为节省几十个寄存器而引入不可审计的 tag 复用假设。

检查清单：请求接受点与槽分配点一致；完整负载被保存；槽在所有终止路径恰好释放一次；并发响应可正确匹配；下游停顿期间请求稳定；上游停顿期间响应稳定；ID 唯一性和复用约束明确；超时/取消后的迟到响应策略明确；同拍分配释放容量行为明确；复位时未完成事务如何响应上游；计数器不会在重复完成时下溢。练习：容量 2，槽0和槽1都有效，槽0本拍响应握手，同时新命令到达，能否同拍接受？答案：能否由接口契约定义；若允许，应保证分配逻辑可复用本拍释放的槽，并确保迟到信号不会把旧槽误释放。如果实现保守拒绝，新命令需保持 valid 至下次 ready。练习二：超时后立即复用原 tag，但旧响应可能晚到，风险是什么？答案：旧响应会匹配新事务；需延迟复用、增加代际标识或得到取消确认。

## 第20章 错误、超时与恢复：设计可控的故障路径

故障处理不能只写“超时则报错”。需要明确检测条件、故障分类、恢复动作、对外响应、重试策略和故障期间资源占用。常见故障包括响应超时、校验失败、非法状态、FIFO 溢出/下溢、总线返回错误、目标复位、CDC 链路失效以及软件取消。每类故障都需要判定是否可恢复、是否可能重复执行副作用，以及怎样避免一笔请求永远挂住。工业模块的正常路径可能简单，故障路径却决定系统能否在部分组件异常时继续工作。

超时通常由事务管理器按“等待响应”状态计数。应规定计时起点：命令被本模块接受时，还是下游真正接受时。若下游背压很久，把等待响应时间从上游接受沿开始计，会把拥塞误报为目标无响应；若目标迟迟不接受请求，则这是发送/排队超时，可能需要另一计时器。计数到期的边界同样要走周期表。例如 `limit=5`，从下游接受沿之后的五个采样沿没有响应才超时，计时器应与第13章的 N 个后续沿定义一致。若响应与超时同拍，优先规则明确且能在 RTL 中表达。

```systemverilog
always_ff @(posedge clk) begin
  if (!rst_n) begin
    wait_q <= 1'b0;
    age_q <= '0;
    timeout_q <= 1'b0;
  end else begin
    timeout_q <= 1'b0;
      if (request_fire) begin // 仅空闲时接受；本例不支持零周期响应
      wait_q <= 1'b1;
      age_q <= '0;
    end else if (wait_q) begin
      if (response_fire) begin // 等待态下响应优先于超时
        wait_q <= 1'b0;
        age_q <= '0;
      end else if (age_q == LIMIT-1) begin
        wait_q <= 1'b0;
        age_q <= '0;
        timeout_q <= 1'b1;
      end else begin
        age_q <= age_q + 1'b1;
      end
    end
  end
end
```

此片段仅表达单笔等待，省略位宽保护、零限值策略和事务槽。`LIMIT=0` 时 `LIMIT-1` 会下溢或得到宽度不符常量；应参数检查要求 LIMIT>=1，或把 0 定义成关闭超时。契约要求 `request_fire` 只在 `wait_q==0` 的空闲态产生，且本单笔版本假定请求至少隔一个采样沿才可能收到响应，不支持接受请求的同沿零周期响应。代码的外层 `if (request_fire) ... else if (wait_q)` 意味着若错误地让 `request_fire` 与 `response_fire` 同时为 1，请求分支优先；在该契约下这种组合不应发生。若总线确实允许零周期响应，必须加入接受沿旁路/同拍完成逻辑，并重新定义请求、响应和超时优先级。更复杂的事务管理器应在每个 slot 上维护独立年龄或共享扫描计时器，不可让一笔响应重置所有其他事务的计时器。

错误推演：请求在时钟沿被接受并令 `age=0`。若代码每拍先加一，随后用 `if (age==LIMIT)` 判断，非阻塞赋值读的是旧值，超时会在预期之外晚一拍；若启动沿也被计入，则又可能早一拍。把 limit=1 手工展开：接受沿后 age=0；第一个后续沿若无响应，应产生 timeout=1。用这个最小边界验证实现。另一个错误是 `timeout = wait && age==LIMIT` 作为组合输出而没有寄存脉冲，状态清除/优先级改变时它可能在周期边界持续两拍或被外部漏采。

错误恢复有不同级别。局部重试适合幂等操作；若写寄存器、发射中断或扣减资源的事务可能已经在目标端执行，超时并不意味着“没发生”，盲目重试可能重复副作用。要么事务带唯一 ID、目标支持去重，要么读回确认，要么把操作设计成幂等，要么把结果报为“不确定”交由上层决策。局部软复位可以清理状态但会丢弃内部待处理事务；系统级复位影响面更大，也可能让未完成写入处于未知状态。复位策略应描述对未完成请求是否返回错误、是否要求上游复位、是否等待下游 reset-busy 解除。

故障锁存和恢复命令需保护诊断信息。可以记录首次错误码、事务 tag、目标地址、时间戳或累计计数；规定首次错误保持还是最新错误覆盖，以及软件清除和新错误同拍时优先级。错误信号应避免直接跨域；sticky 状态跨域也应通过同步或握手读取。安全输出在故障态应进入已定义值，例如关闭写使能、停止发送新请求、保留响应通道可回错误，不能让错误状态导致 valid 永久高且 data 未定义。若错误路径使用多周期清理状态机，应确保对外背压和资源释放有界。

检查清单：每个故障有检测、记录、响应、恢复策略；超时起点和边界定义；响应/超时同拍优先级明确；limit=0 和最大 limit 有定义；重试仅用于安全可重复操作或具备去重；超时后 late response 和 tag 复用有方案；复位/取消对未完成事务的结果已定义；安全输出在故障态已约束；故障记录的清除优先级明确；计数器按事务独立而非误影响其他 slot。练习：非幂等写命令等待超时后，是否应该自动重发？答案：不能默认重发，因为目标可能已经执行，只是响应丢失；需由协议去重、读回判定或上层确认。练习二：LIMIT=1，命令接受沿后第一个沿无响应，本文示例应何时 timeout？答案：该第一个后续沿，`age_q` 沿前为 0，比较 `LIMIT-1` 命中并产生单周期 timeout。

## 参考资料（官方/一手）

以下资料用于核对综合器支持、状态机编码、FIFO 复位/状态信号和存储器读写碰撞语义。不同器件系列与版本的细节可能不同，项目应以目标器件的当前文档和约束为准。

1. AMD Vivado Design Suite User Guide: Synthesis, Coding Guidelines: https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Coding-Guidelines
2. AMD Vivado Design Suite User Guide: Synthesis, Always Procedures (`always_ff`): https://docs.amd.com/r/2025.2-English/ug901-vivado-synthesis/Always-Procedures
3. AMD Vivado Design Suite User Guide: Synthesis, FSM Example: https://docs.amd.com/r/en-US/ug901-vivado-synthesis/FSM-Example-Verilog
4. AMD Vivado Properties Guide, `FSM_ENCODING`: https://docs.amd.com/r/2024.2-English/ug912-vivado-properties/FSM_ENCODING
5. AMD Embedded Memory Generator, Collision Behavior: https://docs.amd.com/r/en-US/pg326-embedded-memory-generator/Collision-Behavior
6. AMD FIFO Generator Product Guide PG057: https://docs.amd.com/api/khub/documents/Ds0JjAYlvIFpRMxJMOrbRw/content
7. AMD XPM FIFO Asynchronous, reset-busy and read mode details: https://docs.amd.com/r/en-US/ug1353-versal-architecture-ai-libraries/XPM_FIFO_ASYNC
8. Intel Agilex 5 Embedded Memory Design Considerations, FIFO Signals: https://www.intel.com/content/www/us/en/docs/programmable/813901/24-3/fifo-signals.html
9. Intel Agilex 3 Embedded Memory Design Considerations, Mixed-Port Read-During-Write Mode: https://www.intel.com/content/www/us/en/docs/programmable/849316/25-1/mixed-port-read-during-write-mode.html
10. Intel Avalon FIFO Memory Core User Guide: https://www.intel.com/content/www/us/en/content-details/666989/fifo-intel-fpga-ip-user-guide.html
11. AMD Vivado UG901, Choosing Between Distributed RAM and Dedicated Block RAM: https://docs.amd.com/r/2025.2-English/ug901-vivado-synthesis/Choosing-Between-Distributed-RAM-and-Dedicated-Block-RAM
12. AMD Vivado UG901, RAM HDL Coding Techniques: https://docs.amd.com/r/en-US/ug901-vivado-synthesis/RAM-HDL-Coding-Techniques
13. AMD Vivado UG901, Memory Inference Capabilities: https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Memory-Inference-Capabilities
14. AMD Vivado UG906, Report RAM Utilization: https://docs.amd.com/r/en-US/ug906-vivado-design-analysis/Report-RAM-Utilization
15. Intel Quartus Prime Pro Edition Design Recommendations, Use Synchronous Memory Blocks: https://www.intel.com/content/www/us/en/docs/programmable/683082/24-3/recommended-design-practices.html
16. Intel Quartus Prime Synthesis Resources Reports, RAM Summary: https://resources.altera.com/quartushelp/current/report/rpt/rpt_file_resource_usage_analysis.htm
17. Intel Quartus Prime, Guideline: Re-target Memory Blocks (reset and inference guidance): https://docs.altera.com/r/docs/683641/25.1/quartus-prime-pro-edition-user-guide/guideline-re-target-memory-blocks
