# تسجيلات مساعد سِياق

الردود المنطوقة ملفات MP3 جاهزة في `public/assistant-audio`. لا يتصل الموقع بأي خدمة نطق أثناء الزيارة.

## التوليد (مرة واحدة، مجانًا)

- **الأداة:** Google AI Studio ← Generate speech، بالطبقة المجانية. لا مفتاح API ولا فوترة.
- **النموذج:** `gemini-3.8-flash-tts`.
- **الصوت:** Achird (Friendly · Lower middle pitch). اختاره كريم في ٥ أكتوبر ٢٠٢٦.
- **الأسلوب (Style):**

  > Bright, friendly and engaged host welcoming a visitor with a warm smile. Upbeat, lively energy and a natural, unhurried pace. Expressive, varied intonation with clear emphasis on key words and a welcoming lift on the greeting and the question. Clear Modern Standard Arabic (Fusha) with precise classical articulation; follow the diacritics exactly and give every long vowel its full length. Pronounce الْآيَةُ and الْآيَاتُ fully and calmly (al-aayah, al-aayaat) with a clear long aa, never clipped, swallowed or rushed. Awake and attentive, never sleepy, monotone or robotic; professional, not over-acted.

- **النصوص:** في `spoken.json`، فصحى مشكولة.
  - «لقطة شاشة» بدل «صورة» حتى لا تُسمع «سورة».
  - مسافة قبل «؟».
  - لا آيات.
- **المجموعات:** في `batches.json`.
  - كل مجموعة تُولَّد في جلسة جديدة.
  - بين الردود `<long pause> <long pause>`.
  - الملفات الأصلية `batchN.wav` محفوظة خارج المستودع في مجلد العينات.

## التقسيم

```
python3 scripts/assistant-audio/split.py <مجلد batchN.wav> <مجلد الإخراج>
```

- **اختيار الفواصل:** يختار فواصل الصمت التي تجعل مدة كل رد أقرب لطول نصه، ويطبع جودة المطابقة.
- **المعالجة:** يقص الأطراف ويضيف تلاشيًا قصيرًا، ثم يوحّد الارتفاع على ‎-16 LUFS.
- **التصدير:** MP3 أحادي، 24kHz، 64kbps.
- **التقرير:** `report.json` فيه مدة كل ملف ونسبة الثواني لكل حرف. النسبة الطبيعية تقريبًا بين 0.05 و0.07.
- **بعد التقسيم:** انسخ الملفات إلى `public/assistant-audio`، ثم شغّل `npm test`.
