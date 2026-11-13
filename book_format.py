"""Offline reader formatting with stable, explicit heading IDs.

IDs use chapter identities and semantic heading text, never document position.
Renaming a heading intentionally can be accompanied by an override in ANCHORS.
"""
import hashlib,re

CHAPTER_SLUGS = ['rtl-philosophy','requirements','implementation-flow','data-objects','width-sign','four-state','scheduling','combinational','sequential','abstraction','parameters','fsm','timer','handshake','pipeline','fifo','arbitration','csr','transactions','recovery','clock-reset','cdc-rdc','timing','power-area','integration-dft','verification-plan','sva','testbench','quality-gates','coding-review','reusable-ip','ppa-loop','release']
PART_NUMBERS = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6}
ANCHORS = {'Verilog/SystemVerilog 编程艺术':'book-title','工业级 RTL 设计的原理、权衡与实践':'book-subtitle','全书验证记录与版本说明':'delivery-status','H.1 案例 A（Timer）的完整 RTL':'case-a-timer','H.2 案例 B（FIFO）的完整 RTL':'case-b-fifo','H.3 案例 C（AXI4-Lite CSR）的完整 RTL':'case-c-full-rtl'}

def normalize_code_blocks(text):
    lines=text.splitlines(); out=[]; i=0; fence=False
    while i<len(lines):
        line=lines[i]
        match=re.match(r'^(```|~~~)(.*)$',line)
        if match:
            if fence: out.append('```');fence=False
            else:
                language=match.group(2).strip() or 'text'
                if language in ['sv','verilog','SystemVerilog']:language='systemverilog'
                if language in ['bash','shell']:language='sh'
                out.append('```'+language);fence=True
            i+=1;continue
        if not fence and line.startswith('    '):
            block=[]
            while i<len(lines) and (lines[i].startswith('    ') or not lines[i].strip()):
                block.append(lines[i][4:] if lines[i].startswith('    ') else '');i+=1
            while block and not block[-1]:block.pop()
            content='\n'.join(block)
            language='systemverilog' if re.search(r'\b(always_ff|always_comb|always|assign|logic|typedef|endclocking|assert property|cover property|parameter|case|if|for)\b',content) else 'text'
            out+=['```'+language,*block,'```',''];continue
        out.append(line);i+=1
    assert not fence
    return '\n'.join(out)+'\n'

def annotate_headings(text):
    out=[];context='front';fence=False;used=set()
    for line in text.splitlines():
        if line.startswith('```'):fence=not fence
        match=re.match(r'^(#{1,6}) (.+)$',line) if not fence else None
        if match:
            title=match.group(2).strip()
            chapter=re.match(r'第(\d+)章',title)
            part=re.match(r'第([一二三四五六])篇(?:[\s：]|$)',title)
            appendix=re.match(r'附录([A-Z])',title)
            if chapter:
                n=int(chapter.group(1));anchor=f'ch{n:02d}-{CHAPTER_SLUGS[n-1]}';context=f'ch{n:02d}'
            elif part:
                context=f'part-{PART_NUMBERS[part.group(1)]}';anchor=context
            elif appendix:
                context='appendix-'+appendix.group(1).lower();anchor=context
            elif title.startswith('案例 C') or title.startswith('案例C'):
                anchor='case-c-axi4lite-csr';context='case-c'
            elif title in ANCHORS:anchor=ANCHORS[title]
            else:
                semantic=re.sub(r'^(?:\d+\.\d+|[A-Z]\.\d+|\d+\.)\s*','',title)
                anchor=context+'-'+hashlib.sha256(semantic.encode()).hexdigest()[:10]
            assert anchor not in used, (anchor,title)
            used.add(anchor)
            out.extend([f'<a id="{anchor}"></a>','',line])
        else:out.append(line)
    return '\n'.join(out)+'\n'

def headings_for_html(text):
    # Transfer each explicit source anchor onto the heading itself for TOC.
    return re.sub(r'<a id="([a-z0-9-]+)"></a>\n\n(#{1,6} .+)',lambda m:m.group(2)+' {#'+m.group(1)+'}',text)
