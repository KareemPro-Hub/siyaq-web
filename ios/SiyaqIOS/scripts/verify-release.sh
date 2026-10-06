#!/bin/bash
# أمر التحقق الموحد لسِياق iOS — يُشغَّل على ماك فيه Xcode، من أي مكان:
#   bash SiyaqIOS/scripts/verify-release.sh                 كل الفحوص
#   bash SiyaqIOS/scripts/verify-release.sh --no-ui-tests   دون اختبارات الواجهة
#   bash SiyaqIOS/scripts/verify-release.sh --static-only   الفحوص الثابتة فقط (لا يحتاج Xcode)
#   SIYAQ_DESTINATION='platform=iOS Simulator,name=iPhone 17' bash ...   لاختيار محاكٍ بعينه
#
# ما يفعله: فحص مراجع المشروع وإعدادات Release وملف Info لكل إعداد (Info.Release.plist المستقل إن وُجد)
# وأن كل خط مسجل في UIAppFonts موجود فعلًا في حزمة ذلك الإعداد، بحث عن أسرار في المصدر،
# بناء Debug واختبارات الوحدة والواجهة على المحاكي، بناء Release لجهاز عام دون توقيع،
# ثم فحص حزمة Release: لا خط حرير، لا خط مسجل غير موجود، لا تهيئة اختبارات، لا أسرار، لا NSAllowsArbitraryLoads.
# ما لا يفعله: لا يعدّل ملفات المشروع، لا يوقّع ولا يرفع ولا ينشر، لا يثبّت أدوات، لا يتصل بخدمة سِياق
# ولا بمزود ذكاء اصطناعي، ولا يطبع قيمة أي سر (اسم الملف ونوع النمط فقط).
# كل نواتج البناء والسجلات في مجلد مؤقت خارج المشروع يُطبع مساره في النهاية.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/SiyaqIOS.xcodeproj"
HELPER="$ROOT/scripts/siyaq_verify.py"
SCHEME="Siyaq"

STATIC_ONLY=0
UI_TESTS=1
for arg in "$@"; do
  case "$arg" in
    --static-only) STATIC_ONLY=1 ;;
    --no-ui-tests) UI_TESTS=0 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "خيار غير معروف: $arg"; exit 2 ;;
  esac
done

WORK="${SIYAQ_VERIFY_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/siyaq-verify.XXXXXX")}"
mkdir -p "$WORK"
RESULTS=()
FAILURES=0

record() { # $1 = الحالة (نجح/فشل/تخطٍّ)، $2 = الوصف
  RESULTS+=("$1 — $2")
  [ "$1" = "فشل" ] && FAILURES=$((FAILURES + 1))
  return 0
}

run_step() { # $1 = الوصف، $2 = ملف السجل، والباقي = الأمر
  local title="$1" log="$2"; shift 2
  echo "▶ $title"
  if "$@" >"$log" 2>&1; then
    record "نجح" "$title"
  else
    record "فشل" "$title (السجل: $log)"
    grep -E "error:|\*\* .* FAILED \*\*|Failing tests|failed \(" "$log" | head -20
  fi
  grep -E "Executed [0-9]+ tests?, with" "$log" | tail -1
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 غير متاح؛ الفحوص الثابتة تحتاجه (يأتي مع أدوات Xcode). لن يُثبَّت شيء تلقائيًا."
  exit 1
fi

echo "مجلد العمل المؤقت: $WORK"
echo

# ١. الفحوص الثابتة
if python3 "$HELPER" static "$ROOT"; then record "نجح" "مراجع المشروع وإعدادات Release"; else record "فشل" "مراجع المشروع وإعدادات Release"; fi
if python3 "$HELPER" secrets "$ROOT/Siyaq" "$ROOT/SiyaqTests" "$ROOT/SiyaqUITests" "$PROJECT"; then
  record "نجح" "لا أسرار في المصدر"
else
  record "فشل" "أسرار محتملة في المصدر"
fi
echo

if [ "$STATIC_ONLY" = 0 ]; then
  if ! command -v xcodebuild >/dev/null 2>&1; then
    record "فشل" "xcodebuild غير متاح — البناء والاختبارات لم تُشغَّل"
  else
    xcodebuild -version | head -1

    DEST="${SIYAQ_DESTINATION:-$(python3 "$HELPER" pick-simulator 2>/dev/null)}"
    if [ -z "$DEST" ]; then
      record "فشل" "لا يوجد محاكي آيفون متاح (اضبط SIYAQ_DESTINATION)"
    else
      echo "المحاكي: $DEST"
      DD="${SIYAQ_DEBUG_DERIVED_DATA:-$WORK/DerivedData-Debug}"
      run_step "بناء Debug للاختبار" "$WORK/1-build-debug.log" \
        xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" -configuration Debug CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
        -destination "$DEST" -derivedDataPath "$DD"
      run_step "اختبارات الوحدة" "$WORK/2-unit-tests.log" \
        xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" -configuration Debug CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
        -destination "$DEST" -derivedDataPath "$DD" -only-testing:SiyaqTests -parallel-testing-enabled NO -collect-test-diagnostics never \
        -resultBundlePath "$WORK/unit.xcresult"
      if [ "$UI_TESTS" = 1 ]; then
        run_step "اختبارات الواجهة" "$WORK/3-ui-tests.log" \
          xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" -configuration Debug CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
          -destination "$DEST" -derivedDataPath "$DD" -only-testing:SiyaqUITests -parallel-testing-enabled NO -collect-test-diagnostics never \
          -resultBundlePath "$WORK/ui.xcresult"
      else
        record "تخطٍّ" "اختبارات الواجهة (--no-ui-tests)"
      fi
    fi

    DR="${SIYAQ_RELEASE_DERIVED_DATA:-$WORK/DerivedData-Release}"
    run_step "بناء Release لجهاز iOS عام دون توقيع" "$WORK/4-build-release.log" \
      xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
      -destination "generic/platform=iOS" -derivedDataPath "$DR" CODE_SIGNING_ALLOWED=NO

    APP="$DR/Build/Products/Release-iphoneos/Siyaq.app"
    if [ -d "$APP" ]; then
      if python3 "$HELPER" app "$APP"; then record "نجح" "حزمة Release نظيفة"; else record "فشل" "حزمة Release"; fi
    else
      record "فشل" "حزمة Release غير موجودة بعد البناء"
    fi
  fi
else
  record "تخطٍّ" "البناء والاختبارات (--static-only)"
fi

echo
echo "الخلاصة:"
for line in "${RESULTS[@]}"; do echo "  $line"; done
echo "السجلات والنواتج: $WORK"
if [ "$FAILURES" -gt 0 ]; then
  echo "النتيجة: فشل ($FAILURES)"
  exit 1
fi
echo "النتيجة: كل الفحوص المطلوبة نجحت"
exit 0
