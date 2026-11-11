# GameNative — Google Pixel 9a 専用・超軽量ビルド

Google Pixel 9a（Tensor G4 / Mali-G715 MP7 / ARM64-v8a / Android 15+）専用にチューニングした
GameNative の APK です。上流の `v1.4.0` APK（約 571 MB）から、**Wine / Proton / コンテナ /
ドライバーをすべて外部化**し、APK 本体とワークスペースを 100 MB 以下（目標 90 MB）に抑えます。

## 何をしているか

| 項目 | 対応内容 |
|---|---|
| **ABI** | `arm64-v8a` のみ。`armeabi-v7a` / `x86` / `x86_64` の `.so` を APK から除外 |
| **R8 / ProGuard** | `proguard-android-optimize.txt` + `proguard-rules.pro` + `proguard-pixel9a.pro`。minify / shrinkResources / R8 full mode、`Timber.d/v` と `Log.d/v` の `-assumenosideeffects` で DEX を削減。JNI 名は `-dontobfuscate` で保護 |
| **デバッグシンボル** | `debugSymbolLevel = "NONE"` + CI で NDK の `llvm-strip --strip-all` を全 `.so` に適用 |
| **ネイティブライブラリ圧縮** | `useLegacyPackaging = true`（APK 内で deflate 圧縮）。オプション機能の `.so`（`libcomet.so` / `libopenxr_loader.so` / `libfossilize_*.so` / `liblsfg-vk-layer.so`）は APK から除外し、各機能は「ファイルが無ければ無効化」する既存の分岐で安全にスキップ |
| **Wine / Proton / コンテナ / ドライバー** | APK に同梱しない。`assets/manifest.json`（Pixel 9a 用に ARM64EC / bionic のみ、Adreno/Turnip ドライバーは空）と既存ダウンローダ経由で外部取得 |
| **アセット超高圧縮** | 外部ランタイムパックを **XZ `-9e`**、同梱 `.tzst` を **ZSTD level 19** で再圧縮。PNG アイコン・ARM64EC 入力 DLL は APK から除外 |
| **初回展開 / 自動ダウンロード** | `Pixel9aRuntime` がアプリ起動時に自動実行。GitHub Releases の `pixel9a-runtime-v1.tar.xz` を取得 → **SHA-256 検証** → `TarCompressorUtils(XZ)` で `filesDir/pixel9a_runtime/` に展開 → コンポーネント manifest を温め → 初回必須ファイルを事前取得。失敗時は次回起動で再試行（致命エラーにはしない） |
| **不要アセット削除** | x86 用入力 DLL、未使用の 1.5 MB ベクター、14 言語の翻訳、テストソース、Room スキーマ履歴、ネイティブ C/C++ ソースをワークスペースから除外（ビルド時に pinned commit / GitHub Releases から復元） |
| **Pixel 9a チューニング** | `minSdk 29` / `targetSdk 36` / `compileSdk 36`、`localeFilters = en, ja`、`DEVICE_PROFILE = pixel9a` / `DEVICE_SOC = Tensor G4` / `DEVICE_GPU = Mali-G715 MP7` を BuildConfig に埋め込み |

## 外部化の仕組み

```
APK (小)
 ├─ Kotlin/Java DEX (R8)
 ├─ 必須 .so のみ (arm64-v8a, strip 済み, deflate 圧縮)
 ├─ assets/manifest.json       … Pixel 9a 用コンポーネント一覧
 └─ assets/pixel9a-bootstrap.json … 初回ダウンロード計画

GitHub Releases / downloads.gamenative.app (大・120 MB 超もこちら)
 ├─ pixel9a-runtime-v1.tar.xz      … アイコン / 入力 DLL (XZ -9e)
 ├─ *.wcp / *.tzst / *.txz         … Proton / DXVK / VKD3D / FEX / Box64
 └─ imagefs_bionic.txz             … コンテナ rootfs
```

`PluviaApp.onCreate()` → `Pixel9aRuntime.start()` → バックグラウンドでダウンロード・検証・展開。
`Pixel9aAssets.open()/file()` が「展開済みファイル → APK assets」の順に解決するため、
ダウンロード未完了でも UI は落ちません。進捗は `Pixel9aRuntime.state`（`StateFlow`）で公開しています。

## ビルド

ローカルには JDK / Android SDK が無いため、GitHub Actions（`.github/workflows/pixel9a-build.yml`）でビルドします。

```bash
# ブランチへの push で自動実行 / 手動実行（ブランチ名は現在の作業ブランチ）
gh workflow run pixel9a-build.yml --ref "$(git rev-parse --abbrev-ref HEAD)"
```

CI の流れ:

1. JDK 17 / `platforms;android-36` / `build-tools;35.0.0` / `ndk;27.3.13750724` を用意
2. `tools/restore-payloads.sh` — ワーキングツリーから除外した `.so` と外部アセットを pinned commit から復元
3. NDK `llvm-strip` で全 `.so` を strip
4. `tools/build-runtime-pack.sh` — ZSTD 19 再圧縮 + XZ `-9e` ランタイムパック + SHA-256 を生成
5. `./gradlew :app:assembleModernRelease`（R8 / shrinkResources / arm64-v8a）
6. 生成物を GitHub Releases（タグ `pixel9a-runtime-v1`）と Actions アーティファクトに公開
   （APK は Git 履歴にコミットしません）

生成 APK: `dist/GameNative-Pixel9a.apk`（デバッグ鍵署名。実機インストール用）

- ダウンロード: <https://github.com/Python121212/gamenative/releases/tag/pixel9a-runtime-v1>
- 実行履歴: `gh run list --workflow pixel9a-build.yml`

### ローカルでビルドする場合（JDK 17 + Android SDK）

`tools/setup-android-toolchain.sh` が `/tmp/toolchain` に最小構成をまとめて導入します
（リポジトリは汚しません）。既定で JDK 17（Temurin）+ cmdline-tools + `platforms;android-36`
+ `build-tools;35.0.0`、`WITH_NDK=1` で `ndk;27.3.13750724` と `cmake;3.22.1` も導入します。

```bash
./tools/setup-android-toolchain.sh          # 初回（約 1 GB / 10 分程度）
source /tmp/toolchain/env.sh                # JAVA_HOME / ANDROID_HOME / GRADLE_USER_HOME
./gradlew :app:assembleModernRelease --no-configuration-cache
```

必要な外向き通信: `dl.google.com`（Android SDK）、`services.gradle.org`（Gradle 本体）、
`maven.google.com` / `repo1.maven.org`（依存解決）、`github.com`（JDK）。
これらが遮断されたサンドボックス（GitHub / PyPI / npm のみ許可）では
依存解決ができないためビルド不可で、CI 経由のみが現実的な手段です。

## ワークスペース容量

外部化したバイナリは `tools/` と `.gitignore` のルールでリポジトリに保持せず、
`.git` 履歴（pinned commit）と GitHub Releases だけに置いています。
`/tmp/pixel9a-payload` などの一時領域はワークスペースにカウントされません。

## 上流

- オリジナル: https://github.com/utkarshdalal/GameNative.git
- ライセンス: [LICENSE](LICENSE)
