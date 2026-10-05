"use client";
// لوحة مساعد سِياق: تُحمَّل عند الضغط على «تحدث مع سِياق» فقط.
// الردود كلها من src/content/assistant-responses.json؛ اختيار الرد بقواعد الكلمات في src/lib/assistant/intents.ts.
// لا تسجيل ولا حفظ للمحادثة: تبقى في ذاكرة الصفحة وتُمحى بإغلاق اللوحة.
import {useCallback, useEffect, useRef, useState} from "react";
import {usePathname, useRouter} from "next/navigation";
import {Mic, Send, Square, Volume2, VolumeX, X} from "lucide-react";
import {useAssistantBridge, type PendingAction} from "./assistant-provider";
import {matchRequest, messages as M, starters, type AllowedPath, type AssistantAction, type AssistantTab, type Intent} from "@/lib/assistant/intents";
import {listenOnce, loadVoices, pickArabicVoice, recognitionCtor, speak, type Listening, type RecognitionErrorKind, type Speaking} from "@/lib/assistant/speech";

type Entry = {id: number; from: "assistant" | "user"; text: string; heard?: boolean; actions?: AssistantAction[]; options?: Intent[]; heardText?: string; replace?: {text: string; review: boolean}};
type Status = "idle" | "listening" | "speaking";
const ERROR_TEXT: Record<Exclude<RecognitionErrorKind, "aborted">, string> = {"denied": M.micDenied, "no-speech": M.noSpeech, "no-mic": M.noMic, "network": M.network, "language": M.languageUnsupported, "failed": M.recognitionFailed};
const REVIEW_ACTION: AssistantAction = {type: "focusQuote", label: "راجع اقتباسًا"};
const MAX_ENTRIES = 30;

