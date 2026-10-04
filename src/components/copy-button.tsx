"use client";
import { Check, Copy } from "lucide-react";
import { useEffect, useRef, useState } from "react";
export function CopyButton({text, label, plain = false}: {text: string; label: string; plain?: boolean}) {
  const [state, setState] = useState<"ready" | "done" | "error">("ready");
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  async function copy() {
    clearTimeout(timer.current);
    try {await navigator.clipboard.writeText(text); setState("done");} catch {setState("error");}
    timer.current = setTimeout(() => setState("ready"), 2400);
  }
  return <button type="button" onClick={copy} className={plain ? "text-button" : "outline-button"} aria-label={label}><span aria-live="polite">{state === "done" ? "تم النسخ" : state === "error" ? "تعذر النسخ" : label}</span>{state === "done" ? <Check size={18} strokeWidth={1.7} aria-hidden="true" /> : <Copy size={18} strokeWidth={1.7} aria-hidden="true" />}</button>;
}
