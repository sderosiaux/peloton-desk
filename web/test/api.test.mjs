import test from 'node:test';
import assert from 'node:assert/strict';
import {createAPI} from '../api.mjs';

test('startup HTML and truncated JSON are recoverable without leaking raw errors',async()=>{
  for(const [body,status] of [['<html>private server details</html>',503],['{',200],['null',200]]){
    const api=createAPI(async()=>new Response(body,{status}));
    await assert.rejects(api('status'),error=>error.retryable && !/Unexpected|private|SyntaxError/.test(error.message));
  }
});
test('network failure is recoverable and a following attempt succeeds',async()=>{
  let calls=0;
  const api=createAPI(async()=>{
    if(!calls++)throw new TypeError('Failed to fetch');
    return new Response(JSON.stringify({vncAvailable:true}));
  });
  await assert.rejects(api('status'),error=>error.retryable);
  assert.deepEqual(await api('status'),{vncAvailable:true});
});
test('authentication errors are explicit and do not trigger endless automatic retries',async()=>{
  const api=createAPI(async()=>new Response(JSON.stringify({error:'Connexion non autorisée.'}),{status:403}));
  await assert.rejects(api('auth',{}),error=>!error.retryable && error.message==='Connexion non autorisée.');
});