export function AssistantPanel({onClose}: {onClose: () => void}) {
  const bridge = useAssistantBridge()!;
  const router = useRouter();
  const pathname = usePathname();
  const [log, setLog] = useState<Entry[]>([]);
  const [status, setStatus] = useState<Status>("idle");
  const [interim, setInterim] = useState("");
  const [voice, setVoice] = useState<SpeechSynthesisVoice | null | undefined>(undefined);
  const [speechOn, setSpeechOn] = useState(true);
  const [micBlocked, setMicBlocked] = useState(false);
  const [dictating, setDictating] = useState(false);
  const [draft, setDraft] = useState<string | null>(null);
  const [showStarters, setShowStarters] = useState(true);
  const [typed, setTyped] = useState("");
  // توضيح معالجة الصوت يظهر قبل أول استخدام للميكروفون، ثم يُختصر لإفساح مكان للمحادثة.
  const [voiceUsed, setVoiceUsed] = useState(false);
  const [canListen] = useState(() => recognitionCtor() !== null);
  const listening = useRef<Listening | null>(null);
  const speaking = useRef<Speaking | null>(null);
  const alive = useRef(true);
  const nextId = useRef(1);
  const awaitingPath = useRef<{path: string; text: string} | null>(null);
  const lastPath = useRef(pathname);
  const title = useRef<HTMLHeadingElement>(null);
  const logEnd = useRef<HTMLDivElement>(null);
  const speechOnRef = useRef(speechOn); speechOnRef.current = speechOn;
  const voiceRef = useRef(voice); voiceRef.current = voice;

  const stopAudio = useCallback(() => {
    listening.current?.abort(); listening.current = null;
    speaking.current?.cancel(); speaking.current = null;
    setInterim(""); setStatus("idle");
  }, []);

  /** إضافة رد معدّ إلى المحادثة، ونطقه إذا كان النطق مفعّلًا وصوت عربي متاحًا. لا يُنطق نص المستخدم أبدًا. */
  const speakText = useCallback((text: string) => {
    const v = voiceRef.current;
    if (!speechOnRef.current || !v) return;
    listening.current?.abort(); listening.current = null; // لا استماع أثناء النطق، حتى لا يسمع المساعد نفسه.
    speaking.current?.cancel();
    const s = speak(text, v);
    speaking.current = s; setStatus("speaking");
    void s.done.then(() => {if (alive.current && speaking.current === s) {speaking.current = null; setStatus("idle");}});
  }, []);
  const say = useCallback((text: string, extra: Omit<Entry, "id" | "from" | "text"> = {}, spoken?: string) => {
    if (!alive.current) return;
    setLog(l => [...l, {id: nextId.current++, from: "assistant" as const, text, ...extra}].slice(-MAX_ENTRIES));
    speakText(spoken ?? text);
  }, [speakText]);
  const addUser = useCallback((text: string, heard: boolean) => setLog(l => [...l, {id: nextId.current++, from: "user" as const, text, heard}].slice(-MAX_ENTRIES)), []);

  // الترحيب بعد ضغط المستخدم، ثم تحميل أصوات الجهاز. لا ميكروفون تلقائي.
  useEffect(() => {
    alive.current = true;
    title.current?.focus();
    let cancelled = false;
    setLog([{id: nextId.current++, from: "assistant", text: M.welcome}]);
    void loadVoices().then(voices => {
      if (cancelled) return;
      const v = typeof window !== "undefined" && "speechSynthesis" in window ? pickArabicVoice(voices) : null;
      setVoice(v); voiceRef.current = v;
      if (v) speakText(M.welcome); else say(M.noArabicVoice);
    });
    return () => {cancelled = true; alive.current = false; listening.current?.abort(); speaking.current?.cancel();};
  }, [say, speakText]);
  // إيقاف الصوت والميكروفون عند التنقل أو إخفاء الصفحة.
  useEffect(() => {
    if (pathname === lastPath.current) return;
    lastPath.current = pathname;
    stopAudio();
    const waiting = awaitingPath.current;
    if (waiting && waiting.path === pathname) {awaitingPath.current = null; say(waiting.text);}
  }, [pathname, stopAudio, say]);
  useEffect(() => {
    const hide = () => {if (document.visibilityState === "hidden") stopAudio();};
    // pagehide: مغادرة الصفحة أو تخزينها في ذاكرة الرجوع بالمتصفح.
    document.addEventListener("visibilitychange", hide); window.addEventListener("pagehide", stopAudio);
    return () => {document.removeEventListener("visibilitychange", hide); window.removeEventListener("pagehide", stopAudio);};
  }, [stopAudio]);
  useEffect(() => {logEnd.current?.scrollIntoView({block: "nearest"});}, [log, draft]);

  // ——— الإجراءات المسموح بها فقط ———
  const afterPending = useCallback((p: PendingAction, ok: boolean) => {
    if (p.type === "showImage" && alive.current) {say(ok ? M.imageShown : M.actionFailed, ok ? {actions: [{type: "pickImage", label: "اختر صورة"}]} : {}); return;}
    bridge.announce(!ok ? M.actionFailed : p.type === "focusQuote" ? M.quoteFocused : p.type === "useText" ? (p.review ? M.dictationSent : M.dictationPlaced) : M.imageShown);
  }, [bridge, say]);
  const goHomeThen = useCallback((p: PendingAction, keepOpen: boolean) => {
    bridge.setPending(p); bridge.onPendingDone.current = afterPending;
    stopAudio(); router.push("/");
    if (!keepOpen) onClose();
  }, [bridge, afterPending, stopAudio, router, onClose]);

  const focusQuote = useCallback(() => {
    const api = bridge.workbench();
    if (!api) {goHomeThen({type: "focusQuote"}, false); return;}
    if (api.isBusy()) {say(M.busy); return;}
    if (api.focusQuote()) {bridge.announce(M.quoteFocused); onClose();} else say(M.actionFailed);
  }, [bridge, goHomeThen, say, onClose]);
  const showImage = useCallback((answer?: Intent) => {
    const api = bridge.workbench();
    if (!api) {goHomeThen({type: "showImage"}, true); return;}
    if (api.showImageReader()) say(answer?.answer ?? M.imageShown, {actions: answer?.actions.length ? answer.actions : [{type: "pickImage", label: "اختر صورة"}]}, answer?.spoken);
    else say(M.actionFailed);
  }, [bridge, goHomeThen, say]);
  // تُستدعى داخل نقرة المستخدم نفسها؛ لذلك يفتح المتصفح منتقي الملفات.
  const pickImage = useCallback(() => {
    const api = bridge.workbench();
    if (!api) {showImage(); return;}
    if (api.isBusy()) {say(M.busy); return;}
    if (api.openImagePicker()) {bridge.announce(M.pickerOpened); onClose();} else say(M.actionFailed);
  }, [bridge, showImage, say, onClose]);
  const openPage = useCallback((path: AllowedPath, text: string = M.pageOpened) => {
    if (pathname === path) {say(M.pageAlready); return;}
    stopAudio(); awaitingPath.current = {path, text};
    router.push(path);
  }, [pathname, say, stopAudio, router]);
  const openTab = useCallback((tab: AssistantTab) => {
    const api = bridge.workbench();
    if (api?.hasSelection() && api.openTab(tab)) {bridge.announce(M.tabOpened); onClose(); return;}
    say(M.needResult, {actions: [REVIEW_ACTION]});
  }, [bridge, say, onClose]);
  // لا نستبدل نصًا كتبه الزائر في مربع الاقتباس إلا بعد موافقته الصريحة.
  const placeText = useCallback((review: boolean, confirmed?: string) => {
    const text = (confirmed ?? draft ?? "").trim();
    if (!text) {say(M.dictationEmpty); return;}
    const api = bridge.workbench();
    if (!api) {setDraft(null); goHomeThen({type: "useText", text, review}, false); return;}
    if (api.isBusy()) {say(M.busy); return;}
    const existing = api.currentQuote().trim();
    if (confirmed === undefined && existing && existing !== text) {say(M.replaceAsk, {replace: {text, review}}); return;}
    if (api.useText(text, review)) {setDraft(null); bridge.announce(review ? M.dictationSent : M.dictationPlaced); onClose();} else say(M.actionFailed);
  }, [draft, bridge, goHomeThen, say, onClose]);

  const runAction = (a: AssistantAction) => {
    if (a.type === "focusQuote") focusQuote();
    else if (a.type === "pickImage") pickImage();
    else if (a.type === "page") openPage(a.path);
    else openTab(a.tab);
  };
  const respond = useCallback((i: Intent) => {
    const run = i.run;
    if (!run) {say(i.answer, {actions: i.actions}, i.spoken); return;}
    if (run.type === "focusQuote") focusQuote();
    else if (run.type === "showImage") showImage(i);
    else if (run.type === "page") openPage(run.path, i.answer);
    else if (run.type === "openTab") openTab(run.tab);
    else if (run.type === "dictate") {
      if (!canListen || micBlocked) {say(M.voiceUnsupported, {actions: [REVIEW_ACTION]}); return;}
      setDictating(true); say(i.answer);
    }
  }, [say, focusQuote, showImage, openPage, openTab, canListen, micBlocked]);

  const handle = useCallback((raw: string, heard: boolean) => {
    const text = raw.trim().slice(0, 500);
    if (!text) return;
    // الإملاء للكلام المسموع فقط؛ ما يُكتب يعامل سؤالًا عاديًا. النص يظهر للتصحيح ولا يُنطق.
    if (dictating) {setDictating(false); if (heard) {setDraft(text); say(M.dictationReview); return;}}
    addUser(text, heard);
    setShowStarters(false);
    const m = matchRequest(text);
    if (m.kind === "intent") respond(m.intent);
    else if (m.kind === "clarify") say(m.reason === "compound" ? M.compound : M.clarify, {options: m.options});
    else if (m.kind === "negated") {say(M.negated); setShowStarters(true);}
    else if (m.kind === "out_of_scope") say(M.outOfScope, {actions: [REVIEW_ACTION]});
    else {say(M.unclear, {heardText: m.offerQuote ? text : undefined}); setShowStarters(true);}
  }, [dictating, addUser, respond, say]);
  const choose = (i: Intent) => {addUser(i.question, false); setShowStarters(false); respond(i);};

  async function toggleMic() {
    if (status === "listening") {listening.current?.stop(); return;}
    speaking.current?.cancel(); speaking.current = null; // لا نطق أثناء الاستماع.
    const l = listenOnce(text => {if (alive.current) setInterim(text);});
    if (!l) {say(M.voiceUnsupported); return;}
    listening.current = l; setStatus("listening"); setInterim(""); setVoiceUsed(true);
    const r = await l.result;
    if (!alive.current || listening.current !== l) return;
    listening.current = null; setStatus("idle"); setInterim("");
    if (r.ok) {handle(r.text, true); return;}
    if (r.error === "aborted") {setDictating(false); return;}
    if (r.error === "denied" || r.error === "language") setMicBlocked(true);
    setDictating(false);
    say(ERROR_TEXT[r.error]);
  }
  function toggleSpeech() {
    const next = !speechOn;
    setSpeechOn(next); speechOnRef.current = next;
    if (!next) {speaking.current?.cancel(); speaking.current = null; setStatus(s => s === "speaking" ? "idle" : s);}
  }

  const micUnavailable = !canListen || micBlocked;
  const statusText = status === "listening" ? (dictating ? `${M.listening} ${M.dictationStart}` : M.listening) : status === "speaking" ? M.speaking : "";
  return <section className="assistant-panel" role="dialog" aria-modal="false" aria-labelledby="assistant-title" onKeyDown={e => {if (e.key === "Escape") {e.stopPropagation(); onClose();}}}>
    <header className="assistant-head">
      <h2 id="assistant-title" ref={title} tabIndex={-1}>{M.title}</h2>
      <div className="assistant-head-actions">
        <button type="button" className="assistant-icon" onClick={toggleSpeech} aria-pressed={speechOn && !!voice} disabled={!voice} aria-label={M.speechToggle} title={voice ? M.speechToggle : M.noArabicVoice}>{speechOn && voice ? <Volume2 aria-hidden="true"/> : <VolumeX aria-hidden="true"/>}</button>
        <button type="button" className="assistant-icon" onClick={onClose} aria-label={M.close}><X aria-hidden="true"/></button>
      </div>
    </header>
    <p className="assistant-notice">{M.notice}</p>
    <div className="assistant-log" role="log" aria-live="polite" aria-relevant="additions" aria-label="المحادثة">
      {log.map(e => e.from === "user"
        ? <div key={e.id} className="assistant-msg from-user"><span className="assistant-who">{e.heard ? M.heard : M.you}</span><p>«{e.text}»</p></div>
        : <div key={e.id} className="assistant-msg"><p>{e.text}</p>
            {!!e.actions?.length && <div className="assistant-actions">{e.actions.map(a => <button key={a.label} type="button" className="outline-button" onClick={() => runAction(a)}>{a.label}</button>)}</div>}
            {!!e.options?.length && <div className="assistant-actions">{e.options.map(o => <button key={o.id} type="button" className="outline-button" onClick={() => choose(o)}>{o.question}</button>)}</div>}
            {e.replace && <div className="assistant-actions"><button type="button" className="outline-button" onClick={() => placeText(e.replace!.review, e.replace!.text)}>{M.replaceConfirm}</button><button type="button" className="outline-button" onClick={() => say(M.replaceKept)}>{M.replaceKeep}</button></div>}
            {e.heardText && <div className="assistant-actions"><button type="button" className="outline-button" onClick={() => setDraft(e.heardText!)}>{M.useHeard}</button></div>}
          </div>)}
      <div ref={logEnd}/>
    </div>
    {draft !== null && <div className="assistant-draft">
      <label htmlFor="assistant-draft">{M.dictationLabel}</label>
      <textarea id="assistant-draft" value={draft} onChange={e => setDraft(e.target.value)} maxLength={1000} spellCheck={false} rows={3}/>
      <div className="assistant-actions"><button type="button" className="outline-button" onClick={() => placeText(false)}>{M.placeQuote}</button><button type="button" className="button" onClick={() => placeText(true)}>{M.reviewQuote}</button><button type="button" className="text-button" onClick={() => setDraft(null)}>إلغاء</button></div>
    </div>}
    {showStarters && <div className="assistant-chips" role="group" aria-label={M.moreQuestions}>{starters.map(s => <button key={s.id} type="button" onClick={() => choose(s)}>{s.question}</button>)}</div>}
    <div className="assistant-controls">
      <p className="assistant-status" role="status" aria-live="polite">{statusText}{status === "listening" && interim && <span className="assistant-interim"> «{interim}»</span>}</p>
      <div className="assistant-row">
        <button type="button" className={`button assistant-mic${status === "listening" ? " is-listening" : ""}`} onClick={() => void toggleMic()} disabled={micUnavailable} aria-pressed={status === "listening"}>{status === "listening" ? <><Square aria-hidden="true" size={18}/>{M.stopListening}</> : <><Mic aria-hidden="true" size={20}/>{M.talk}</>}</button>
        {status === "speaking" && <button type="button" className="text-button" onClick={() => {speaking.current?.cancel(); speaking.current = null; setStatus("idle");}}>{M.stopSpeaking}</button>}
        <button type="button" className="text-button" onClick={() => setShowStarters(s => !s)} aria-expanded={showStarters}>{M.moreQuestions}</button>
      </div>
      <form className="assistant-form" onSubmit={e => {e.preventDefault(); const t = typed; setTyped(""); handle(t, false);}}>
        <label htmlFor="assistant-input" className="assistant-sr">{M.typeLabel}</label>
        <input id="assistant-input" value={typed} onChange={e => setTyped(e.target.value)} placeholder={M.typePlaceholder} maxLength={300} autoComplete="off" enterKeyHint="send"/>
        <button type="submit" className="assistant-icon" aria-label={M.send} disabled={!typed.trim()}><Send aria-hidden="true"/></button>
      </form>
      {(micUnavailable || !voiceUsed) && <p className="assistant-privacy">{micUnavailable ? (canListen ? M.micDenied : M.voiceUnsupported) : M.voicePrivacy}</p>}
    </div>
  </section>;
}
