#!/usr/bin/env bash
# Build the ultra-compressed (XZ -9e) first-run runtime pack and its checksum.
# The app downloads this from GitHub Releases on first launch and expands it
# with TarCompressorUtils (XZ / ZSTD aware).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${PIXEL9A_PAYLOAD_DIR:-/tmp/pixel9a-payload}
OUT="$ROOT/dist"
NAME=${PIXEL9A_PACK_NAME:-pixel9a-runtime-v1.tar.xz}
cd "$ROOT"
mkdir -p "$OUT"

test -d "$STAGE" || { echo "missing payload stage: $STAGE" >&2; exit 1; }

# Recompress the bundled .tzst assets with ZSTD level 19 (higher than the
# upstream default level 3) before packaging; those stay inside the APK.
if command -v zstd >/dev/null 2>&1; then
  for f in "$STAGE"/*.tzst app/src/main/assets/*.tzst; do
    [ -f "$f" ] || continue
    before=$(stat -c %s "$f")
    if zstd -d -q -f -c "$f" | zstd -19 -q -f -o "$f.new"; then
      after=$(stat -c %s "$f.new")
      if [ "$after" -lt "$before" ]; then mv "$f.new" "$f"; else rm -f "$f.new"; fi
    else
      rm -f "$f.new"
    fi
  done
fi

tar -C "$STAGE" --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime='2020-01-01 00:00:00' -cf - . \
  | xz -9e -T0 -c > "$OUT/$NAME"

sha256sum "$OUT/$NAME" | cut -d' ' -f1 > "$OUT/$NAME.sha256"
echo "runtime pack: $OUT/$NAME ($(stat -c %s "$OUT/$NAME") bytes), sha256=$(cat "$OUT/$NAME.sha256")"
