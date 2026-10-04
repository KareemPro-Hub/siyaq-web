#!/bin/zsh
set -eu
cd "$(dirname "$0")"
if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
  print 'ثبّت Node.js 22 أو أحدث مع npm، ثم افتح الملف مرة أخرى.'
  exit 1
fi
if [[ ! -d node_modules ]]; then
  npm ci
fi
print 'سِياق: http://127.0.0.1:3000'
if [[ -f .next/BUILD_ID ]]; then
  exec npm run start
else
  exec npm run dev
fi
