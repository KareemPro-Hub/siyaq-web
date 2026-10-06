#!/usr/bin/env python3
"""فحوص سِياق الثابتة وفحص حزمة Release — مكتبة Python القياسية فقط، لا تكتب في المشروع.

الاستخدام:
  siyaq_verify.py static  <SiyaqIOS>      مراجع المشروع، إعدادات Release، Info.plist، ملف الخصوصية
  siyaq_verify.py secrets <dir>...        بحث عن أسرار (يطبع اسم الملف ونوع النمط فقط، لا القيمة)
  siyaq_verify.py app     <Siyaq.app>     حزمة Release: لا خط حرير، لا تهيئة اختبارات، لا أسرار، ATS
  siyaq_verify.py pick-simulator          أول آيفون متاح في المحاكي (للأمر الموحد)
رمز الخروج: 0 = كل الفحوص نجحت، 1 = فشل فحص واحد على الأقل، 2 = خطأ في الاستخدام.
"""
import json
import os
import plistlib
import re
import subprocess
import sys

FAILED = False


def ok(msg):
    print(f"  ✓ {msg}")


def fail(msg):
    global FAILED
    FAILED = True
    print(f"  ✗ {msg}")


def info(msg):
    print(f"  • {msg}")


# ---------------------------------------------------------------- pbxproj (OpenStep plist)

