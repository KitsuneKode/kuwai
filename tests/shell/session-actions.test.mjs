import { expect, test } from 'bun:test';
import { functions } from '../helpers/qml.mjs';
import * as ChatStore from '../../shell/services/ai/chatstore.mjs';

function chat(active = 'B') {
  let abandons = 0, drains = 0;
  const scope = functions('shell/services/OllamaService.qml', ['clear', 'finishTurn'], {
    activeSessionId: active, draftSessionId: 'A', streaming: true, discardDraft: false,
    queue: [{id:'qa',session:'A'}, {id:'qb',session:'B'}, {id:'qc',session:'C'}], steering:[],
    messages:[{text:'old'}], summary:'old', summaryUpTo:1, pendingImage:'old', errorText:'old',
    pendingContext:{},pendingAppTitle:'old', draft:{parts:[{text:'partial'}],status:'streaming'},
    syncCurrentSession(){}, flushDeltas(){}, notifyDone(){},
    abandon(){abandons++; scope.discardDraft = true;}, drainAfterTurn:false,
    drainTimer:{restart(){drains++;}}, saveDelay:{restart(){}}, release(){},
  });
  return {scope,abandons:()=>abandons,drains:()=>drains};
}
test('clearing B preserves the streaming turn and queued work in A and C', () => {
  const t=chat(); t.scope.clear();
  expect(t.abandons()).toBe(0);
  expect(t.scope.queue.map(q=>q.session)).toEqual(['A','C']);
  expect(t.scope.streaming).toBe(true);
  expect(t.scope.messages).toEqual([]);
  expect(t.scope.pendingContext).toBeNull();
});
test('clearing streaming A also preserves B through real finishTurn cleanup', () => {
  const t=chat('A'); t.scope.clear(); t.scope.finishTurn();
  expect(t.abandons()).toBe(1);
  expect(t.scope.queue.map(q=>q.session)).toEqual(['B','C']);
  expect(t.drains()).toBe(1);
  expect(t.scope.draft).toBeNull();
});

test('prompt queued after Clear survives the old process exit and drains next',()=>{
 const t=chat('A');t.scope.clear();t.scope.queue=[{id:'new',session:'A',text:'new work after Clear'}];
 t.scope.finishTurn();expect(t.scope.queue.map(q=>q.id)).toEqual(['new']);expect(t.drains()).toBe(1);
});
test('discarded turns cannot accept an obsolete question answer',()=>{
 let written=0;
 const s=functions('shell/services/OllamaService.qml',['resolveRequest'],{discardDraft:true,pendingRequest:{id:'old'},chatProc:{running:true,write(){written++;}}});
 s.resolveRequest('old','accept','new text');expect(written).toBe(0);
});

test('forking a stopped conversation preserves queued work owned by existing chats',()=>{
 const s=functions('shell/services/OllamaService.qml',['forkAt'],{streaming:false,activeSessionId:'A',sessions:[{id:'A',title:'Original'}],messages:[{role:'user',text:'hi'}],summaryUpTo:0,model:'fixture',mode:'chat',queue:[{id:'keep',session:'A'}],syncCurrentSession(){},saveDelay:{restart(){}},ChatStore,leave(){},markDirty(){}});
 s.forkAt(-1);expect(s.queue.map(q=>q.id)).toEqual(['keep']);
});
