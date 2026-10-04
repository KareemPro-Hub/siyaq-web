import test from 'node:test';
import assert from 'node:assert/strict';
import {validateImageFile,validateImageDimensions,validateExtractedText} from '../src/lib/image-policy';
import {POST as explain} from '../src/app/api/explain/route';

test('OCR rejects unsupported or oversized files and excessive decoded pixels',()=>{
 for(const file of [{type:'image/svg+xml',size:300},{type:'application/pdf',size:300},{type:'image/png',size:0},{type:'image/jpeg',size:11*1024*1024}])assert.throws(()=>validateImageFile(file));
 validateImageFile({type:'image/png',size:1000});
 for(const size of [[9000,40],[5000,5000],[0,50],[1.5,20]])assert.throws(()=>validateImageDimensions(...size as [number,number]));
 validateImageDimensions(2000,1500);
});
test('OCR requires actual Arabic letters and preserves recognized diacritics without inventing corrections',()=>{
 for(const text of ['','١٢٣٤','Hello 123','؟،؛'])assert.throws(()=>validateExtractedText(text));
 assert.throws(()=>validateExtractedText('س'.repeat(1001)));
 assert.equal(validateExtractedText('  اللَّهُ الصَّمَدُ  '),'اللَّهُ الصَّمَدُ');
});

test('old configured API key can never activate a paid explanation',async()=>{
 const oldKey=process.env.OPENAI_API_KEY;const oldFetch=globalThis.fetch;
 process.env.OPENAI_API_KEY='test-not-a-real-key';
 globalThis.fetch=async()=>{throw Error('Paid provider must never be called');};
 try{
  const response=await explain(new Request('http://localhost/api/explain',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({quote:'لا تقربوا الصلاة'})}));
  const result=await response.json();assert.equal(response.status,200);assert.equal(result.status,'abstained');assert.equal(result.claims.length,0);assert.ok(result.reason.includes('متوقف'));
 }finally{globalThis.fetch=oldFetch;if(oldKey===undefined)delete process.env.OPENAI_API_KEY;else process.env.OPENAI_API_KEY=oldKey;}
});
