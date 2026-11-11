#!/usr/bin/env bash
# Restore the prebuilt ARM64 native libraries from the pinned base commit.
# They are intentionally NOT kept in the working tree (workspace budget), but the
# build still needs the small set of APK-resident executables. All other .so files
# are shipped as an external runtime pack downloaded on first launch.
set -euo pipefail
BASE_COMMIT=97e48a2a765c7a76095c32c73c14c16d4869ce8c
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [ -d app/src/main/jniLibs/arm64-v8a ] && [ "$(find app/src/main/jniLibs/arm64-v8a -name '*.so' | wc -l)" -gt 5 ]; then
  echo "jniLibs already present; nothing to restore"
  exit 0
fi
for path in $(git ls-tree -r --name-only "$BASE_COMMIT" -- app/src/main/jniLibs/arm64-v8a app/src/modern/jniLibs/arm64-v8a); do
  mkdir -p "$(dirname "$path")"
  git show "$BASE_COMMIT:$path" > "$path"
done
echo "restored $(find app/src/main/jniLibs/arm64-v8a app/src/modern/jniLibs/arm64-v8a -name '*.so' | wc -l) libraries from $BASE_COMMIT"
