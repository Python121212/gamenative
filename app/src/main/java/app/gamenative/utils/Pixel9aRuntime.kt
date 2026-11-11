package app.gamenative.utils

import android.content.Context
import app.gamenative.BuildConfig
import app.gamenative.service.SteamService
import com.winlator.core.TarCompressorUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Request
import timber.log.Timber
import java.io.File
import java.security.MessageDigest

/** Bundled as `assets/pixel9a-bootstrap.json`. */
@Serializable
data class BootstrapPlan(
    val version: Int = 1,
    val pack: BootstrapPack,
    val prefetch: List<BootstrapFile> = emptyList(),
)

@Serializable
data class BootstrapPack(
    val name: String,
    val url: String,
    val sha256Url: String,
)

@Serializable
data class BootstrapFile(
    val name: String,
    val path: String? = null,
    val optional: Boolean = true,
)

data class BootstrapState(
    val active: Boolean = false,
    val label: String = "",
    val progress: Float = 0f,
    val error: String? = null,
)

/**
 * First-run bootstrap for the Pixel 9a build.
 *
 * Everything that is not needed to boot the UI lives outside the APK:
 *  - Wine / Proton / container / driver payloads (manifest.json + downloads),
 *  - the ultra-compressed XZ runtime asset pack on GitHub Releases.
 *
 * On every app open this object (a) expands the runtime pack once, (b) warms the
 * component manifest, and (c) pre-fetches the first-run files that the launcher
 * would otherwise download on the first game start. Failures are non-fatal and
 * are retried on the next launch.
 */
object Pixel9aRuntime {
    private const val TAG = "Pixel9aRuntime"
    private const val PLAN_ASSET = "pixel9a-bootstrap.json"

    private val _state = MutableStateFlow(BootstrapState())
    val state: StateFlow<BootstrapState> = _state.asStateFlow()

    @Volatile
    private var job: Job? = null

    private val json = Json { ignoreUnknownKeys = true }

    /** Called from Application.onCreate — never blocks the main thread. */
    fun start(context: Context, scope: CoroutineScope) {
        if (job?.isActive == true) return
        job = scope.launch(Dispatchers.IO) {
            val app = context.applicationContext
            _state.value = BootstrapState(active = true, label = "Preparing Pixel 9a runtime")
            try {
                run(app)
                _state.value = BootstrapState(active = false, label = "Ready", progress = 1f)
            } catch (t: Throwable) {
                Timber.tag(TAG).w(t, "first-run bootstrap failed; will retry next launch")
                _state.value = BootstrapState(active = false, label = "Runtime download pending", error = t.message)
            }
        }
    }

    private suspend fun run(context: Context) = withContext(Dispatchers.IO) {
        val plan = json.decodeFromString<BootstrapPlan>(
            context.assets.open(PLAN_ASSET).bufferedReader().use { it.readText() },
        )
        Timber.tag(TAG).i(
            "%s bootstrap v%d / %s / %s",
            BuildConfig.DEVICE_PROFILE, plan.version, BuildConfig.DEVICE_SOC, BuildConfig.DEVICE_GPU,
        )

        expandRuntimePack(context, plan)
        warmComponentManifest(context)

        var index = 0
        for (item in plan.prefetch) {
            index++
            val dest = File(context.filesDir, item.path ?: item.name)
            if (dest.isFile && dest.length() > 0) continue
            _state.value = BootstrapState(
                active = true,
                label = "Downloading ${item.name}",
                progress = index.toFloat() / (plan.prefetch.size + 1),
            )
            try {
                SteamService.fetchFileWithFallback(item.name, dest, context) { p ->
                    _state.value = _state.value.copy(progress = (index - 1 + p) / (plan.prefetch.size + 1))
                }
                Timber.tag(TAG).i("prefetched %s (%d bytes)", item.name, dest.length())
            } catch (e: Exception) {
                dest.delete()
                if (!item.optional) throw e
                Timber.tag(TAG).w(e, "optional prefetch failed: %s", item.name)
            }
        }
    }

    /** Download (once), verify SHA-256, then expand the XZ runtime pack. */
    private fun expandRuntimePack(context: Context, plan: BootstrapPlan) {
        val root = Pixel9aAssets.dir(context).apply { mkdirs() }
        val marker = File(root, ".${plan.pack.name}.v${plan.version}.done")
        if (marker.isFile) return

        _state.value = BootstrapState(active = true, label = "Downloading runtime assets")
        val packFile = File(context.cacheDir, plan.pack.name)
        if (!packFile.isFile || packFile.length() == 0L) {
            download(plan.pack.url, packFile) { p -> _state.value = _state.value.copy(progress = p * 0.5f) }
        }

        val expected = runCatching { fetchText(plan.pack.sha256Url).trim().substringBefore(' ').lowercase() }
            .getOrDefault("")
        val actual = sha256(packFile)
        if (expected.length == 64 && expected != actual) {
            packFile.delete()
            error("runtime pack checksum mismatch (expected $expected, got $actual)")
        }

        _state.value = BootstrapState(active = true, label = "Expanding runtime assets", progress = 0.6f)
        val ok = TarCompressorUtils.extract(TarCompressorUtils.Type.XZ, packFile, root)
        if (!ok) {
            packFile.delete()
            error("failed to expand ${plan.pack.name}")
        }
        marker.writeText("v${plan.version} sha256=$actual")
        packFile.delete()
        Timber.tag(TAG).i("runtime pack expanded into %s", root.absolutePath)
    }

    /** Warm the external Wine/Proton/container/driver catalogue on every app open. */
    private suspend fun warmComponentManifest(context: Context) {
        try {
            ManifestRepository.loadManifest(context)
        } catch (e: Exception) {
            Timber.tag(TAG).w(e, "component manifest refresh failed (non-fatal)")
        }
    }

    private fun download(url: String, dest: File, onProgress: (Float) -> Unit) {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "GameNative-Pixel9a/${BuildConfig.VERSION_NAME}")
            .build()
        Net.http.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "HTTP ${response.code} for $url" }
            val body = response.body ?: error("empty response body for $url")
            val total = body.contentLength()
            val tmp = File(dest.absolutePath + ".part")
            tmp.outputStream().buffered().use { out ->
                body.byteStream().buffered().use { input ->
                    val buf = ByteArray(64 * 1024)
                    var done = 0L
                    while (true) {
                        val read = input.read(buf)
                        if (read < 0) break
                        if (read == 0) continue
                        out.write(buf, 0, read)
                        done += read
                        if (total > 0) onProgress(done.toFloat() / total)
                    }
                }
            }
            if (total > 0 && tmp.length() != total) {
                tmp.delete()
                error("incomplete download: ${tmp.length()} / $total")
            }
            if (!tmp.renameTo(dest)) {
                tmp.copyTo(dest, overwrite = true)
                tmp.delete()
            }
        }
    }

    private fun fetchText(url: String): String {
        val request = Request.Builder().url(url).build()
        Net.http.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "HTTP ${response.code} for $url" }
            return response.body?.string() ?: error("empty response body for $url")
        }
    }

    private fun sha256(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buf = ByteArray(128 * 1024)
            while (true) {
                val read = input.read(buf)
                if (read < 0) break
                if (read > 0) md.update(buf, 0, read)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
}
