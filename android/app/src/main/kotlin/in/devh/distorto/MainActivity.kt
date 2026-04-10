package `in`.devh.distorto

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "in.devh.distorto/wallpaper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openWallpaperPicker") {
                val path = call.argument<String>("path")
                if (path != null) {
                    openWallpaperPicker(path)
                    result.success(null)
                } else {
                    result.error("INVALID_PATH", "Path was null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openWallpaperPicker(path: String) {
        val file = File(path)
        val uri: Uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        
        try {
            val wallpaperManager = android.app.WallpaperManager.getInstance(this)
            val intent = wallpaperManager.getCropAndSetWallpaperIntent(uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback to chooser if direct intent fails
            val intent = Intent(Intent.ACTION_ATTACH_DATA)
            intent.addCategory(Intent.CATEGORY_DEFAULT)
            intent.setDataAndType(uri, "image/*")
            intent.putExtra("mimeType", "image/*")
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(intent, "Set as Wallpaper"))
        }
    }
}
