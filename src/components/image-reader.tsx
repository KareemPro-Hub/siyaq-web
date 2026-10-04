"use client";
import {useEffect,useRef,useState} from 'react';
import {ImagePlus,X} from 'lucide-react';
import {validateImageFile,validateImageDimensions,validateExtractedText} from '@/lib/image-policy';
import type {Worker} from 'tesseract.js';

export function ImageReader({onText,busy,onBusyChange}:{onText:(text:string)=>void;busy:boolean;onBusyChange:(busy:boolean)=>void}){
 const picker=useRef<HTMLInputElement>(null);
 const worker=useRef<Worker|null>(null);
 const run=useRef(0);
 const imageURL=useRef<string|null>(null);
 const [pending,setPending]=useState(false);
 const [status,setStatus]=useState('');
 const [error,setError]=useState('');
 const [preview,setPreview]=useState<string|null>(null);
 useEffect(()=>onBusyChange(pending),[pending,onBusyChange]);
 function releaseImage(){if(imageURL.current)URL.revokeObjectURL(imageURL.current);imageURL.current=null;}
 function cancel(){run.current++;const active=worker.current;worker.current=null;void active?.terminate();releaseImage();setPreview(null);setPending(false);setStatus('أُلغي استخراج النص.');}
 useEffect(()=>()=>{run.current++;void worker.current?.terminate();if(imageURL.current)URL.revokeObjectURL(imageURL.current);},[]);
 async function read(file:File){
  const id=++run.current;
  releaseImage();setPreview(null);
  setError('');setStatus('نجهّز قراءة الصورة على جهازك…');setPending(true);
  let active:Worker|null=null;
  let timer:ReturnType<typeof setTimeout>|undefined;
  try{
   validateImageFile(file);
   const url=URL.createObjectURL(file);releaseImage();imageURL.current=url;
   const image=new window.Image();image.src=url;
   await image.decode();
   if(run.current!==id)return;
   validateImageDimensions(image.naturalWidth,image.naturalHeight);
   setPreview(url);
   // Uniformly resize large screenshots to keep WASM memory bounded.
   const scale=Math.min(1,2400/Math.max(image.naturalWidth,image.naturalHeight));
   const canvas=document.createElement('canvas');canvas.width=Math.round(image.naturalWidth*scale);canvas.height=Math.round(image.naturalHeight*scale);
   const context=canvas.getContext('2d');if(!context)throw Error('تعذرت قراءة الصورة في هذا المتصفح.');
   context.fillStyle='#fff';context.fillRect(0,0,canvas.width,canvas.height);context.drawImage(image,0,0,canvas.width,canvas.height);
   const {createWorker,OEM,PSM}=await import('tesseract.js');
   if(run.current!==id)return;
   timer=setTimeout(()=>{if(run.current===id){run.current++;void worker.current?.terminate();worker.current=null;setPending(false);setError('استغرقت القراءة وقتًا طويلًا. قصّ الاقتباس من الصورة أو اكتبه يدويًا.');setStatus('');}},90000);
   active=await createWorker('ara',OEM.LSTM_ONLY,{workerPath:'/ocr/worker.min.js',corePath:'/ocr/core',langPath:'/ocr/lang',workerBlobURL:false,logger:message=>{if(run.current===id)setStatus(message.status==='recognizing text'?`نقرأ النص… ${Math.round(message.progress*100)}٪`:'نجهّز قارئ العربية على جهازك…');}});
   if(run.current!==id){await active.terminate();return;}
   worker.current=active;
   await active.setParameters({tessedit_pageseg_mode:PSM.SINGLE_BLOCK,user_defined_dpi:'300'});
   const {data}=await active.recognize(canvas);
   if(run.current!==id)return;
   const text=validateExtractedText(data.text);
   onText(text);
   setStatus(data.confidence<60?'استُخرج النص. القراءة غير واضحة وقد تحتوي أخطاء كثيرة؛ صحّحه قبل المراجعة أو اكتبه يدويًا.':'استُخرج النص. راجعه وصحّحه أو حدّد الاقتباس قبل الضغط على «راجع الاقتباس».');
  }catch(e){if(run.current===id){setError(e instanceof Error&&/^(اختر|أبعاد|تعذرت|لم نقرأ|الصورة)/.test(e.message)?e.message:'تعذرت قراءة الصورة. جرّب صورة أوضح أو اكتب الاقتباس.');setStatus('');}}
  finally{clearTimeout(timer);if(active){if(worker.current===active)worker.current=null;await active.terminate().catch(()=>{});}if(run.current===id)setPending(false);}
 }
 return <div className="image-reader">
  <input ref={picker} type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={event=>{const file=event.currentTarget.files?.[0];event.currentTarget.value='';if(file)void read(file);}}/>
  <div className="image-reader-actions"><button type="button" className="outline-button" disabled={busy||pending} onClick={()=>picker.current?.click()}><ImagePlus size={18} aria-hidden="true"/>اقرأ من صورة</button>{pending&&<button type="button" className="text-button" onClick={cancel}><X size={17} aria-hidden="true"/>إلغاء القراءة</button>}</div>
  <p className="image-hint">الصورة لا تُرفع. اختر لقطة للاقتباس فقط؛ القراءة قد تفقد تشكيلًا أو حروفًا، فراجع النص قبل البحث.</p>
  {preview&&<div className="image-preview"><img src={preview} alt="الصورة المختارة لاستخراج الاقتباس"/><button type="button" className="text-button" onClick={cancel} aria-label="إزالة الصورة">إزالة الصورة</button></div>}
  <p role="status" aria-live="polite" className="image-status">{status}</p>{error&&<p role="alert" className="form-error">{error}</p>}
 </div>;
}
