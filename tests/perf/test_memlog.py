import importlib.machinery
import importlib.util
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def module():
 loader=importlib.machinery.SourceFileLoader('memlog_fixture',str(ROOT/'bin/rice-memlog'))
 spec=importlib.util.spec_from_loader('memlog_fixture',loader);m=importlib.util.module_from_spec(spec);loader.exec_module(m);return m

def test_runs_do_not_share_rotation_files(tmp_path):
 m=module()
 for run,value in [('run-a',100),('run-b',200),('run-a',300)]:
  m.append_sample(tmp_path,run,{'schema':1,'pssAnonKb':value},limit=2)
 a=[json.loads(l) for l in (tmp_path/'run-a.jsonl').read_text().splitlines()]
 b=[json.loads(l) for l in (tmp_path/'run-b.jsonl').read_text().splitlines()]
 assert [r['pssAnonKb'] for r in a]==[100,300]
 assert [r['pssAnonKb'] for r in b]==[200]
 m.append_sample(tmp_path,'run-a',{'schema':1,'pssAnonKb':400},limit=2)
 assert len((tmp_path/'run-a.jsonl').read_text().splitlines())==2

def test_collection_failure_is_attributable_not_anonymous(tmp_path):
 m=module();sample=m.collect(1234,proc_root=tmp_path)
 assert sample['pid']==1234
 assert sample['status']=='unavailable'
 assert 'error' in sample


def test_cli_records_requested_render_loop_and_source_revision(tmp_path):
 import os
 import subprocess
 result=subprocess.run([str(ROOT/'bin/rice-memlog'),'--config','synthetic','--run','synthetic','--render-loop','basic','--outputs','2','0','1','0','0','0','0','0'],env=dict(os.environ,XDG_STATE_HOME=str(tmp_path),KUWAI_REVISION='fixture-dirty'),capture_output=True,text=True)
 assert result.returncode==0,result.stderr
 sample=json.loads(next((tmp_path/'rice/memlog').glob('*.jsonl')).read_text())
 assert sample['renderLoop']=='basic' and sample['revision']=='fixture-dirty'
 assert sample['outputs']==2
