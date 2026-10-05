# يقسّم ملفات التوليد المجمّعة إلى ملف لكل رد: يختار فواصل «<long pause>» من بين فترات الصمت
# بمطابقة مدة كل مقطع مع طول نصه، ثم يقص الأطراف ويوحّد الارتفاع ويصدّر MP3.
# الاستخدام: python3 split.py <مجلد batch*.wav> <مجلد الإخراج> [plan.json]
import json, math, re, subprocess, sys, itertools, os
src, out = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
plan = json.load(open(sys.argv[3] if len(sys.argv) > 3 else f"{here}/plan.json", encoding="utf-8"))
texts = {}
for name in ("spoken.json", "numbers.json"):
    texts.update(json.load(open(f"{here}/{name}", encoding="utf-8")))
os.makedirs(out, exist_ok=True)
def silences(f, d=0.3):
    err = subprocess.run(["ffmpeg","-hide_banner","-i",f,"-af",f"silencedetect=noise=-40dB:d={d}","-f","null","-"],capture_output=True,text=True).stderr
    s=[float(x) for x in re.findall(r"silence_start: ([\d.]+)",err)]; e=[float(x) for x in re.findall(r"silence_end: ([\d.]+)",err)]
    dur=float(re.findall(r"time=(\d+):(\d+):([\d.]+)",err)[-1][2]) + 60*int(re.findall(r"time=(\d+):(\d+):([\d.]+)",err)[-1][1])
    return list(zip(s,e)), dur

MAX_GAP, KEEP_GAP, TARGET = 0.9, 0.7, -16.0
def polish(f, a, z, o):
    """قص المقطع، وتقصير أي صمت داخلي أطول من MAX_GAP إلى KEEP_GAP، ثم توحيد الارتفاع على TARGET LUFS بمرحلتين."""
    tmp = o + ".wav"
    subprocess.run(["ffmpeg","-v","error","-y","-i",f,"-af",f"atrim=start={a:.3f}:end={z:.3f},asetpts=PTS-STARTPTS","-ac","1",tmp],check=True)
    sil,dur = silences(tmp, MAX_GAP)
    keep=[]; t=0.0
    for x,y in sil:
        if x < 0.05 or y > dur-0.05: continue
        cut_a = x + KEEP_GAP/2; cut_b = y - KEEP_GAP/2
        keep.append((t, cut_a)); t = cut_b
    keep.append((t, dur))
    parts="".join(f"[0:a]atrim=start={p:.3f}:end={q:.3f},asetpts=PTS-STARTPTS[s{i}];" for i,(p,q) in enumerate(keep))
    graph=parts+"".join(f"[s{i}]" for i in range(len(keep)))+f"concat=n={len(keep)}:v=0:a=1,afade=t=in:d=0.04,areverse,afade=t=in:d=0.08,areverse[out]"
    tmp2 = o + ".2.wav"
    subprocess.run(["ffmpeg","-v","error","-y","-i",tmp,"-filter_complex",graph,"-map","[out]",tmp2],check=True)
    e=subprocess.run(["ffmpeg","-hide_banner","-i",tmp2,"-af","ebur128","-f","null","-"],capture_output=True,text=True).stderr
    gain = TARGET - float(re.findall(r"I:\s+(-?[\d.]+) LUFS",e)[-1])
    subprocess.run(["ffmpeg","-v","error","-y","-i",tmp2,"-af",f"volume={gain:.2f}dB,alimiter=limit=0.84:level=false","-ar","24000","-ac","1","-c:a","libmp3lame","-b:a","64k",o],check=True)
    os.remove(tmp); os.remove(tmp2)
def fname(k): return {"I.":"intent-","M.":"msg-","N.":"num-"}[k[:2]]+k[2:]
report=[]
for item in plan:
    f=f"{src}/{item['wav']}"; keys=item["keys"]; export=set(item.get("export", keys))
    sil,dur=silences(f)
    start = sil[0][1] if sil and sil[0][0] < 0.05 else 0.0
    end = sil[-1][0] if sil and sil[-1][1] > dur-0.05 else dur
    inner=[x for x in sil if x[0]>start+0.1 and x[1]<end-0.1]
    n=len(keys); chars=[len(texts[k]) for k in keys]
    if len(inner) > 26:  # كثيرة جدًا للتجربة الكاملة: أطول الفواصل فقط (للأرقام المتساوية الطول)
        cuts=sorted(sorted(inner,key=lambda x:x[1]-x[0])[-(n-1):])
    else:
        best=None
        for combo in itertools.combinations(range(len(inner)), n-1):
            c=[inner[i] for i in combo]; b=[start]+[t for x in c for t in x]+[end]
            sp=[b[2*i+1]-b[2*i] for i in range(n)]; r=sum(sp)/sum(chars)
            score=sum(math.log(s/(ch*r))**2 for s,ch in zip(sp,chars) if s>0)-0.6*sum(math.log(y-x) for x,y in c)
            if best is None or score<best[0]: best=(score,c)
        cuts=best[1]
    b=[start]+[t for x in cuts for t in x]+[end]
    segs=[(b[2*i],b[2*i+1]) for i in range(n)]
    print(f"{item['wav']}: cuts={[round(y-x,2) for x,y in cuts]}")
    for k,(a,z),c in zip(keys,segs,chars):
        if k not in export: continue
        a=max(0,a-0.12); z=min(dur,z+0.25)
        o=f"{out}/{fname(k)}.mp3"
        polish(f, a, z, o)
        report.append({"wav":item["wav"],"key":k,"file":os.path.basename(o),"sec":round(z-a,2),"chars":c,"s_per_char":round((z-a)/c,3)})
json.dump(report,open(f"{out}/report.json","w"),ensure_ascii=False,indent=1)
