import {mkdir,copyFile,writeFile,readFile,readdir} from 'node:fs/promises';
import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
const destination='public/ocr';
await mkdir(`${destination}/core`,{recursive:true});
await mkdir(`${destination}/lang`,{recursive:true});
await copyFile('node_modules/tesseract.js/dist/worker.min.js',`${destination}/worker.min.js`);
await copyFile('node_modules/tesseract.js/dist/worker.min.js.LICENSE.txt',`${destination}/worker.min.js.LICENSE.txt`);
await copyFile('node_modules/tesseract.js-core/LICENSE',`${destination}/core/LICENSE`);
// LSTM-only is sufficient; retain SIMD and non-SIMD builds for browser compatibility.
for(const file of await readdir('node_modules/tesseract.js-core')) {
 if(/lstm\.(wasm|wasm\.js)$/.test(file)) await copyFile(`node_modules/tesseract.js-core/${file}`,`${destination}/core/${file}`);
}
const sha='87416418657359cb625c412a48b6e1d6d41c29bd';
const manifest={engine:'Tesseract.js 7.0.0',source:'https://github.com/tesseract-ocr/tessdata_fast',revision:sha,license:'Apache-2.0',files:[]};
for(const language of ['ara','eng']){
 const url=`https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/${sha}/${language}.traineddata`;
 const response=await fetch(url);
 if(!response.ok) throw Error(`Language download failed: ${response.status}`);
 const bytes=Buffer.from(await response.arrayBuffer());
 const zipped=gzipSync(bytes);
 await writeFile(`${destination}/lang/${language}.traineddata.gz`,zipped);
 manifest.files.push({language,url,sha256:createHash('sha256').update(zipped).digest('hex'),bytes:zipped.length});
}
const license=await fetch(`https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/${sha}/LICENSE`);
if(!license.ok) throw Error('Missing OCR language license');
await writeFile(`${destination}/lang/LICENSE`,await license.text());
await writeFile(`${destination}/manifest.json`,JSON.stringify(manifest,null,2));
console.log(JSON.stringify(manifest,null,2));
