package com.godot.game

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File

// Captures a single photo for the photo-scan feature. Since 2026-10 with our own camera
// screen (ScanCameraActivity: CameraX, torch on — the camera app's own exposure choices made
// evening photos unreadable); the device's camera app (ACTION_IMAGE_CAPTURE) is the fallback
// when that can't run (camera permission refused, no back camera, CameraX failing).
// For the fallback, the photo goes to a FileProvider-shared path (required
// since Android 7 — raw file:// URIs handed to another app now throw
// FileUriExposedException) and the resulting local path is returned to
// GDScript via a signal, matching the async nature of leaving the app.
//
// Reuses Godot's own FileProvider (godot-lib's AndroidManifest already
// declares one at authority "${applicationId}.fileprovider") rather than
// declaring a second one — two <provider> tags with the same authority is a
// manifest-merge error, not just redundant. Godot's own res/xml/godot_
// provider_paths.xml only maps a <files-path> (Context.getFilesDir()), not
// a cache path, so the photo goes under filesDir instead of cacheDir.
class CameraIntentPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val REQUEST_IMAGE_CAPTURE = 4173
		private const val REQUEST_SCAN_CAMERA = 4174
		private val PHOTO_CAPTURED_SIGNAL = SignalInfo("photo_captured", String::class.java)
		private val PHOTO_CANCELED_SIGNAL = SignalInfo("photo_canceled")
	}

	private var pendingPhotoPath: String? = null
	private var hint: String = ""

	override fun getPluginName() = "CameraIntentPlugin"

	override fun getPluginSignals(): Set<SignalInfo> = setOf(PHOTO_CAPTURED_SIGNAL, PHOTO_CANCELED_SIGNAL)

	// The line shown on top of the camera screen (already translated by the game).
	@UsedByGodot
	fun set_hint(text: String) {
		hint = text
	}

	@UsedByGodot
	fun capture_photo() {
		runOnUiThread {
			val activity = activity ?: run {
				emitSignal(PHOTO_CANCELED_SIGNAL)
				return@runOnUiThread
			}
			val photoDir = File(activity.filesDir, "captured_photos")
			photoDir.mkdirs()
			val photoFile = File(photoDir, "scan_${System.currentTimeMillis()}.jpg")
			pendingPhotoPath = photoFile.absolutePath
			val intent = Intent(activity, ScanCameraActivity::class.java)
			intent.putExtra(ScanCameraActivity.EXTRA_OUTPUT_PATH, photoFile.absolutePath)
			intent.putExtra(ScanCameraActivity.EXTRA_HINT, hint)
			activity.startActivityForResult(intent, REQUEST_SCAN_CAMERA)
		}
	}

	// The device's camera app, for when our own camera screen can't run.
	private fun captureWithCameraApp() {
		runOnUiThread {
			// GodotPlugin.activity is nullable (the host Activity may not be
			// alive at call time) — bind it to a local non-null val once so
			// every use below doesn't need its own null-check.
			val activity = activity ?: run {
				emitSignal(PHOTO_CANCELED_SIGNAL)
				return@runOnUiThread
			}
			val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
			if (intent.resolveActivity(activity.packageManager) == null) {
				emitSignal(PHOTO_CANCELED_SIGNAL)
				return@runOnUiThread
			}
			val photoDir = File(activity.filesDir, "captured_photos")
			photoDir.mkdirs()
			val photoFile = File(photoDir, "scan_${System.currentTimeMillis()}.jpg")
			pendingPhotoPath = photoFile.absolutePath
			val photoUri: Uri = FileProvider.getUriForFile(
				activity, "${activity.packageName}.fileprovider", photoFile)
			intent.putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
			intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
			activity.startActivityForResult(intent, REQUEST_IMAGE_CAPTURE)
		}
	}

	override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		if (requestCode == REQUEST_SCAN_CAMERA && resultCode == ScanCameraActivity.RESULT_FALLBACK) {
			pendingPhotoPath = null
			captureWithCameraApp()
			return
		}
		if (requestCode != REQUEST_IMAGE_CAPTURE && requestCode != REQUEST_SCAN_CAMERA) {
			return
		}
		val path = pendingPhotoPath
		pendingPhotoPath = null
		if (resultCode == Activity.RESULT_OK && path != null) {
			emitSignal(PHOTO_CAPTURED_SIGNAL, path)
		} else {
			emitSignal(PHOTO_CANCELED_SIGNAL)
		}
	}
}
