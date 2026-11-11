#!/usr/bin/env bash
# Restore build inputs that are intentionally NOT stored in the working tree.
# The workspace budget (<100 MB incl. APK) means bulky binaries and assets live
# either in the pinned base commit or in a GitHub Release and are materialised
# only inside CI (or locally when a full build is wanted).
set -euo pipefail
BASE_COMMIT=${PIXEL9A_BASE_COMMIT:-97e48a2a765c7a76095c32c73c14c16d4869ce8c}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${PIXEL9A_PAYLOAD_DIR:-/tmp/pixel9a-payload}
cd "$ROOT"

# 1) ARM64 .so files needed to assemble the APK (the optional ones are dropped
#    again by packaging.jniLibs.excludes in app/build.gradle.kts).
if [ ! -d app/src/main/jniLibs/arm64-v8a ] || [ "$(find app/src/main/jniLibs/arm64-v8a -name '*.so' 2>/dev/null | wc -l)" -lt 5 ]; then
  for path in $(git ls-tree -r --name-only "$BASE_COMMIT" -- app/src/main/jniLibs/arm64-v8a app/src/modern/jniLibs/arm64-v8a); do
    mkdir -p "$(dirname "$path")"
    git cat-file blob "$BASE_COMMIT:$path" > "$path"
  done
  echo "restored $(find app/src/main/jniLibs/arm64-v8a app/src/modern/jniLibs/arm64-v8a -name '*.so' | wc -l) ARM64 libraries"
else
  echo "jniLibs already present"
fi

# 2) Assets externalized into the first-run runtime pack (staged OUTSIDE the repo
#    so aapt2 cannot put them back into the APK).
rm -rf "$STAGE"
mkdir -p "$STAGE/inputcontrols/icons"
for path in $(git ls-tree -r --name-only "$BASE_COMMIT" -- \
    app/src/main/assets/inputcontrols/icons \
    app/src/main/assets/arm64ec_input_dlls.tzst); do
  case "$path" in
    */inputcontrols/icons/*)
      git cat-file blob "$BASE_COMMIT:$path" > "$STAGE/inputcontrols/icons/$(basename "$path")" ;;
    */arm64ec_input_dlls.tzst)
      git cat-file blob "$BASE_COMMIT:$path" > "$STAGE/$(basename "$path")" ;;
  esac
done
echo "staged $(find "$STAGE" -type f | wc -l) externalized assets in $STAGE"
