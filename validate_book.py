from pathlib import Path
from collections import Counter
from html.parser import HTMLParser
import re,json,hashlib
root=Path(__file__).resolve().parent
s=(root/'RTL_Art_Manuscript.md').read_text()
chap=[int(x) for x in re.findall(r'^# 第(\d+)章',s,re.M)]
assert chap==list(range(1,34)),chap
sections=re.findall(r'^## (\d+\.\d+)\s',s,re.M)
assert len(sections)==len(set(sections)),[k for k,n in Counter(sections).items() if n>1]
for ch in 'ABCDEFGH': assert re.search('^# 附录'+ch,s,re.M)
fence=None
for line in s.splitlines():
 m=re.match(r'^(```|~~~)',line)
 if m:
  if fence is None:fence=m.group(1)
  elif fence==m.group(1):fence=None
assert fence is None
blocks=[b.strip() for b in s.split('\n\n') if len(b.strip())>180]
dups=[(n,b[:100]) for b,n in Counter(blocks).items() if n>1]
assert not dups,dups
for token in ['尚未撰写','本交付环境中未发现','前一分支使响应优先','\\`']:
 assert token not in s,token
class Check(HTMLParser):
 def __init__(self): super().__init__();self.ids=[];self.refs=[];self.tables=0;self.pres=0;self.missing_headings=[];self.subs=0
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if 'id' in a:self.ids.append(a['id'])
  if tag in ['h1','h2'] and 'id' not in a:self.missing_headings.append(tag)
  if tag=='sub':self.subs+=1
  if tag=='a' and a.get('href','').startswith('#'):self.refs.append(a['href'][1:])
  if tag=='table':self.tables+=1
  if tag=='pre':self.pres+=1
c=Check();c.feed((root/'RTL_Art_Reader.html').read_text())
assert len(c.ids)==len(set(c.ids))
assert not c.missing_headings
assert c.subs==6
assert not set(c.refs)-set(c.ids)
assert c.tables>=20 and c.pres>=25
logchecks={}
for log,marker in [('run.log','PASS all examples'),('bridge-iverilog.log','PASS: bounded AXI4-Lite CSR scenarios completed'),('pyslang.log','ERRORS: 0 DIAGNOSTICS: 0'),('bridge-pyslang.log','ERRORS: 0 DIAGNOSTICS: 0'),('sva-syntax.log','ERRORS: 0 DIAGNOSTICS: 0')]:
 data=(root/'examples/logs'/log).read_text();assert marker in data;logchecks[log]=marker
# Explicit stable anchors must survive insertion of an unrelated section.
from book_format import annotate_headings
probe='# 第12章 FSM\n\n## 12.1 状态选择\n\n## 12.2 输出保持\n'
original_ids=set(re.findall(r'<a id="([^"]+)"',annotate_headings(probe)))
changed=probe.replace('## 12.2','## 12.15 新增而无关的小节\n\n## 12.2')
assert original_ids <= set(re.findall(r'<a id="([^"]+)"',annotate_headings(changed)))
assert all(re.match(r'[a-z][a-z0-9-]+$',v) for v in c.ids)
assert not re.search(r'\\\[|S_\{k', (root/'RTL_Art_Reader.html').read_text())
# Every complete appendix block is copied verbatim from its executed source.
manifest=json.loads((root/'appendix_sources.json').read_text())
for item in manifest:
 source=(root/item['source']).read_bytes()
 assert hashlib.sha256(source).hexdigest()==item['sha256']
 assert source.decode().rstrip() in (root/'appendix_h.md').read_text()
for f in ['add4_baseline.sv','add4_pipeline.sv']:
 assert (root/'examples/ppa'/f).read_text().rstrip() in (root/'part4_5.md').read_text(), f
assert 'PASS part-select signedness' in (root/'examples/language/logs/run.log').read_text()
assert 'PASS add4 transactions=238' in (root/'examples/ppa/logs/iverilog.log').read_text()
report={'status' :'passed','chapters':chap,'appendices':list('ABCDEFGH'),'characters':len(s),'cjk_characters':len(re.findall(r'[\u3400-\u9fff]',s)),'numbered_sections':len(sections),'html_ids':len(c.ids),'html_tables':c.tables,'html_code_blocks':c.pres,'duplicate_long_blocks':dups,'execution_log_markers':logchecks,'stable_anchor_insertion_test':'passed','appendix_verbatim_test':'passed','part_select_simulation':'passed','pipeline_latency_alignment':'passed','manuscript_sha256':hashlib.sha256(s.encode()).hexdigest(),'limitations':'Structural and static HTML checks; browser screenshot QA was blocked by environment socket restrictions; not publication proof review. HDL evidence is limited to recorded configurations; generic synthesis is not physical PPA.'}
(root/'quality_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
