#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# GameNative (Pixel 9a 専用ビルド) 用の最小ツールチェーンをまとめて取得する。
# 既定のインストール先は /tmp/toolchain （リポジトリを汚さないため）。
#
#   ./tools/setup-android-toolchain.sh              # JDK17 + SDK36 + build-tools
#   WITH_NDK=1 ./tools/setup-android-toolchain.sh   # NDK 27.3 も入れる (+1.5GB)
#
# 必要な外向き通信:
#   dl.google.com (Android SDK), repo.maven.apache.org (Adoptium/zig などは GitHub),
#   services.gradle.org (Gradle 本体), maven.google.com / repo1.maven.org (依存解決)
# ---------------------------------------------------------------------------
set -euo pipefail

PREFIX="${PREFIX:-/tmp/toolchain}"
SDK_DIR="$PREFIX/android-sdk"
GRADLE_HOME_DIR="$PREFIX/gradle-home"
JDK_DIR="$PREFIX/jdk17"

JDK_VERSION="${JDK_VERSION:-17.0.13+11}"
CMDLINE_VERSION="${CMDLINE_VERSION:-11076708}"
COMPILE_SDK="${COMPILE_SDK:-36}"
BUILD_TOOLS="${BUILD_TOOLS:-35.0.0}"
NDK_VERSION="${NDK_VERSION:-27.3.13750724}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

mkdir -p "$PREFIX" "$SDK_DIR/cmdline-tools" "$GRADLE_HOME_DIR"

# --- 1. JDK 17 (Temurin) ----------------------------------------------------
if [ ! -x "$JDK_DIR/bin/javac" ]; then
  log "JDK 17 ($JDK_VERSION) を取得"
  JDK_TAG="jdk-${JDK_VERSION/+/-}"        # 17.0.13+11 -> jdk-17.0.13-11
  JDK_FILE="OpenJDK17U-jdk_x64_linux_hotspot_${JDK_VERSION/+_}.tar.gz"
  url="https://github.com/adoptium/temurin17-binaries/releases/download/${JDK_TAG//-/+}/${JDK_FILE}"
  curl -fL --retry 3 -o "$PREFIX/jdk17.tar.gz" "$url"
  rm -rf "$JDK_DIR"; mkdir -p "$JDK_DIR"
  tar -xzf "$PREFIX/jdk17.tar.gz" -C "$JDK_DIR" --strip-components=1
  rm -f "$PREFIX/jdk17.tar.gz"
fi
export JAVA_HOME="$JDK_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
log "JDK: $(java -version 2>&1 | head -1)"

# --- 2. Android command line tools -----------------------------------------
SDKMANAGER="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  log "Android cmdline-tools ($CMDLINE_VERSION) を取得"
  curl -fL --retry 3 -o "$PREFIX/cmdline-tools.zip" \
    "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_VERSION}_latest.zip"
  rm -rf "$SDK_DIR/cmdline-tools/latest" "$PREFIX/cmdline-tools"
  unzip -q "$PREFIX/cmdline-tools.zip" -d "$PREFIX/cmdline-tools"
  mv "$PREFIX/cmdline-tools/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
  rm -rf "$PREFIX/cmdline-tools.zip" "$PREFIX/cmdline-tools"
fi
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"

# --- 3. プラットフォーム / build-tools (--- 最小構成) -----------------------
pkgs=( "platforms;android-$COMPILE_SDK" "build-tools;$BUILD_TOOLS" "platform-tools" )
[ "${WITH_NDK:-0}" = "1" ] && pkgs+=( "ndk;$NDK_VERSION" "cmake;3.22.1" )
log "SDK パッケージを導入: ${pkgs[*]}"
yes | "$SDKMANAGER" --sdk_root="$SDK_DIR" --licenses >/dev/null
yes | "$SDKMANAGER" --sdk_root="$SDK_DIR" "${pkgs[@]}" >/dev/null

# --- 4. プロジェクトへパスを伝える -----------------------------------------
cat > local.properties <<EOF
sdk.dir=$SDK_DIR
EOF
log "local.properties に sdk.dir=$SDK_DIR を書き込み"

cat > "$PREFIX/env.sh" <<EOF
export JAVA_HOME=$JDK_DIR
export ANDROID_HOME=$SDK_DIR
export ANDROID_SDK_ROOT=$SDK_DIR
export GRADLE_USER_HOME=$GRADLE_HOME_DIR
export PATH=\$JAVA_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH
# メモリ 3GB 級のマシンでは gradle.properties の -Xmx8192m を上書きする
export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=768m -Dfile.encoding=UTF-8"
export KOTLIN_DAEMON_JVMARGS="-Xmx1536m"
EOF
log "環境変数: source $PREFIX/env.sh"

log "完了。ビルド例:"
cat <<'EOF'
  source /tmp/toolchain/env.sh
  ./gradlew :app:assembleModernDebug \
    -Pkotlin.daemon.jvmargs="$KOTLIN_DAEMON_JVMARGS" \
    --no-configuration-cache
EOF
