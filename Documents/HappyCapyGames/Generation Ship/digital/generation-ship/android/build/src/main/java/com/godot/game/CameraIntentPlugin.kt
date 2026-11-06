package com.godot.game

import android.app.Activity
import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Environment
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import kotlin.math.max
import androidx.core.content.FileProvider
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File

// Captures a single photo for the photo-scan feature. Since 2026-10 with our own camera
// screen (ScanCameraActivity: CameraX, live guidance, torch where it's dim — the camera app's own
// exposure choices made evening photos unreadable; the other burst shots are left next to the
// photo as <name>_alt1.jpg, _alt2.jpg); the device's camera app (ACTION_IMAGE_CAPTURE) is the fallback
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
//
// 2026-11-02: pick_photo() — a photo from the gallery (the system photo picker, no permission
// needed): the way to the phone's own Night mode on every phone, since many makers don't offer
// it to apps (the camera app's night photo of a real ship read 14 of 15 dials, a plain one 9).
// The pick is copied into captured_photos as pick_<time>.jpg (.png); HEIC and anything over
// MAX_PICK_LONG px (50 MP modes) is decoded and saved as a JPEG of at most that size.
class CameraIntentPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val REQUEST_IMAGE_CAPTURE = 4173
		private const val REQUEST_SCAN_CAMERA = 4174
		private const val REQUEST_PICK_PHOTO = 4175
		private const val REQUEST_PICK_VENDOR = 4176
		// The camera app straight in its night mode, where the maker lets apps ask for it (tried in turn,
		// then the plain camera app). Honor: StoreShow, exported (MagicOS, checked 2026-11-06 on the Honor 200)
		private val NIGHT_CAMERAS = listOf(Pair("com.hihonor.camera", "com.hihonor.camera.store.show.NIGHT_SCENE"))
		// The maker's own gallery as the picker: full screen, the newest photo one tap away (Android's
		// picker opens as a half sheet: the user had to swipe it up first)
		private val VENDOR_GALLERIES = listOf("com.hihonor.photos")
		private const val MAX_PICK_LONG = 4608
		private val PHOTO_CAPTURED_SIGNAL = SignalInfo("photo_captured", String::class.java)
		private val PHOTO_CANCELED_SIGNAL = SignalInfo("photo_canceled")
	}

	private var pendingPhotoPath: String? = null
	private var awaitingCameraApp = false      // open_camera_app(): pick the photo once the game is back
	private var hint: String = ""
	private var guide: String = ""

	override fun getPluginName() = "CameraIntentPlugin"

	override fun getPluginSignals(): Set<SignalInfo> = setOf(PHOTO_CAPTURED_SIGNAL, PHOTO_CANCELED_SIGNAL)

	// The line shown on top of the camera screen (already translated by the game).
	@UsedByGodot
	fun set_hint(text: String) {
		hint = text
	}

	// The live guidance lines (translated by the game), "\n"-joined: no ship in view / move
	// closer / hold still / taking the photo / (optional) the tip shown where it's dim.
	@UsedByGodot
	fun set_guide(texts: String) {
		guide = texts
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
			intent.putExtra(ScanCameraActivity.EXTRA_GUIDE, guide)
			activity.startActivityForResult(intent, REQUEST_SCAN_CAMERA)
		}
	}

	// A photo from the gallery: photo_captured(copy's path) when one was picked, else photo_canceled.
	// The maker's own gallery where known (VENDOR_GALLERIES), else Android's photo picker.
	@UsedByGodot
	fun pick_photo() {
		runOnUiThread {
			val activity = activity ?: run {
				emitSignal(PHOTO_CANCELED_SIGNAL)
				return@runOnUiThread
			}
			for (pkg in VENDOR_GALLERIES) {
				try {
					activity.startActivityForResult(
						Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).setPackage(pkg), REQUEST_PICK_VENDOR)
					return@runOnUiThread
				} catch (e: Throwable) {      // not on this phone
				}
			}
			pickSystem()
		}
	}

	// Android's photo picker (Android 13+), else the document picker.
	private fun pickSystem() {
		runOnUiThread {
			val activity = activity ?: run {
				emitSignal(PHOTO_CANCELED_SIGNAL)
				return@runOnUiThread
			}
			try {
				val intent = if (Build.VERSION.SDK_INT >= 33) {
					Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*")
				} else {
					Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
				}
				activity.startActivityForResult(intent, REQUEST_PICK_PHOTO)
			} catch (e: Throwable) {          // no picker on this phone
				emitSignal(PHOTO_CANCELED_SIGNAL)
			}
		}
	}

	// 2026-11-06: the phone's own camera app, the full one (its Night mode: on the real cut cards its
	// night shots read nearly everything, this game's camera screen ~90 % at best — Honor and others
	// don't offer their night processing to apps, and the camera app's "take a photo for an app" screen
	// is a cut-down one without it, whose exposure made evening photos unreadable in 2026-10). The
	// player takes the photo there and comes back; on the way back the photo picker opens by itself
	// (newest first), and the pick goes on like From Gallery: photo_captured / photo_canceled. No camera
	// app to open: the picker straight away.
	@UsedByGodot
	fun open_camera_app() {
		runOnUiThread {
			val activity = activity ?: run {
				emitSignal(PHOTO_CANCELED_SIGNAL)
				return@runOnUiThread
			}
			// its night mode where the maker lets apps ask for it, else the camera app as it opens
			for ((pkg, action) in NIGHT_CAMERAS) {
				try {
					activity.startActivity(Intent(action).setPackage(pkg))
					awaitingCameraApp = true
					return@runOnUiThread
				} catch (e: Throwable) {      // not this maker's camera
				}
			}
			try {
				activity.startActivity(Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA))
				awaitingCameraApp = true
			} catch (e: Throwable) {          // no camera app (or none that answers this intent)
				pick_photo()
			}
		}
	}

	override fun onMainResume() {
		super.onMainResume()
		if (awaitingCameraApp) {
			awaitingCameraApp = false
			pick_photo()
		}
	}

	// The picked photo into captured_photos (off the main thread: a big HEIC takes a moment to
	// decode); the signal goes out on the UI thread like the camera's.
	// fromVendor: picked in the maker's gallery; if its photo can't be read (no read grant on the
	// returned address), Android's picker opens instead of the scan just failing
	private fun copyPick(activity: Activity, uri: Uri, fromVendor: Boolean = false) {
		val dir = File(activity.filesDir, "captured_photos")
		val stamp = System.currentTimeMillis()
		var out = File(dir, "pick_$stamp.jpg")
		Thread {
			var ok = false
			try {
				dir.mkdirs()
				val resolver = activity.contentResolver
				val type = resolver.getType(uri) ?: ""
				val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
				resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
				val long = max(bounds.outWidth, bounds.outHeight)
				if ((type == "image/jpeg" || type == "image/png") && long in 1..MAX_PICK_LONG) {
					// as it is (named by its kind: Godot picks the image loader by the file's extension)
					if (type == "image/png") out = File(dir, "pick_$stamp.png")
					resolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } }
					ok = out.length() > 0
				} else if (long > 0) {
					var sample = 1
					while (long / (sample * 2) >= MAX_PICK_LONG * 3 / 4 && long / sample > MAX_PICK_LONG) sample *= 2
					val opts = BitmapFactory.Options().apply { inSampleSize = sample }
					var bmp = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
					if (bmp != null) {
						val l = max(bmp.width, bmp.height)
						if (l > MAX_PICK_LONG) {
							val f = MAX_PICK_LONG.toFloat() / l
							val scaled = Bitmap.createScaledBitmap(bmp, (bmp.width * f).toInt(), (bmp.height * f).toInt(), true)
							if (scaled !== bmp) bmp.recycle()
							bmp = scaled
						}
						out.outputStream().use { ok = bmp.compress(Bitmap.CompressFormat.JPEG, 95, it) }
						bmp.recycle()
					}
				}
			} catch (e: Throwable) {          // unreadable pick, full storage, out of memory
				ok = false
			}
			if (!ok) out.delete()
			runOnUiThread {
				if (ok) emitSignal(PHOTO_CAPTURED_SIGNAL, out.absolutePath) else if (fromVendor) pickSystem() else emitSignal(PHOTO_CANCELED_SIGNAL)
			}
		}.start()
	}

	// Copies a scan photo into the public gallery (Pictures/Generation Ship) — the photos
	// themselves live in the app's private files, which nothing else can read. Android 10+
	// only (MediaStore needs no storage permission there); returns whether it worked.
	@UsedByGodot
	fun save_to_gallery(path: String): Boolean {
		val activity = activity ?: return false
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
			return false
		}
		val src = File(path)
		if (!src.exists()) {
			return false
		}
		return try {
			val resolver = activity.contentResolver
			val values = ContentValues().apply {
				put(MediaStore.Images.Media.DISPLAY_NAME, src.name)
				put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
				put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Generation Ship")
				put(MediaStore.Images.Media.IS_PENDING, 1)
			}
			val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
			resolver.openOutputStream(uri)?.use { out -> src.inputStream().use { it.copyTo(out) } }
			values.clear()
			values.put(MediaStore.Images.Media.IS_PENDING, 0)
			resolver.update(uri, values, null, null)
			true
		} catch (e: Exception) {
			false
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
		if (requestCode == REQUEST_PICK_VENDOR) {
			val uri = data?.data
			val activity = activity
			if (resultCode == Activity.RESULT_OK && uri != null && activity != null) {
				copyPick(activity, uri, fromVendor = true)
			} else {
				emitSignal(PHOTO_CANCELED_SIGNAL)
			}
			return
		}
		if (requestCode == REQUEST_PICK_PHOTO) {
			val uri = data?.data
			val activity = activity
			if (resultCode == Activity.RESULT_OK && uri != null && activity != null) {
				copyPick(activity, uri)
			} else {
				emitSignal(PHOTO_CANCELED_SIGNAL)
			}
			return
		}
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
