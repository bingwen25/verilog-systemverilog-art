from pathlib import Path
import re,hashlib,json
from book_format import normalize_code_blocks,annotate_headings
root=Path(__file__).resolve().parent

# Appendix code is included verbatim from the executed, canonical sources.
appendix=['# 附录H 三个案例的完整教学 RTL', '''本附录让纸书与离线阅读版也能完成“契约→实现”的阅读闭环。代码直接从配套源文件纳入，不维护第二份手工副本；`examples/` 中的源码是可执行版本的唯一来源。对应自检、配置和工具记录见文末验证记录。

这些实现用于教学。Timer/FIFO参数合法性检查中的`initial $fatal`用于仿真/构建诊断，不构成对所有ASIC综合工具的支持承诺；生产集成可把配置检查放在构建阶段。FIFO的组合读不承诺推断为块RAM。案例C不提供完整AXI协议认证或安全隔离。''']
specs=[('H.1 案例 A（Timer）的完整 RTL','examples/timer.sv','第2章规定接受后第N个后续边沿完成；取消优先、忙时启动不接受，`period=0`不接受。参数W≥1，本次回归W=8。'),('H.2 案例 B（FIFO）的完整 RTL','examples/sync_fifo.sv','单时钟、组合首字可见、空态无直通、满态保守回压；非二次幂地址显式绕回。本次回归WIDTH=16、DEPTH=1/3/4。'),('H.3 案例 C（AXI4-Lite CSR）的完整 RTL','examples/bridge/axi4lite_csr.sv','32位数据，AW与W独立一槽，读写各一笔在途；响应背压保持，支持WSTRB，同沿读与写提交返回旧CTRL。')]
manifest=[]
for title,path,note in specs:
    data=(root/path).read_text();appendix+=['## '+title,note,'```systemverilog\n'+data.rstrip()+'\n```']
    manifest.append({'heading':title,'source':path,'sha256':hashlib.sha256(data.encode()).hexdigest()})
(root/'appendix_h.md').write_text('\n\n'.join(appendix)+'\n')
(root/'appendix_sources.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
chunks=[]
for name in ['front_matter.md','part1.md','part2.md','part3.md','part4_5.md','part6_appendices.md','appendix_h.md','bridge_case.md','delivery_status.md','review_response_v1.1.md']:
    s=(root/name).read_text().replace('\\`','`')
    s=re.sub(r'^#+ (第\d+章[^\n]*)',r'# \1',s,flags=re.M)
    s=re.sub(r'^### (\d+\.\d+[^\n]*)',r'## \1',s,flags=re.M)
    s=re.sub(r'^## (附录[A-Z][^\n]*)',r'# \1',s,flags=re.M)
    s=s.replace('# 第三篇：工业 RTL 的控制与数据通路','# 第三篇　RTL 结构与微架构设计').replace('# 第六篇 工业 RTL 的工程化与交付','# 第六篇　编码规范与工程实践')
    chunks.append(s)
s=normalize_code_blocks('\n\n'.join(chunks))
# Normalize labels only in prose, never inside the verbatim source code.
lines=[];fenced=False
for line in s.splitlines():
    if line.startswith('```'):fenced=not fenced
    if not fenced:
        for letter,label in [('A','Timer'),('B','FIFO'),('C','AXI4-Lite CSR')]:
            line=re.sub(r'案例\s*'+letter+r'(?!（'+re.escape(label)+'）)',f'案例 {letter}（{label}）',line)
        line=re.sub(r'(?<![\(<\[])https?://[A-Za-z0-9./_?=&%:+~#@-]+',lambda m:'['+m.group()+']('+m.group()+')',line)
    lines.append(line)
s=annotate_headings('\n'.join(lines)+'\n')
(root/'RTL_Art_Manuscript.md').write_text(s)
chapters=[int(x) for x in re.findall(r'^# 第(\d+)章',s,re.M)]
assert chapters==list(range(1,34)),chapters
for ch in 'ABCDEFGH':assert re.search(r'^# 附录'+ch,s,re.M),ch
assert '尚未撰写' not in s
print('33 chapters, 8 appendices; characters:',len(s),'bytes:',len(s.encode()))
