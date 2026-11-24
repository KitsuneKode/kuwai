import importlib.machinery
import importlib.util
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def module():
 loader=importlib.machinery.SourceFileLoader('memlog_fixture',str(ROOT/'bin/kuwai-memlog'))
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
 result=subprocess.run([str(ROOT/'bin/kuwai-memlog'),'--config','synthetic','--run','synthetic','--render-loop','basic','--outputs','2','--saver-visible','no','--displays-off','yes','--wallpaper-state','hidden','0','1','0','0','0','0','0'],env=dict(os.environ,XDG_STATE_HOME=str(tmp_path),KUWAI_REVISION='fixture-dirty'),capture_output=True,text=True)
 assert result.returncode==0,result.stderr
 sample=json.loads(next(p for p in (tmp_path/'kuwai/memlog').glob('*.jsonl') if not p.name.startswith('hypr-')).read_text())
 assert sample['renderLoop']=='basic' and sample['revision']=='fixture-dirty'
 assert sample['outputs']==2
 assert sample['activity']=={'saverVisible':False,'displaysOff':True,'wallpaper':'hidden'}


def test_swap_is_recorded(tmp_path):
 m=module();(tmp_path/'7').mkdir()
 (tmp_path/'7/stat').write_text('7 (Hyprland) S '+' '.join(['0']*18)+' 4242 0\n')
 (tmp_path/'7/smaps_rollup').write_text('Rss: 100 kB\nPss: 90 kB\nPss_Anon: 80 kB\nSwap: 600 kB\nSwapPss: 550 kB\n')
 s=m.collect(7,proc_root=tmp_path)
 assert s['startTicks']==4242 and s['swapKb']==600 and s['swapPssKb']==550 and s['rssKb']==100


def test_the_compositor_gets_its_own_series(tmp_path):
 import os
 import subprocess
 run=tmp_path/'run';sig='fixture-sig';(run/'hypr'/sig).mkdir(parents=True)
 (run/'hypr'/sig/'hyprland.lock').write_text(f'{os.getpid()}\nwayland-1\n')
 env=dict(os.environ,XDG_STATE_HOME=str(tmp_path),XDG_RUNTIME_DIR=str(run),HYPRLAND_INSTANCE_SIGNATURE=sig)
 for _ in range(2):
  r=subprocess.run([str(ROOT/'bin/kuwai-memlog'),'--config','c','--run','r','0','0','0','0','0','0','0'],env=env,capture_output=True,text=True)
  assert r.returncode==0,r.stderr
 hypr=list((tmp_path/'kuwai/memlog').glob('hypr-*.jsonl'))
 assert len(hypr)==1
 rows=[json.loads(l) for l in hypr[0].read_text().splitlines()]
 assert len(rows)==2 and all(x['role']=='compositor' and x['pid']==os.getpid() and x['status']=='ok' for x in rows)