class _Parser:
    _bare = re.compile(r"[A-Za-z0-9_$/:.\-+]+")

    def __init__(self, text):
        self.s, self.i = text, 0

    def _skip(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c.isspace():
                self.i += 1
            elif s.startswith("//", self.i):
                j = s.find("\n", self.i)
                self.i = len(s) if j < 0 else j + 1
            elif s.startswith("/*", self.i):
                j = s.find("*/", self.i + 2)
                if j < 0:
                    raise ValueError("تعليق غير مغلق")
                self.i = j + 2
            else:
                return

    def _expect(self, ch):
        self._skip()
        if self.s[self.i:self.i + 1] != ch:
            raise ValueError(f"متوقع '{ch}' عند {self.i}")
        self.i += 1

    def value(self):
        self._skip()
        c = self.s[self.i:self.i + 1]
        if c == "{":
            self.i += 1
            out = {}
            while True:
                self._skip()
                if self.s[self.i:self.i + 1] == "}":
                    self.i += 1
                    return out
                key = self.value()
                self._expect("=")
                out[key] = self.value()
                self._expect(";")
        if c == "(":
            self.i += 1
            out = []
            while True:
                self._skip()
                if self.s[self.i:self.i + 1] == ")":
                    self.i += 1
                    return out
                out.append(self.value())
                self._skip()
                if self.s[self.i:self.i + 1] == ",":
                    self.i += 1
        if c == '"':
            self.i += 1
            buf = []
            esc = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
            while True:
                ch = self.s[self.i]
                if ch == "\\":
                    nxt = self.s[self.i + 1]
                    buf.append(esc.get(nxt, nxt))
                    self.i += 2
                elif ch == '"':
                    self.i += 1
                    return "".join(buf)
                else:
                    buf.append(ch)
                    self.i += 1
        m = self._bare.match(self.s, self.i)
        if not m:
            raise ValueError(f"قيمة غير مفهومة عند {self.i}")
        self.i = m.end()
        return m.group(0)


def load_pbxproj(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if text.startswith("// !$*UTF8*$!"):
        text = text.split("\n", 1)[1]
    parser = _Parser(text)
    root = parser.value()
    parser._skip()
    if parser.i != len(parser.s):
        raise ValueError(f"محتوى زائد بعد نهاية الملف عند {parser.i}")
    return root


# ---------------------------------------------------------------- static

def _file_paths(objects, root_id, project_dir):
    """يبني المسار الكامل لكل مرجع ملف عبر شجرة المجموعات."""
    paths = {}

    def walk(oid, base):
        obj = objects[oid]
        tree = obj.get("sourceTree", "<group>")
        p = obj.get("path")
        if tree == "<group>":
            here = os.path.join(base, p) if p else base
        elif tree == "SOURCE_ROOT":
            here = os.path.join(project_dir, p or "")
        else:
            here = None  # BUILT_PRODUCTS_DIR / SDKROOT: خارج المشروع
        if obj.get("isa") in ("PBXGroup", "PBXVariantGroup"):
            for child in obj.get("children", []):
                walk(child, here if here is not None else base)
        else:
            paths[oid] = here

    walk(root_id, project_dir)
    return paths


def _excluded(settings, filename):
    """هل يستثني EXCLUDED_SOURCE_FILE_NAMES هذا الملف (يدعم أنماط *)؟"""
    import fnmatch
    v = settings.get("EXCLUDED_SOURCE_FILE_NAMES", "")
    patterns = v if isinstance(v, list) else str(v).split()
    return any(fnmatch.fnmatch(filename, p) for p in patterns)


def _setting_has(settings, key, needle):
    v = settings.get(key, "")
    vals = v if isinstance(v, list) else str(v).split()
    return any(needle == x or x.startswith(needle + "=") for x in vals)


def cmd_static(root):
    project_dir = os.path.abspath(root)
    pbx = os.path.join(project_dir, "SiyaqIOS.xcodeproj", "project.pbxproj")
    print("مراجع المشروع وإعدادات Release:")
    try:
        data = load_pbxproj(pbx)
    except Exception as e:  # noqa: BLE001
        fail(f"تعذر تحليل project.pbxproj: {e}")
        return
    ok("project.pbxproj يُحلَّل بلا أخطاء")
    objects = data["objects"]
    proj = objects[data["rootObject"]]
    paths = _file_paths(objects, proj["mainGroup"], project_dir)

    missing = [os.path.relpath(p, project_dir) for oid, p in paths.items()
               if p and objects[oid].get("isa") == "PBXFileReference" and not os.path.exists(p)]
    if missing:
        fail("مراجع معلقة: " + "، ".join(sorted(missing)))
    else:
        ok(f"كل المراجع موجودة على القرص ({sum(1 for p in paths.values() if p)} مرجعًا)")

    targets = {objects[t]["name"]: objects[t] for t in proj["targets"]}
    expected_dirs = {"Siyaq": "Siyaq", "SiyaqTests": "SiyaqTests", "SiyaqUITests": "SiyaqUITests"}
    in_sources = {}
    for name, target in targets.items():
        for phase_id in target.get("buildPhases", []):
            phase = objects[phase_id]
            if phase.get("isa") != "PBXSourcesBuildPhase":
                continue
            for bf in phase.get("files", []):
                ref = objects.get(bf, {}).get("fileRef")
                if ref not in objects:
                    fail(f"{name}: ملف بناء يشير إلى مرجع غير موجود")
                    continue
                rel = os.path.relpath(paths.get(ref) or "", project_dir)
                in_sources.setdefault(rel, []).append(name)
                folder = expected_dirs.get(name)
                if folder and not rel.startswith(folder + os.sep):
                    fail(f"{name} يترجم ملفًا من خارج مجلده: {rel}")
    for name in expected_dirs:
        if name not in targets:
            fail(f"الهدف {name} غير موجود")
    dupes = [f for f, ts in in_sources.items() if len(ts) > 1]
    if dupes:
        fail("ملفات مترجمة في أكثر من هدف: " + "، ".join(sorted(dupes)))
    on_disk = []
    for folder in expected_dirs.values():
        for dirpath, _, files in os.walk(os.path.join(project_dir, folder)):
            on_disk += [os.path.relpath(os.path.join(dirpath, f), project_dir) for f in files if f.endswith(".swift")]
    orphans = sorted(set(on_disk) - set(in_sources))
    if orphans:
        fail("ملفات Swift خارج أي هدف: " + "، ".join(orphans))
    else:
        counts = {n: sum(1 for ts in in_sources.values() if n in ts) for n in expected_dirs}
        ok("كل ملفات Swift في هدفها الصحيح (" + "، ".join(f"{n}: {c}" for n, c in counts.items()) + ")")

    def configs(owner):
        lst = objects[owner["buildConfigurationList"]]
        return {objects[c]["name"]: objects[c].get("buildSettings", {}) for c in lst["buildConfigurations"]}

    app_cfg, proj_cfg = configs(targets["Siyaq"]), configs(proj)
    rel_app, rel_proj = app_cfg.get("Release", {}), proj_cfg.get("Release", {})
    if any(_setting_has(s, "SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG") or
           _setting_has(s, "GCC_PREPROCESSOR_DEFINITIONS", "DEBUG") for s in (rel_app, rel_proj)):
        fail("Release يعرّف DEBUG — تهيئة الاختبارات ستدخل الإصدار")
    else:
        ok("Release لا يعرّف DEBUG (تهيئة اختبارات الواجهة خارج الإصدار)")
    if all(_excluded(rel_app, f) for f in ("Harir-Regular.otf", "Harir-Bold.otf")):
        ok("Release يستثني ملفي خط حرير")
    else:
        fail("Release لا يستثني ملفي خط حرير (EXCLUDED_SOURCE_FILE_NAMES)")
    team = {str(s.get("DEVELOPMENT_TEAM", "")) for s in app_cfg.values()}
    info("فريق التوقيع " + ("فارغ (لا توقيع من هذا المشروع)" if team <= {""} else "مضبوط"))

    # موارد الحزمة (أسماء الملفات) — لفحص الخطوط المسجلة وعدم نسخ ملفات Info إلى الحزمة.
    resources = set()
    for phase_id in targets["Siyaq"].get("buildPhases", []):
        phase = objects[phase_id]
        if phase.get("isa") == "PBXResourcesBuildPhase":
            for bf in phase.get("files", []):
                ref = objects.get(bf, {}).get("fileRef")
                if ref in paths and paths[ref]:
                    resources.add(os.path.basename(paths[ref]))
    copied_info = sorted(r for r in resources if r.startswith("Info") and r.endswith(".plist"))
    if copied_info:
        fail("ملف Info يُنسخ كمورد داخل الحزمة: " + "، ".join(copied_info))

    for config_name in ("Debug", "Release"):
        settings = app_cfg.get(config_name, {})
        rel = settings.get("INFOPLIST_FILE") or proj_cfg.get(config_name, {}).get("INFOPLIST_FILE")
        if not rel:
            info(f"{config_name}: Info.plist مولّد تلقائيًا")
            continue
        for prefix in ("$(SRCROOT)/", "$(PROJECT_DIR)/", "${SRCROOT}/", "${PROJECT_DIR}/"):
            rel = str(rel).replace(prefix, "")
        plist_path = os.path.join(project_dir, str(rel))
        if not os.path.exists(plist_path):
            fail(f"{config_name}: ملف {rel} غير موجود")
            continue
        try:
            with open(plist_path, "rb") as f:
                plist = plistlib.load(f)
        except Exception:  # noqa: BLE001
            fail(f"{config_name}: تعذرت قراءة {rel}")
            continue
        label = f"{config_name} ({os.path.basename(str(rel))})"
        if plist.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads"):
            fail(f"{label}: يسمح بأي اتصال غير مشفر (NSAllowsArbitraryLoads)")
        else:
            ok(f"{label}: بلا NSAllowsArbitraryLoads")
        base = str(plist.get("SiyaqServiceBaseURL", ""))
        # العنوان يأتي من إعداد البناء SIYAQ_SERVICE_BASE_URL (لا خيار للمستخدم في الواجهة).
        m = re.fullmatch(r"\$[({](\w+)[)}]", base.strip())
        if m:
            base = str(settings.get(m.group(1), proj_cfg.get(config_name, {}).get(m.group(1), "")))
        if not base:
            fail(f"{label}: لا عنوان لخدمة سِياق في إعدادات البناء (SIYAQ_SERVICE_BASE_URL)")
        elif not base.startswith("https://"):
            fail(f"{label}: SiyaqServiceBaseURL ليس https")
        else:
            ok(f"{label}: عنوان الخدمة من إعدادات البناء وhttps")
        fonts = [str(x) for x in plist.get("UIAppFonts", [])]
        missing = [f for f in fonts if f not in resources or _excluded(settings, f)]
        if missing:
            fail(f"{label}: يسجّل خطوطًا لن تكون في الحزمة: " + "، ".join(missing))
        else:
            ok(f"{label}: كل خط مسجل موجود في الحزمة" + ("" if fonts else " (لا خطوط مسجلة)"))

    privacy = os.path.join(project_dir, "Siyaq", "Resources", "PrivacyInfo.xcprivacy")
    if os.path.exists(privacy):
        with open(privacy, "rb") as f:
            p = plistlib.load(f)
        if p.get("NSPrivacyTracking") is False:
            ok("PrivacyInfo.xcprivacy موجود ولا تتبع")
        else:
            fail("PrivacyInfo.xcprivacy: NSPrivacyTracking ليس false")
    else:
        fail("PrivacyInfo.xcprivacy غير موجود")


# ---------------------------------------------------------------- secrets

SECRET_PATTERNS = [
    ("مفتاح OpenAI/Anthropic", re.compile(rb"sk-(?:proj-|ant-)?[A-Za-z0-9_\-]{20,}")),
    ("اسم متغير مفتاح OpenAI", re.compile(rb"OPENAI" rb"_API_KEY")),
    ("مفتاح AWS", re.compile(rb"AKIA[0-9A-Z]{16}")),
    ("رمز GitHub", re.compile(rb"gh[pousr]_[A-Za-z0-9]{30,}")),
    ("رمز Slack", re.compile(rb"xox[abprs]-[A-Za-z0-9\-]{10,}")),
    ("مفتاح Google", re.compile(rb"AIza[0-9A-Za-z_\-]{35}")),
    ("مفتاح خاص", re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("سر مُسند حرفيًا", re.compile(
        rb"(?i)(?:api[_-]?key|secret|token|passw(?:or)?d)[\"']?\s*[:=]\s*[\"'][^\"'\s]{8,}[\"']")),
]
SECRET_FILES = (".p8", ".p12", ".pem", ".mobileprovision", ".cer", ".keystore", ".env")
SKIP_DIRS = {".git", "DerivedData", "build", ".build", "xcuserdata"}


def scan_secrets(paths, label):
    hits = []
    for top in paths:
        for dirpath, dirnames, files in os.walk(top):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for name in files:
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, top)
                if name.lower().endswith(SECRET_FILES) or name == ".env":
                    hits.append((rel, "ملف شهادة/مفتاح/بيئة"))
                    continue
                try:
                    with open(full, "rb") as f:
                        blob = f.read(64 * 1024 * 1024)
                except OSError:
                    continue
                for kind, rx in SECRET_PATTERNS:
                    if rx.search(blob):
                        hits.append((rel, kind))
    if hits:
        for rel, kind in sorted(set(hits)):
            fail(f"{label}: {rel} — {kind} (القيمة لا تُطبع)")
    else:
        ok(f"{label}: لا أسرار ولا ملفات مفاتيح")


def cmd_secrets(paths):
    print("البحث عن الأسرار:")
    scan_secrets(paths, "المصدر")


# ---------------------------------------------------------------- Release app bundle

TEST_MARKERS = [b"SIYAQ_UITEST", b"siyaq.uitest.", b"SiyaqUITests"]


def cmd_app(app):
    print(f"حزمة Release ({os.path.basename(app)}):")
    if not os.path.isdir(app):
        fail("الحزمة غير موجودة")
        return
    all_files = []
    for dirpath, _, files in os.walk(app):
        all_files += [os.path.join(dirpath, f) for f in files]
    fonts = [os.path.relpath(f, app) for f in all_files if os.path.basename(f).lower().startswith("harir")]
    fail("خط حرير داخل الحزمة: " + "، ".join(fonts)) if fonts else ok("لا ملفات خط حرير")
    xct = [os.path.relpath(f, app) for f in all_files if ".xctest" in f]
    fail("مكونات اختبار داخل الحزمة: " + "، ".join(xct)) if xct else ok("لا مكونات اختبار (.xctest)")
    found = set()
    for f in all_files:
        try:
            with open(f, "rb") as fh:
                blob = fh.read()
        except OSError:
            continue
        for m in TEST_MARKERS:
            if m in blob:
                found.add((os.path.relpath(f, app), m.decode()))
    if found:
        for rel, m in sorted(found):
            fail(f"نص تهيئة اختبارات في {rel}: {m}")
    else:
        ok("لا نصوص تهيئة اختبارات الواجهة في أي ملف")
    plist_path = os.path.join(app, "Info.plist")
    try:
        with open(plist_path, "rb") as f:
            plist = plistlib.load(f)
        if plist.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads"):
            fail("Info.plist في الحزمة يسمح بأي اتصال غير مشفر")
        else:
            ok("Info.plist في الحزمة بلا NSAllowsArbitraryLoads")
        names = {os.path.basename(f) for f in all_files}
        missing = [str(x) for x in plist.get("UIAppFonts", []) if os.path.basename(str(x)) not in names]
        if missing:
            fail("Info.plist في الحزمة يسجّل خطوطًا غير موجودة: " + "، ".join(missing))
        else:
            ok("كل خط مسجل في Info.plist موجود في الحزمة")
    except (OSError, plistlib.InvalidFileException):
        fail("تعذرت قراءة Info.plist في الحزمة")
    extra_info = [os.path.relpath(f, app) for f in all_files
                  if os.path.basename(f).startswith("Info") and f.endswith(".plist") and os.path.dirname(f) != app.rstrip("/")]
    extra_info += [os.path.relpath(f, app) for f in all_files if os.path.basename(f) == "Info.Release.plist"]
    if extra_info:
        fail("ملفات Info إضافية داخل الحزمة: " + "، ".join(sorted(set(extra_info))))
    scan_secrets([app], "الحزمة")


# ---------------------------------------------------------------- simulator

def cmd_pick_simulator():
    out = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                         capture_output=True, text=True, check=True).stdout
    devices = json.loads(out).get("devices", {})

    def version(runtime):
        m = re.search(r"iOS-(\d+)-(\d+)", runtime)
        return (int(m.group(1)), int(m.group(2))) if m else (0, 0)

    for runtime in sorted(devices, key=version, reverse=True):
        if "iOS" not in runtime:
            continue
        for d in devices[runtime]:
            if d.get("name", "").startswith("iPhone") and d.get("isAvailable", True):
                print(f"platform=iOS Simulator,id={d['udid']}")
                return 0
    return 1


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, args = argv[1], argv[2:]
    if cmd == "static" and len(args) == 1:
        cmd_static(args[0])
    elif cmd == "secrets" and args:
        cmd_secrets(args)
    elif cmd == "app" and len(args) == 1:
        cmd_app(args[0])
    elif cmd == "pick-simulator":
        return cmd_pick_simulator()
    else:
        print(__doc__)
        return 2
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
