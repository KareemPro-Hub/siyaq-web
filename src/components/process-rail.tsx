const STEPS = [
  ["النص الأصلي", "نعرض الآية في موضعها من المصحف."],
  ["السياق المحيط", "نُظهر ما قبل الآية وما بعدها."],
  ["التفسير والمصدر", "نُقدّم التفسير من مصدره الموثق."]
];
export function ProcessRail() {
  return <section className="process-rail" aria-label="خطوات المراجعة">{STEPS.map(([title, text], i) => <div className="process-step" key={title}>
    <span className="step-number" aria-hidden="true">0{i + 1}</span><div className="step-copy"><h2>{title}</h2><p>{text}</p></div>
  </div>)}</section>;
}
