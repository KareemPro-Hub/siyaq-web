import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createMatcher } from "./matcher";
import type { Tafsir, Verse } from "./types";
const data = (name: string) => JSON.parse(readFileSync(join(process.cwd(), "data", name), "utf8"));
const verses = data("quran.json") as Verse[];
const tafsir = data("tafsir.json") as Record<string, Tafsir[]>;
export const provenance = data("provenance.json") as {version: string; verses: number; surahs: number; tafsir_ayahs: number; books: {id: number; name: string; author: string; ayahs: number}[]};
const fullProvenance = data("provenance.json") as {version: string; files: {dataset: string; license_version: string}[]; books: {id: number; name: string; author: string}[]};
const datasetVersion = (dataset: string) => fullProvenance.files.find(f => f.dataset === dataset)?.license_version ?? "";
/** المصادر ونسخها الحقيقية من سجل الاستيراد: نسخة المصحف، ونسخة بيانات كل كتاب تفسير محمّل. */
export const reviewSources = {
  quran: {name: "الموسوعة القرآنية", version: datasetVersion("mushafs-1") || provenance.version},
  tafsir: fullProvenance.books.map(b => ({bookId: b.id, name: b.name, author: b.author, version: datasetVersion(`tafsir-book-${b.id}`)})),
};
export const reviewQuote = createMatcher(verses, tafsir, provenance.version, reviewSources);
export const sourcePolicy = data("source-policy.json") as {tafsir_books:{bookId:number;aiEligible:boolean;edition:string;attributionNote?:string;aiExclusionReason?:string;metadataURL:string}[]};
