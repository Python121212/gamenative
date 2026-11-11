package app.gamenative.utils

import android.content.Context
import java.io.File
import java.io.InputStream

/**
 * Resolves assets that were externalized from the APK for the Pixel 9a build.
 *
 * The first-run bootstrap downloads `pixel9a-runtime-v1.tar.xz` (XZ ultra) and
 * expands it into `filesDir/pixel9a_runtime/`. If the pack has not been expanded
 * yet, every caller transparently falls back to the copy inside the APK, so a
 * missing / interrupted download never hard-fails the app.
 */
object Pixel9aAssets {
    const val RUNTIME_DIR = "pixel9a_runtime"

    @JvmStatic
    fun dir(context: Context): File = File(context.filesDir, RUNTIME_DIR)

    @JvmStatic
    fun file(context: Context, name: String): File? =
        File(dir(context), name).takeIf { it.isFile && it.length() > 0 }

    /** Opens an externalized asset, falling back to the APK asset store. */
    @JvmStatic
    fun open(context: Context, name: String): InputStream =
        file(context, name)?.inputStream() ?: context.assets.open(name)
}
