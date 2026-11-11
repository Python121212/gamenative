# GameNative - Google Pixel 9a 専用ビルド

Google Pixel 9a (Tensor G4, ARM64-v8a) にチューニングした GameNative の APK ビルド設定です。

## サイズ削減の方針

| 項目 | 対応 |
|------|------|
| **ABI フィルタ** | `arm64-v8a` のみ（Pixel 9a は 64bit ARM のみ） |
| **レガシーフレーバー削除** | `legacy`, `legacyXr`, `modernXr` を削除（x86/armeabi-v7a サポートを廃止、約 440MB 削減） |
| **言語リソース** | `en` + `ja` のみ（15言語から削減） |
| **ProGuard/R8** | `proguard-android-optimize.txt` を使用、minify/shrink 有効 |
| **ネイティブライブラリ** | リリースビルドでデバッグシンボルを削除（`debugSymbolLevel = SYMBOL_TABLE`） |
| **アセット圧縮** | ZSTD (`.tzst`) / XZ 圧縮を適用 |
| **不要アセットの外部化** | `box86_64`, `dxwrapper`, `fexcore`, `steampipe`, `wowbox64` など x86 用エミュレータ・ドライバを APK から除外し、初回起動時に外部サーバーからダウンロード |
| **Wine/Proton コンテナ** | `:ubuntufs` ダイナミック機能モジュールとして外部化。アプリ起動時に別途ダウンロード |
| **グラフィックスドライバ** | `manifest.json` から Adreno/Turnip ドライバを削除（Pixel 9a は Adreno 非搭載のため不要） |

## ビルド手順

### 前提条件

- Android SDK (compileSdk 36, NDK 27.3.13750724)
- JDK 17
- Android NDK

### ローカルビルド

```bash
# プロジェクトルート
cd /path/to/gamenative

# 現地キーストア設定（release-signed 用）
cp app/keystores/keystore.properties.example app/keystores/keystore.properties
# keystore.properties に storeFile, storePassword, keyAlias, keyPassword を設定

# Pixel 9a 専用リリースビルド（modern フレーバー / arm64-v8a）
./gradlew app:assembleModernRelease

# 署名付きリリースビルド
./gradlew app:assembleModernRelease-signed
```

生成 APK: `app/build/outputs/apk/modern/release/`

### 初回起動時の外部ダウンロード

アプリを初回起動すると、以下を外部サーバーから自動ダウンロードします：

- Wine / Proton コンテナ（`:ubuntufs` ダイナミック機能モジュール）
- グラフィックスドライバ（`manifest.json` の URL 経由）
- x86 エミュレータ（FEX, Box64 など、ARM 上で x86 Windows ゲームを動作させるため）

ダウンロード先 URL は `manifest.json` に定義されており、Pixel 9a に必要な ARM64ec バージョンのみが含まれます。

### APK サイズ目標

- **APK 本体**: 90MB 以下（目標）
- **初回ダウンロード分**: Wine/Proton コンテナ等は別途ダウンロード（APK に含めず）

## フレーバー構成

- `modern` (デフォルト): arm64-v8a のみ、minSdk 29、targetSdk 36、Pixel 9a 対応

削除済みフレーバー：`legacy`, `legacyXr`, `modernXr`

## ライセンス

[LICENSE](LICENSE) を参照してください。