// رمز مساعد سِياق: روبوت مبسّط بلا عينين ولا ملامح وجه، وفي شاشته موجة صوت تدل على المحادثة.
export function AssistantRobot({className}: {className?: string}) {
  return <svg className={className} viewBox="0 0 48 48" aria-hidden="true" focusable="false">
    <circle cx="24" cy="5.5" r="2.6" fill="currentColor"/>
    <rect x="22.8" y="7" width="2.4" height="5" rx="1.2" fill="currentColor"/>
    <rect x="4.5" y="19.5" width="4" height="9" rx="2" fill="currentColor"/>
    <rect x="39.5" y="19.5" width="4" height="9" rx="2" fill="currentColor"/>
    <rect x="9.5" y="11.5" width="29" height="24" rx="8" fill="currentColor"/>
    <rect className="robot-screen" x="13" y="16" width="22" height="15" rx="5.5"/>
    <g className="robot-wave" fill="currentColor">
      <rect x="17.1" y="21.6" width="2.4" height="3.8" rx="1.2"/>
      <rect x="20.9" y="18.9" width="2.4" height="9.2" rx="1.2"/>
      <rect x="24.7" y="20.4" width="2.4" height="6.2" rx="1.2"/>
      <rect x="28.5" y="22.2" width="2.4" height="2.6" rx="1.2"/>
    </g>
    <path d="M13.5 46c0-4.8 4.7-7.6 10.5-7.6s10.5 2.8 10.5 7.6z" fill="currentColor"/>
  </svg>;
}
