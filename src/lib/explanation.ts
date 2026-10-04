import type {ReviewResult, Tafsir} from "./types";
export type Evidence = Tafsir & {id:string;verseId:string};
export type Explanation = {status:"ready"|"abstained";claims:{text:string;evidence:Evidence;excerpt:string}[];sourceVersion:string;model?:string;notice:string;reason?:string};
export const EXPLANATION_NOTICE="شرح مساعد مولّد من النصوص المعروضة، وليس تفسيرًا مستقلًا أو فتوى أو تصحيحًا للأسانيد. راجع الأدلة الأصلية.";
export function collectEvidence(result:ReviewResult,eligible:ReadonlySet<number>):Evidence[]{
  if(!result.selected || result.selected.kind==="possible")return [];
  let total=0;
  // Omit oversized entries rather than cutting an argument mid-sentence.
  return result.tafsir.flatMap(g=>g.entries.map((e,i)=>({...e,id:`${g.verseId}:${e.bookId}:${i}`,verseId:g.verseId}))).filter(e=>{if(!eligible.has(e.bookId)||!e.text.trim()||e.text.length>8000||total+e.text.length>18000)return false;total+=e.text.length;return true;}).slice(0,8);
}
type ModelDraft={status:"ready"|"abstained";claims:{text:string;evidenceId:string;excerpt:string}[]};
export const draftSchema={type:"object",additionalProperties:false,required:["status","claims"],properties:{status:{type:"string",enum:["ready","abstained"]},claims:{type:"array",maxItems:3,items:{type:"object",additionalProperties:false,required:["text","evidenceId","excerpt"],properties:{text:{type:"string"},evidenceId:{type:"string"},excerpt:{type:"string"}}}}}};
const object=(v:unknown):v is Record<string,unknown>=>!!v&&typeof v==="object"&&!Array.isArray(v);
const keys=(v:Record<string,unknown>,allowed:string[])=>Object.keys(v).every(k=>allowed.includes(k));
export function validateDraft(input:unknown,evidence:Evidence[]):ModelDraft{
  if(!object(input)||!keys(input,["status","claims"])||!["ready","abstained"].includes(String(input.status))||!Array.isArray(input.claims)||input.claims.length>3)throw Error("Invalid explanation structure");
  if((input.status==="ready")!==(input.claims.length>0))throw Error("Inconsistent status");
  const claims=input.claims.map(c=>{
    if(!object(c)||!keys(c,["text","evidenceId","excerpt"])||typeof c.text!=="string"||typeof c.evidenceId!=="string"||typeof c.excerpt!=="string")throw Error("Invalid claim");
    const source=evidence.find(e=>e.id===c.evidenceId);
    if(!source||c.excerpt.trim().length<12||c.excerpt.length>1500||!source.text.includes(c.excerpt))throw Error("Unverifiable citation");
    if(!c.text.trim()||c.text.length>700||/https?:|www\.|[<>]|﴿|﴾/i.test(c.text))throw Error("Unsupported text");
    return {text:c.text.trim(),evidenceId:c.evidenceId,excerpt:c.excerpt};
  });
  return {status:input.status as ModelDraft["status"],claims};
}
export function renderExplanation(draft:ModelDraft,evidence:Evidence[],version:string,model:string):Explanation{return {status:draft.status,claims:draft.claims.map(c=>({text:c.text,excerpt:c.excerpt,evidence:evidence.find(e=>e.id===c.evidenceId)!})),sourceVersion:version,model,notice:EXPLANATION_NOTICE};}
export function buildExplanationInput(result:ReviewResult,evidence:Evidence[]){
  // Free user input stays on our server; the provider receives canonical verses and vetted evidence only.
  return JSON.stringify({verses:result.selected?.verses.map(v=>({id:v.id,text:v.text})),evidence:evidence.map(e=>({id:e.id,verseId:e.verseId,bookName:e.bookName,text:e.text}))});
}
