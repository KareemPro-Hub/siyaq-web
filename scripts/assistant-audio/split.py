# يقسّم ملفات التوليد المجمّعة إلى رد لكل ملف: يختار فواصل «<long pause>» من بين فترات الصمت
# بمطابقة مدة كل مقطع مع طول نصه، ثم يقص الصمت الزائد ويصدّر MP3.
import json, math, re, subprocess, sys, itertools, os
src, out = sys.argv[1], sys.argv[2]
here = os.path.dirname(__file__)
spoken = json.load(open(f"{here}/spoken.json")); batches = json.load(open(f"{here}/batches.json"))
os.makedirs(out, exist_ok=True)
def silences(f, d=0.3):
    err = subprocess.run(["ffmpeg","-hide_banner","-i",f,"-af",f"silencedetect=noise=-40dB:d={d}","-f","null","-"],capture_output=True,text=True).stderr
    s=[float(x) for x in re.findall(r"silence_start: ([\d.]+)",err)]; e=[float(x) for x in re.findall(r"silence_end: ([\d.]+)",err)]
    dur=float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",f],capture_output=True,text=True).stdout)
    return list(zip(s,e)), dur
def fname(k): return ("intent-" if k.startswith("I.") else "msg-")+k[2:]
report=[]
for bi,keys in enumerate(batches,1):
    f=f"{src}/batch{bi}.wav"; sil,dur=silences(f)
    # حدود الكلام الفعلي
    start = sil[0][1] if sil and sil[0][0] < 0.05 else 0.0
    end = sil[-1][0] if sil and sil[-1][1] > dur-0.05 else dur
    inner=[x for x in sil if x[0]>start+0.1 and x[1]<end-0.1]
    n=len(keys); chars=[len(spoken[k]) for k in keys]; best=None
    for combo in itertools.combinations(range(len(inner)), n-1):
        cuts=[inner[i] for i in combo]; bounds=[start]+[c for x in cuts for c in x]+[end]
        segs=[(bounds[2*i],bounds[2*i+1]) for i in range(n)]
        speech=[b-a for a,b in segs]; r=sum(speech)/sum(chars)
        fit=sum(math.log(s/(c*r))**2 for s,c in zip(speech,chars) if s>0)
        gap=sum(math.log(b-a) for a,b in cuts)
        score=fit-0.6*gap
        if best is None or score<best[0]: best=(score,segs,cuts,fit)
    score,segs,cuts,fit=best
    for k,(a,b),c in zip(keys,segs,chars):
        a=max(0,a-0.12); b=min(dur,b+0.25)
        o=f"{out}/{fname(k)}.mp3"
        subprocess.run(["ffmpeg","-v","error","-y","-i",f,"-af",f"atrim=start={a:.3f}:end={b:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.04,areverse,afade=t=in:d=0.08,areverse,loudnorm=I=-16:TP=-1.5:LRA=11","-ar","24000","-ac","1","-c:a","libmp3lame","-b:a","64k",o],check=True)
        report.append({"batch":bi,"key":k,"file":os.path.basename(o),"sec":round(b-a,2),"chars":c,"s_per_char":round((b-a)/c,3)})
    print(f"batch{bi}: fit={fit:.3f} cuts={[round(b-a,2) for a,b in cuts]} unused={[round(b-a,2) for a,b in inner if (a,b) not in cuts and b-a>0.9]}")
json.dump(report,open(f"{out}/report.json","w"),ensure_ascii=False,indent=1)
for r in report: print(r["key"],r["sec"],r["chars"],r["s_per_char"])
