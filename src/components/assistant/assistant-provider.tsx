"use client";
// يربط مساعد سِياق بمكونات الصفحة عبر إجراءات React صريحة، دون نقرات على عناصر DOM.
// الزر الصغير وحده يُحمَّل مع الصفحة؛ لوحة المساعد وردوده وموارد الصوت تُحمَّل عند الضغط فقط.
import dynamic from "next/dynamic";
import {createContext, useCallback, useContext, useEffect, useMemo, useRef, useState} from "react";
import {AudioLines} from "lucide-react";
import {ASSISTANT_ENABLED} from "@/lib/assistant/config";
import type {AssistantTab} from "@/lib/assistant/intents";

/** ما تتيحه صفحة المراجعة للمساعد. كل دالة تُرجع true فقط إذا نُفّذ الإجراء فعلًا. */
export type WorkbenchApi = {
  focusQuote(): boolean;
  showImageReader(): boolean;
  /** يجب استدعاؤها داخل نقرة المستخدم نفسها؛ المتصفح يمنع فتح منتقي الملفات من نتيجة صوتية. */
  openImagePicker(): boolean;
  openTab(tab: AssistantTab): boolean;
  hasSelection(): boolean;
  isBusy(): boolean;
  /** يضع نصًا أكّده المستخدم في مربع الاقتباس، ويبدأ المراجعة مرة واحدة إذا طُلب ذلك. */
  useText(text: string, review: boolean): boolean;
  /** النص الحالي في مربع الاقتباس؛ للتحقق قبل أي استبدال. */
  currentQuote(): string;
};
export type PendingAction = {type: "focusQuote"} | {type: "showImage"} | {type: "useText"; text: string; review: boolean};

type Bridge = {
  workbench: () => WorkbenchApi | null;
  register: (api: WorkbenchApi) => () => void;
  setPending: (p: PendingAction | null) => void;
  /** تُستدعى عند تنفيذ إجراء مؤجل بعد الانتقال إلى الرئيسية. */
  onPendingDone: React.RefObject<((p: PendingAction, ok: boolean) => void) | null>;
  announce: (text: string) => void;
  close: () => void;
};
const Ctx = createContext<Bridge | null>(null);
export const useAssistantBridge = () => useContext(Ctx);

const AssistantPanel = dynamic(() => import("./assistant-panel").then(m => m.AssistantPanel), {ssr: false, loading: () => <div className="assistant-panel assistant-loading" role="status" aria-label="نجهّز المساعد"/>});

export function AssistantProvider({children, label}: {children: React.ReactNode; label: string}) {
  const api = useRef<WorkbenchApi | null>(null);
  const pending = useRef<PendingAction | null>(null);
  const onPendingDone = useRef<((p: PendingAction, ok: boolean) => void) | null>(null);
  const launcher = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [toast, setToast] = useState("");
  const [typing, setTyping] = useState(false);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const announce = useCallback((text: string) => {
    clearTimeout(toastTimer.current); setToast(text);
    toastTimer.current = setTimeout(() => setToast(""), 6000);
  }, []);
  useEffect(() => () => clearTimeout(toastTimer.current), []);
  const close = useCallback(() => {setOpen(false); requestAnimationFrame(() => {if (!document.activeElement || document.activeElement === document.body) launcher.current?.focus();});}, []);
  const register = useCallback((next: WorkbenchApi) => {
    api.current = next;
    const p = pending.current;
    if (p) {
      pending.current = null;
      requestAnimationFrame(() => {
        const ok = p.type === "focusQuote" ? next.focusQuote() : p.type === "showImage" ? next.showImageReader() : next.useText(p.text, p.review);
        onPendingDone.current?.(p, ok);
      });
    }
    return () => {if (api.current === next) api.current = null;};
  }, []);
  // على الشاشات الصغيرة يختفي الزر أثناء الكتابة حتى لا يغطي لوحة المفاتيح أو مربع البحث.
  useEffect(() => {
    const field = (t: EventTarget | null) => t instanceof HTMLElement && (t.tagName === "TEXTAREA" || (t.tagName === "INPUT" && (t as HTMLInputElement).type !== "file") || t.isContentEditable) && !t.closest(".assistant-panel");
    const on = (e: FocusEvent) => setTyping(field(e.target));
    const off = () => setTyping(false);
    document.addEventListener("focusin", on); document.addEventListener("focusout", off);
    return () => {document.removeEventListener("focusin", on); document.removeEventListener("focusout", off);};
  }, []);
  const bridge = useMemo<Bridge>(() => ({workbench: () => api.current, register, setPending: p => {pending.current = p;}, onPendingDone, announce, close}), [register, announce, close]);
  return <Ctx.Provider value={bridge}>
    {children}
    {ASSISTANT_ENABLED && <>
      {!open && <button ref={launcher} type="button" className="assistant-launcher" data-typing={typing || undefined} onClick={() => {setToast(""); setOpen(true);}} aria-haspopup="dialog"><AudioLines aria-hidden="true" size={22}/><span>{label}</span></button>}
      {!open && toast && <p className="assistant-toast" role="status">{toast}</p>}
      {open && <AssistantPanel onClose={close}/>}
    </>}
  </Ctx.Provider>;
}

/** تسجيل صفحة المراجعة لدى المساعد. يُستدعى من QuoteWorkbench فقط. */
export function useWorkbenchBridge(make: () => WorkbenchApi) {
  const bridge = useAssistantBridge();
  const latest = useRef(make);
  latest.current = make;
  useEffect(() => {
    if (!bridge) return;
    // الدوال تقرأ أحدث الحالة عند الاستدعاء، فلا نعيد التسجيل مع كل تغيير.
    const proxy: WorkbenchApi = {
      focusQuote: () => latest.current().focusQuote(), showImageReader: () => latest.current().showImageReader(),
      openImagePicker: () => latest.current().openImagePicker(), openTab: t => latest.current().openTab(t),
      hasSelection: () => latest.current().hasSelection(), isBusy: () => latest.current().isBusy(),
      useText: (t, r) => latest.current().useText(t, r), currentQuote: () => latest.current().currentQuote(),
    };
    return bridge.register(proxy);
  }, [bridge]);
}
