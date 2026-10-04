// فحص تزامن محدود محليًا فقط (لا يُشغَّل على الإنتاج): دفعات متزامنة على /api/review.
const base = process.env.QA_URL || "http://127.0.0.1:4192";
if (!["127.0.0.1", "localhost", "[::1]"].includes(new URL(base).hostname)) throw new Error("فحص التزامن مسموح محليًا فقط.");
const quotes = ["لا تقربوا الصلاة", "فبأي آلاء ربكما تكذبان", "ولا تقربوا الصلوه وانتم سكري حتي تعلموا ما تقولون", "هذا نص عادي ليس من القرآن الكريم للتجربة", "مهطعين مقنعي رءوسهم"];
const call = async q => {const t = performance.now(); const r = await fetch(base + "/api/review", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({quote: q})}); await r.json(); return {ms: performance.now() - t, status: r.status};};
const t0 = performance.now(); const first = await call(quotes[0]); console.log("أول طلب بعد التشغيل", Math.round(first.ms), "ms");
for (const n of [10, 25, 50]) {
  const rows = await Promise.all(Array.from({length: n}, (_, i) => call(quotes[i % quotes.length])));
  const ms = rows.map(r => r.ms).sort((a, b) => a - b); const p = q => Math.round(ms[Math.min(ms.length - 1, Math.floor(q * ms.length))]);
  console.log(`${n} متزامن: p50=${p(.5)}ms p95=${p(.95)}ms max=${Math.round(ms.at(-1))}ms أخطاء=${rows.filter(r => r.status !== 200).length}`);
}
