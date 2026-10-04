"use client";
export default function Error({reset}: {reset: () => void}) {return <main id="main" className="reading-page"><div className="reading-inner"><h1>تعذر فتح هذه الصفحة.</h1><p>حاول مرة أخرى. لن نعرض نصًا أو مصدرًا تخمينيًا.</p><button className="primary-button" onClick={reset}>إعادة المحاولة</button></div></main>;}
