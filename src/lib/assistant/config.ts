// تعطيل المساعد وحده دون لمس بقية الموقع: اضبط NEXT_PUBLIC_SIYAQ_ASSISTANT=off وقت البناء ثم أعد النشر،
// أو غيّر السطر التالي إلى false. عند التعطيل لا يظهر الزر ولا يُحمَّل أي جزء من المساعد.
export const ASSISTANT_ENABLED = process.env.NEXT_PUBLIC_SIYAQ_ASSISTANT !== "off";
