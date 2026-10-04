export const IMAGE_MAX_BYTES = 10 * 1024 * 1024;
export const IMAGE_MAX_PIXELS = 20_000_000;
export const IMAGE_MAX_EDGE = 8000;
const accepted = new Set(['image/png','image/jpeg','image/webp']);
export function validateImageFile(file:{type:string;size:number}) {
 if(!accepted.has(file.type)) throw Error('اختر صورة PNG أو JPEG أو WebP.');
 if(file.size <= 0 || file.size > IMAGE_MAX_BYTES) throw Error('اختر صورة لا يتجاوز حجمها ١٠ ميجابايت.');
}
export function validateImageDimensions(width:number,height:number){
 if(!Number.isInteger(width)||!Number.isInteger(height)||width<1||height<1||width>IMAGE_MAX_EDGE||height>IMAGE_MAX_EDGE||width*height>IMAGE_MAX_PIXELS) throw Error('أبعاد الصورة كبيرة جدًا. قصّ منطقة الاقتباس وأعد المحاولة.');
}
export function validateExtractedText(raw:string){
 const text=raw.trim();
 if(!Array.from(text).some(letter=>/\p{Script=Arabic}/u.test(letter)&&/\p{L}/u.test(letter)))throw Error('لم نقرأ نصًا عربيًا واضحًا. قصّ منطقة الاقتباس أو اكتب النص يدويًا.');
 if(text.length>1000)throw Error('الصورة تحتوي نصًا طويلًا. قصّ منطقة الاقتباس فقط ثم أعد المحاولة.');
 return text;
}
