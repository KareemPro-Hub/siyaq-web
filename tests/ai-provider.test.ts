import test from "node:test";
import assert from "node:assert/strict";
import {reviewQuote} from "../src/lib/data";
import {collectEvidence} from "../src/lib/explanation";
import {generateExplanation} from "../src/lib/ai-provider";

// No live requests or real credentials: exercise the provider boundary offline.
const result=reviewQuote("لا تقربوا الصلاة");
const evidence=collectEvidence(result,new Set([269]));
const draft={status:"ready",claims:[{text:"يشرح النص المنقول هذا الموضع.",evidenceId:evidence[0].id,excerpt:evidence[0].text.slice(0,40)}]};
function completed(value:unknown){return Response.json({status:"completed",output:[{content:[{type:"output_text",text:JSON.stringify(value)}]}]});}
async function mockProvider(run:(requests:Record<string,unknown>[])=>Promise<void>,responses:Response[]){
  const originalFetch=globalThis.fetch;
  const originalKey=process.env.OPENAI_API_KEY;
  const originalModel=process.env.OPENAI_MODEL;
  const requests:Record<string,unknown>[]=[];
  process.env.OPENAI_API_KEY="offline-test-fixture";
  process.env.OPENAI_MODEL="offline-test-model";
  globalThis.fetch=async(url,options)=>{
    assert.equal(url,"https://api.openai.com/v1/responses");
    assert.equal(options?.cache,"no-store");
    assert.ok(options?.signal instanceof AbortSignal);
    requests.push(JSON.parse(String(options?.body)));
    const response=responses.shift();
    assert.ok(response,"Unexpected extra provider request");
    return response;
  };
  try{await run(requests);}finally{
    globalThis.fetch=originalFetch;
    if(originalKey===undefined)delete process.env.OPENAI_API_KEY;else process.env.OPENAI_API_KEY=originalKey;
    if(originalModel===undefined)delete process.env.OPENAI_MODEL;else process.env.OPENAI_MODEL=originalModel;
  }
}
test("provider boundary requires two checks and attaches only server evidence",async()=>{
  await mockProvider(async(requests)=>{
    const explanation=await generateExplanation({...result,quote:"PRIVATE_INPUT_DO_NOT_FORWARD"},evidence);
    assert.equal(explanation.status,"ready");
    assert.deepEqual(explanation.claims[0].evidence,evidence[0]);
    assert.equal(explanation.model,"offline-test-model");
    assert.equal(requests.length,2);
    for(const request of requests){
      assert.equal(request.store,false);
      assert.equal(request.model,"offline-test-model");
      assert.equal(request.max_output_tokens,3000);
      assert.ok(!String(request.input).includes("PRIVATE_INPUT_DO_NOT_FORWARD"));
      assert.equal((request.text as {format:{strict:boolean}}).format.strict,true);
    }
  },[completed(draft),completed({supported:true})]);
});
test("provider abstention stops without a paid support check",async()=>{
  await mockProvider(async(requests)=>{
    const explanation=await generateExplanation(result,evidence);
    assert.equal(explanation.status,"abstained");
    assert.deepEqual(explanation.claims,[]);
    assert.equal(requests.length,1);
  },[completed({status:"abstained",claims:[]})]);
});
test("unsupported draft is never returned to the user",async()=>{
  await mockProvider(async(requests)=>{
    const explanation=await generateExplanation(result,evidence);
    assert.equal(explanation.status,"abstained");
    assert.deepEqual(explanation.claims,[]);
    assert.equal(requests.length,2);
  },[completed(draft),completed({supported:false})]);
});
for(const [name,response,error] of [
  ["provider failure",new Response(null,{status:429}),"AI_PROVIDER_UNAVAILABLE"],
  ["incomplete output",Response.json({status:"incomplete",output:[]}),"AI_INCOMPLETE"],
  ["provider refusal",Response.json({status:"completed",output:[{content:[{type:"refusal"}]}]}),"AI_REFUSED"],
  ["fabricated citation",completed({...draft,claims:[{...draft.claims[0],excerpt:"اقتباس مختلق غير موجود في الدليل المعتمد"}]}),"Unverifiable citation"],
] as const){
  test(`${name} fails closed without retries`,async()=>{
    await mockProvider(async(requests)=>{
      await assert.rejects(generateExplanation(result,evidence),new RegExp(error));
      assert.equal(requests.length,1);
    },[response]);
  });
}
test("failed second check never exposes a previously generated draft",async()=>{
  await mockProvider(async(requests)=>{
    await assert.rejects(generateExplanation(result,evidence),/AI_PROVIDER_UNAVAILABLE/);
    assert.equal(requests.length,2);
  },[completed(draft),new Response(null,{status:503})]);
});
