package com.godot.game

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.os.Bundle
import android.os.SystemClock
import android.util.Size
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.UseCase
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.extensions.ExtensionMode
import androidx.camera.extensions.ExtensionsManager
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

// Scan Tableau's own camera screen (CameraX), replacing the hand-off to the phone's camera
// app: that one decides flash, exposure and focus itself, and in the evening under lamps it
// shot at 1/25 s handheld — blurry dials, unreadable tokens (real photos 2026-10-06). Capture
// is at the highest 4:3 resolution in quality mode, the flash stays off (its glints on the
// cards fooled the reader), and a tap focuses there. Returns the saved JPEG's path like the
// old intent did.
// 2026-10-15, better photos for the dial reader without changing the cards:
//  - the phone's own multi-frame processing (CameraX Extensions HDR / auto / night) when it offers it,
//    else a burst of BURST shots of which the sharpest is kept (shaky hands)
//  - focus + exposure metered at the centre right before each shot
//  - EXPOSURE_EV darker, so colours (the violet diamond) don't wash out
//  - a small status line names what's in use (tell the developer which modes a phone offers)
// 2026-11-01, live guidance (the photo that can't be read is better prevented than rescued):
//  - while aiming, the violet diamonds of the dials are found in a low-resolution copy of the
//    preview and ringed on screen (green: big enough to read, yellow: too small), and a line
//    says what to do: point at the ship / move closer / hold still
//  - AUTO (on by default, remembered): the photo is taken by itself once enough diamonds are
//    big enough and the phone has been steady for a moment (gyroscope x exposure time: how far
//    the picture would smear)
//  - the torch is no longer always on: it comes on by itself only where it's dim (the camera's
//    exposure time x ISO; the light sensor if the camera doesn't say) — in good light its bright
//    spot on the cards cost more than it gave; the torch button still switches it by hand
//  - the other burst shots are kept next to the photo (<name>_alt1.jpg, _alt2.jpg): the game
//    takes a second look at them for cards it couldn't read in the sharpest one
// Camera permission refused, no back camera or CameraX failing: RESULT_FALLBACK, and the
// plugin opens the camera app instead.
class ScanCameraActivity : ComponentActivity(), SensorEventListener {

	companion object {
		const val EXTRA_OUTPUT_PATH = "output_path"
		const val EXTRA_HINT = "hint"
		const val EXTRA_GUIDE = "guide"          // "\n"-joined: no ship / move closer / hold still / taking the photo
		const val RESULT_FALLBACK = Activity.RESULT_FIRST_USER + 1
		private const val PREFS = "scan_camera"
	}

	private lateinit var previewView: PreviewView
	private lateinit var overlay: GuideOverlay
	private lateinit var shutter: View
	private lateinit var torchButton: TextView
	private lateinit var autoButton: TextView
	private lateinit var guideLabel: TextView
	private var imageCapture: ImageCapture? = null
	private var camera: Camera? = null
	private var torchOn = false
	private var torchByHand = false        // the player switched it: no more automatic changes
	private var torchDecided = false
	private var autoShoot = true
	private var lastShotAuto = false       // the shot under way was taken by AUTO
	@Volatile private var busy = false
	private lateinit var status: TextView
	private var statusBase = ""             // mode, EV, resolution; the live figures follow it
	private var extensionName = ""          // "" = no extension, burst instead
	private val BURST = 3
	private val EXPOSURE_EV = -0.7f
	private var openedAt = 0L

	// guidance
	private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
	private var guideTexts = listOf("Point the camera at your ship", "Move closer", "Hold still", "Hold still – taking the photo")
	@Volatile private var exposureNs = 0L    // from the preview's capture results (0: unknown)
	@Volatile private var iso = 0
	private var focalPx = 0f                 // lens focal length in capture pixels (0: unknown)
	private var captureLong = 4032           // the capture's long side, px
	private var sensorManager: SensorManager? = null
	private val gyro = ArrayDeque<Pair<Long, Float>>()   // (time ms, angular speed rad/s)
	private var lux = -1f
	private var readySince = 0L
	private var lastAnalysis = 0L
	private var analysisBytes = ByteArray(0)
	private var analysisSeen = ByteArray(0)
	private var stack = IntArray(4096)

	// Diamonds read as big enough above this many px per mm (the reader reads 3000 px photos of a
	// whole ship, ~7 px/mm, fine; ~5 px/mm loses the tech lights), and the photo is good to take
	// with at least READY_DIAMONDS of them, the picture smearing less than MAX_SMEAR_PX for READY_MS.
	// The estimate from a diamond's area is rough: on the real photos of 2026-10 it came out 1.1-1.4x
	// the true px/mm for the final borderless diamond, 0.4-0.8x for the old pale and blurry prints
	// (those photos were 12-18 px/mm; a 6-sector ship filling the frame is ~7.5-8).
	private val GOOD_PX_PER_MM = 7.5f
	private val READY_DIAMONDS = 2
	private val MAX_SMEAR_PX = 1.2f
	private val READY_MS = 700L
	// the torch comes on where exposure time (s) x ISO is above this (bright room ~1-2, lamp-lit
	// evening ~10-30) — or, without exposure figures, below DIM_LUX on the light sensor
	private val DIM_EXPOSURE = 8.0f
	private val DIM_LUX = 60f
	private val MIN_CAPTURE_LONG = 3000       // px: below this the reader loses the tech lights on a whole ship

	private val askPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
		if (granted) startCamera() else finishWith(RESULT_FALLBACK)
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
		WindowCompat.setDecorFitsSystemWindows(window, false)
		WindowInsetsControllerCompat(window, window.decorView).let {
			it.hide(WindowInsetsCompat.Type.systemBars())
			it.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
		}
		intent.getStringExtra(EXTRA_GUIDE)?.split("\n")?.let { if (it.size >= 4 && it.all { s -> s.isNotBlank() }) guideTexts = it }
		autoShoot = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("auto", true)
		openedAt = SystemClock.elapsedRealtime()
		sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
		setContentView(buildUi())
		onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
			override fun handleOnBackPressed() = finishWith(Activity.RESULT_CANCELED)
		})
		if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
			startCamera()
		} else {
			askPermission.launch(Manifest.permission.CAMERA)
		}
	}

	override fun onResume() {
		super.onResume()
		// CameraX drops the torch and the exposure offset when the screen goes off or the player
		// switches apps: put both back (the torch button keeps showing what was chosen)
		if (camera != null) {
			applyTorch()
			applyExposure()
		}
		sensorManager?.let { sm ->
			sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
			sm.getDefaultSensor(Sensor.TYPE_LIGHT)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
		}
	}

	override fun onPause() {
		super.onPause()
		sensorManager?.unregisterListener(this)
	}

	override fun onDestroy() {
		super.onDestroy()
		analysisExecutor.shutdown()
	}

	override fun onSensorChanged(event: SensorEvent) {
		when (event.sensor.type) {
			Sensor.TYPE_GYROSCOPE -> {
				val v = event.values
				val now = SystemClock.elapsedRealtime()
				synchronized(gyro) {
					gyro.addLast(Pair(now, sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])))
					while (gyro.isNotEmpty() && now - gyro.first().first > 400) gyro.removeFirst()
				}
			}
			Sensor.TYPE_LIGHT -> lux = event.values[0]
		}
	}

	override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

	private fun dp(v: Float): Int =
		TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics).toInt()

	private fun circle(fill: Int, stroke: Int, strokeDp: Float): GradientDrawable = GradientDrawable().apply {
		shape = GradientDrawable.OVAL
		setColor(fill)
		setStroke(dp(strokeDp), stroke)
	}

	private fun buildUi(): View {
		val root = FrameLayout(this)
		root.setBackgroundColor(Color.BLACK)

		// the whole 4:3 frame stays visible (letterboxed), so what you see is what gets read
		previewView = PreviewView(this)
		previewView.scaleType = PreviewView.ScaleType.FIT_CENTER
		previewView.setOnTouchListener { v, ev ->
			if (ev.action == MotionEvent.ACTION_UP) {
				val point = previewView.meteringPointFactory.createPoint(ev.x, ev.y)
				camera?.cameraControl?.startFocusAndMetering(FocusMeteringAction.Builder(point).build())
				v.performClick()
			}
			true
		}
		root.addView(previewView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

		overlay = GuideOverlay(this)
		root.addView(overlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

		val hint = TextView(this)
		hint.text = intent.getStringExtra(EXTRA_HINT) ?: ""
		hint.setTextColor(Color.WHITE)
		hint.textSize = 16f
		hint.gravity = Gravity.CENTER
		hint.setShadowLayer(6f, 0f, 0f, Color.BLACK)
		hint.setPadding(dp(16f), dp(6f), dp(16f), dp(6f))
		root.addView(hint, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
			Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = dp(12f) })

		guideLabel = TextView(this)
		guideLabel.setTextColor(Color.WHITE)
		guideLabel.textSize = 22f
		guideLabel.gravity = Gravity.CENTER
		guideLabel.setShadowLayer(8f, 0f, 0f, Color.BLACK)
		guideLabel.setPadding(dp(18f), dp(8f), dp(18f), dp(8f))
		guideLabel.background = GradientDrawable().apply {
			cornerRadius = dp(22f).toFloat()
			setColor(Color.argb(120, 0, 0, 0))
		}
		guideLabel.visibility = View.INVISIBLE
		root.addView(guideLabel, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
			Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(34f) })

		shutter = View(this)
		shutter.background = circle(Color.argb(200, 255, 255, 255), Color.argb(255, 120, 220, 255), 4f)
		shutter.setOnClickListener { shoot() }
		root.addView(shutter, FrameLayout.LayoutParams(dp(76f), dp(76f), Gravity.END or Gravity.CENTER_VERTICAL).apply { marginEnd = dp(28f) })

		val close = TextView(this)
		close.text = "✕"
		close.setTextColor(Color.WHITE)
		close.textSize = 22f
		close.gravity = Gravity.CENTER
		close.background = circle(Color.argb(140, 0, 0, 0), Color.argb(200, 255, 255, 255), 1.5f)
		close.setOnClickListener { finishWith(Activity.RESULT_CANCELED) }
		root.addView(close, FrameLayout.LayoutParams(dp(52f), dp(52f), Gravity.TOP or Gravity.START).apply {
			marginStart = dp(20f)
			topMargin = dp(16f)
		})

		torchButton = TextView(this)
		torchButton.text = "⚡"
		torchButton.textSize = 24f
		torchButton.gravity = Gravity.CENTER
		torchButton.setOnClickListener {
			torchByHand = true
			torchDecided = true
			torchOn = !torchOn
			applyTorch()
		}
		root.addView(torchButton, FrameLayout.LayoutParams(dp(52f), dp(52f), Gravity.END or Gravity.TOP).apply {
			marginEnd = dp(40f)
			topMargin = dp(16f)
		})

		autoButton = TextView(this)
		autoButton.text = "AUTO"
		autoButton.textSize = 12f
		autoButton.gravity = Gravity.CENTER
		autoButton.setOnClickListener {
			autoShoot = !autoShoot
			readySince = 0L
			getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("auto", autoShoot).apply()
			applyAutoLook()
		}
		root.addView(autoButton, FrameLayout.LayoutParams(dp(52f), dp(52f), Gravity.END or Gravity.BOTTOM).apply {
			marginEnd = dp(40f)
			bottomMargin = dp(16f)
		})

		status = TextView(this)
		status.setTextColor(Color.argb(200, 255, 255, 255))
		status.textSize = 12f
		status.setShadowLayer(4f, 0f, 0f, Color.BLACK)
		root.addView(status, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
			Gravity.BOTTOM or Gravity.START).apply {
			marginStart = dp(20f)
			bottomMargin = dp(12f)
		})

		applyTorchLook()
		applyAutoLook()
		return root
	}

	private fun startCamera() {
		val future = ProcessCameraProvider.getInstance(this)
		future.addListener({
			try {
				val provider = future.get()
				// the phone's own multi-frame modes, if any (several frames merged by the camera's
				// processing, aligned and denoised) — only where the live guidance can run with them;
				// otherwise a plain capture + our burst
				val extFuture = ExtensionsManager.getInstanceAsync(this, provider)
				extFuture.addListener({
					var selector = CameraSelector.DEFAULT_BACK_CAMERA
					try {
						val ext = extFuture.get()
						for ((mode, name) in listOf(ExtensionMode.HDR to "HDR", ExtensionMode.AUTO to "Auto", ExtensionMode.NIGHT to "Night")) {
							if (ext.isExtensionAvailable(CameraSelector.DEFAULT_BACK_CAMERA, mode) &&
									ext.isImageAnalysisSupported(CameraSelector.DEFAULT_BACK_CAMERA, mode)) {
								selector = ext.getExtensionEnabledCameraSelector(CameraSelector.DEFAULT_BACK_CAMERA, mode)
								extensionName = name
								break
							}
						}
					} catch (e: Exception) {
						extensionName = ""
					}
					bindCamera(provider, selector)
				}, ContextCompat.getMainExecutor(this))
			} catch (e: Exception) {
				finishWith(RESULT_FALLBACK)
			}
		}, ContextCompat.getMainExecutor(this))
	}

	@OptIn(ExperimentalCamera2Interop::class)
	private fun bindCamera(provider: ProcessCameraProvider, cameraSelector: CameraSelector) {
		try {
			val selector = ResolutionSelector.Builder()
				.setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
				.setResolutionStrategy(ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY)
				.build()
			val previewBuilder = Preview.Builder()
				.setResolutionSelector(ResolutionSelector.Builder()
					.setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY).build())
			// exposure time + ISO of the live picture: how dim it is (torch) and how long a shot
			// would smear while the phone moves (auto shot)
			Camera2Interop.Extender(previewBuilder).setSessionCaptureCallback(object : CameraCaptureSession.CaptureCallback() {
				override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
					result.get(CaptureResult.SENSOR_EXPOSURE_TIME)?.let { exposureNs = it }
					result.get(CaptureResult.SENSOR_SENSITIVITY)?.let { iso = it }
				}
			})
			val preview = previewBuilder.build()
			preview.setSurfaceProvider(previewView.surfaceProvider)
			val capture = ImageCapture.Builder()
				.setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
				.setFlashMode(ImageCapture.FLASH_MODE_OFF)
				.setResolutionSelector(selector)
				.build()
			// a small copy of the live picture for the guidance (the diamonds are ~3-6 px there)
			val analysis = ImageAnalysis.Builder()
				.setResolutionSelector(ResolutionSelector.Builder()
					.setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
					.setResolutionStrategy(ResolutionStrategy(Size(1440, 1080), ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER))
					.build())
				.setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
				.setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
				.build()
			analysis.setAnalyzer(analysisExecutor) { analyze(it) }
			provider.unbindAll()
			var withGuide = true
			camera = bindFirst(provider, listOf(
				Pair(cameraSelector, listOf(preview, capture, analysis)),
				Pair(CameraSelector.DEFAULT_BACK_CAMERA, listOf(preview, capture, analysis)),
				Pair(cameraSelector, listOf(preview, capture)),
				Pair(CameraSelector.DEFAULT_BACK_CAMERA, listOf(preview, capture)),
			)) { i ->
				if (i % 2 == 1) extensionName = ""      // an extension that can't run with these use cases: plain camera + burst
				withGuide = i < 2
			}
			// the live picture must not cost the photo its resolution (a phone that can't stream
			// three sizes at once may lower the capture): then the photo wins, without guidance
			val longSide = capture.resolutionInfo?.resolution?.let { max(it.width, it.height) } ?: 0
			if (withGuide && longSide in 1 until MIN_CAPTURE_LONG) {
				camera = bindFirst(provider, listOf(
					Pair(cameraSelector, listOf(preview, capture)),
					Pair(CameraSelector.DEFAULT_BACK_CAMERA, listOf(preview, capture)),
				)) { i -> if (i == 1) extensionName = "" }
				withGuide = false
			}
			imageCapture = capture
			capture.resolutionInfo?.resolution?.let { captureLong = max(it.width, it.height) }
			focalPx = focalLengthPx()
			if (camera?.cameraInfo?.hasFlashUnit() != true) {
				torchButton.visibility = View.GONE
				torchDecided = true
			}
			if (!withGuide) {
				autoButton.visibility = View.GONE
				torchOn = true                 // no live picture to judge the light by: the old behaviour
				torchDecided = true
			}
			applyTorch()
			val ev = applyExposure()
			statusBase = (if (extensionName.isEmpty()) "Burst $BURST" else extensionName) +
				(if (ev != 0f) " · %+.1f EV".format(ev) else "") +
				(capture.resolutionInfo?.resolution?.let { " · ${it.width}×${it.height}" } ?: "")
			status.text = statusBase
			if (torchDecided) return
			// decide the torch once the exposure has settled
			previewView.postDelayed({ decideTorch() }, 1300)
		} catch (e: Exception) {
			finishWith(RESULT_FALLBACK)
		}
	}

	private fun bindFirst(provider: ProcessCameraProvider, tries: List<Pair<CameraSelector, List<UseCase>>>, chose: (Int) -> Unit): Camera {
		var last: Exception? = null
		for ((i, t) in tries.withIndex()) {
			try {
				provider.unbindAll()
				val cam = provider.bindToLifecycle(this, t.first, *t.second.toTypedArray())
				chose(i)
				return cam
			} catch (e: Exception) {
				last = e
			}
		}
		throw last ?: IllegalStateException("no camera")
	}

	@OptIn(ExperimentalCamera2Interop::class)
	private fun focalLengthPx(): Float {
		return try {
			val info = Camera2CameraInfo.from(camera!!.cameraInfo)
			val f = info.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull() ?: return 0f
			val size = info.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE) ?: return 0f
			f / max(size.width, size.height) * captureLong
		} catch (e: Exception) {
			0f
		}
	}

	private fun decideTorch() {
		if (torchDecided || isFinishing) return
		torchDecided = true
		if (torchByHand) return
		val t = exposureNs / 1e9f
		val dim = if (t > 0f && iso > 0) t * iso > DIM_EXPOSURE else if (lux >= 0f) lux < DIM_LUX else true
		torchOn = dim
		applyTorch()
		if (dim) statusBase += " · torch auto"
		status.text = statusBase
	}

	// darker by EXPOSURE_EV where the camera allows exposure compensation; returns what was set
	private fun applyExposure(): Float {
		val state = camera?.cameraInfo?.exposureState ?: return 0f
		if (!state.isExposureCompensationSupported) return 0f
		val step = state.exposureCompensationStep.toFloat()
		if (step <= 0f) return 0f
		val index = (EXPOSURE_EV / step).roundToInt().coerceIn(state.exposureCompensationRange.lower, state.exposureCompensationRange.upper)
		camera?.cameraControl?.setExposureCompensationIndex(index)
		return index * step
	}

	private fun applyTorch() {
		camera?.let {
			if (it.cameraInfo.hasFlashUnit()) {
				it.cameraControl.enableTorch(torchOn)
			}
		}
		applyTorchLook()
	}

	private fun applyTorchLook() {
		torchButton.setTextColor(if (torchOn) Color.rgb(255, 220, 90) else Color.argb(150, 255, 255, 255))
		torchButton.background = circle(if (torchOn) Color.argb(170, 60, 50, 10) else Color.argb(140, 0, 0, 0),
			if (torchOn) Color.rgb(255, 220, 90) else Color.argb(200, 255, 255, 255), 1.5f)
	}

	private fun applyAutoLook() {
		autoButton.setTextColor(if (autoShoot) Color.rgb(120, 255, 150) else Color.argb(150, 255, 255, 255))
		autoButton.background = circle(if (autoShoot) Color.argb(170, 10, 60, 25) else Color.argb(140, 0, 0, 0),
			if (autoShoot) Color.rgb(120, 255, 150) else Color.argb(200, 255, 255, 255), 1.5f)
	}

	// ── Live guidance ────────────────────────────────────────────────────────

	// The dial reader's marker colour (DialReader._is_violet_loose): the violet diamond, blue well
	// above green, red a bit above green; the card art has almost no violet.
	private fun violet(r: Int, g: Int, b: Int): Boolean =
		b * 100 > g * 118 && r * 100 > g * 103 && b * 100 >= r * 65 && b - g > 10

	private fun analyze(image: ImageProxy) {
		try {
			val now = SystemClock.elapsedRealtime()
			if (busy || now - lastAnalysis < 120) return
			lastAnalysis = now
			val plane = image.planes[0]
			val buf = plane.buffer
			val rowStride = plane.rowStride
			val px = plane.pixelStride
			val w = image.width
			val h = image.height
			buf.rewind()
			if (analysisBytes.size < buf.remaining()) analysisBytes = ByteArray(buf.remaining())
			buf.get(analysisBytes, 0, buf.remaining())
			val data = analysisBytes
			if (analysisSeen.size < w * h) analysisSeen = ByteArray(w * h) else java.util.Arrays.fill(analysisSeen, 0, w * h, 0)
			val seen = analysisSeen
			fun isV(x: Int, y: Int): Boolean {
				val o = y * rowStride + x * px
				return violet(data[o].toInt() and 255, data[o + 1].toInt() and 255, data[o + 2].toInt() and 255)
			}
			val blobs = ArrayList<FloatArray>()      // x, y (analysis px, upright later), area
			var y = 0
			while (y < h) {
				for (x in 0 until w) {
					val i = y * w + x
					if (seen[i].toInt() != 0 || !isV(x, y)) continue
					var sp = 0
					stack[sp++] = i
					seen[i] = 1
					var count = 0
					var sx = 0f
					var sy = 0f
					var minX = x
					var maxX = x
					var minY = y
					var maxY = y
					while (sp > 0) {
						val p = stack[--sp]
						val qx = p % w
						val qy = p / w
						count++
						sx += qx
						sy += qy
						minX = min(minX, qx); maxX = max(maxX, qx); minY = min(minY, qy); maxY = max(maxY, qy)
						// a big violet patch is flooded whole (and dropped below): stopping early left
						// pieces of it behind that counted as diamonds
						for (n in intArrayOf(p - 1, p + 1, p - w, p + w)) {
							if (n < 0 || n >= w * h || seen[n].toInt() != 0) continue
							if ((n == p - 1 && qx == 0) || (n == p + 1 && qx == w - 1)) continue
							if (isV(n % w, n / w)) {
								seen[n] = 1
								if (sp >= stack.size) stack = stack.copyOf(stack.size * 2)
								stack[sp++] = n
							}
						}
					}
					val bw = maxX - minX + 1
					val bh = maxY - minY + 1
					if (count < 2 || count > 900 || max(bw, bh) > 2.5f * min(bw, bh)) continue
					blobs.add(floatArrayOf(sx / count, sy / count, count.toFloat()))
				}
				y += 2
			}
			// px per mm in the photo from each diamond's area (the kite is ~2.2 mm^2; blur and the
			// colour test take a little off, hence 1.8)
			val f = captureLong.toFloat() / max(w, h)
			val scales = blobs.map { sqrt(it[2] / 1.8f) * f }
			// the stray violet speck of a busy card is far smaller than the diamonds: judge by the
			// bigger half
			val sorted = scales.sorted()
			val good = scales.count { it >= GOOD_PX_PER_MM }
			val typical = if (sorted.isEmpty()) 0f else sorted[(sorted.size * 3) / 4]
			val rot = image.imageInfo.rotationDegrees
			val pts = FloatArray(blobs.size * 3)
			for ((k, b) in blobs.withIndex()) {
				// upright (as shown) coordinates in 0..1
				val (ux, uy) = when (rot) {
					90 -> Pair((h - b[1]) / h, b[0] / w)
					180 -> Pair((w - b[0]) / w, (h - b[1]) / h)
					270 -> Pair(b[1] / h, (w - b[0]) / w)
					else -> Pair(b[0] / w, b[1] / h)
				}
				pts[k * 3] = ux
				pts[k * 3 + 1] = uy
				pts[k * 3 + 2] = if (scales[k] >= GOOD_PX_PER_MM) 1f else 0f
			}
			val upright = if (rot == 90 || rot == 270) Pair(h, w) else Pair(w, h)
			// how far the picture would smear right now: the fastest turn of the last 0.4 s x
			// exposure time x focal length in pixels
			val omega = synchronized(gyro) { gyro.maxOfOrNull { it.second } ?: 0f }
			val t = if (exposureNs > 0) exposureNs / 1e9f else 1f / 60f
			val fpx = if (focalPx > 0f) focalPx else captureLong * 0.8f
			val smear = omega * t * fpx
			val hasGyro = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null
			runOnUiThread { guide(pts, upright, blobs.size, good, typical, smear, hasGyro) }
		} catch (e: Exception) {
			// guidance is a help only: never let it break the camera
		} finally {
			image.close()
		}
	}

	private fun guide(pts: FloatArray, upright: Pair<Int, Int>, n: Int, good: Int, typical: Float, smear: Float, hasGyro: Boolean) {
		if (busy || isFinishing) return
		overlay.show(pts, upright, previewView.width, previewView.height)
		val now = SystemClock.elapsedRealtime()
		val steady = !hasGyro || smear < MAX_SMEAR_PX
		// the live figures, for tuning on real phones: diamonds seen (big enough), px per mm, smear px
		status.text = "%s · %d (%d) · %.1f px/mm · %.1f px".format(statusBase, n, good, typical, smear)
		val text: String
		var ready = false
		when {
			n == 0 -> text = guideTexts[0]
			good < READY_DIAMONDS || typical < GOOD_PX_PER_MM -> text = guideTexts[1]
			!steady -> text = guideTexts[2]
			else -> {
				text = if (autoShoot) guideTexts[3] else guideTexts[2]
				ready = true
			}
		}
		guideLabel.text = text
		guideLabel.visibility = if (now - openedAt > 600) View.VISIBLE else View.INVISIBLE
		guideLabel.setTextColor(if (ready) Color.rgb(140, 255, 160) else Color.WHITE)
		if (!ready) {
			readySince = 0L
			overlay.progress = 0f
			return
		}
		if (readySince == 0L) readySince = now
		val held = now - readySince
		overlay.progress = if (autoShoot) min(1f, held.toFloat() / READY_MS) else 0f
		overlay.shutterAt = floatArrayOf(shutter.x + shutter.width / 2f, shutter.y + shutter.height / 2f, shutter.width / 2f + dp(6f))
		overlay.invalidate()
		// never straight away: a moment to frame the ship after the screen opens
		if (autoShoot && held >= READY_MS && now - openedAt > 1800 && torchDecided) {
			shoot(auto = true)
		}
	}

	// Rings round the diamonds seen (green: big enough to read; yellow: too small) and the auto
	// shot's countdown round the shutter.
	private class GuideOverlay(context: Context) : View(context) {
		private var pts = FloatArray(0)
		private var rect = RectF()
		var progress = 0f
		var shutterAt = FloatArray(0)
		private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
		private val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
			style = Paint.Style.STROKE
			color = Color.rgb(140, 255, 160)
			strokeCap = Paint.Cap.ROUND
		}

		fun show(p: FloatArray, upright: Pair<Int, Int>, vw: Int, vh: Int) {
			pts = p
			// the preview is letterboxed (FIT_CENTER) at the same 4:3 as the analysed copy
			val s = min(vw.toFloat() / upright.first, vh.toFloat() / upright.second)
			val dw = upright.first * s
			val dh = upright.second * s
			rect = RectF((vw - dw) / 2f, (vh - dh) / 2f, (vw + dw) / 2f, (vh + dh) / 2f)
			invalidate()
		}

		override fun onDraw(canvas: Canvas) {
			super.onDraw(canvas)
			val d = resources.displayMetrics.density
			ring.strokeWidth = 2.2f * d
			var k = 0
			while (k + 2 < pts.size) {
				ring.color = if (pts[k + 2] > 0f) Color.argb(230, 120, 255, 150) else Color.argb(230, 255, 210, 80)
				canvas.drawCircle(rect.left + pts[k] * rect.width(), rect.top + pts[k + 1] * rect.height(), 9f * d, ring)
				k += 3
			}
			if (progress > 0f && shutterAt.size == 3) {
				arc.strokeWidth = 4f * d
				val r = shutterAt[2]
				canvas.drawArc(RectF(shutterAt[0] - r, shutterAt[1] - r, shutterAt[0] + r, shutterAt[1] + r), -90f, 360f * progress, false, arc)
			}
		}
	}

	// ── Taking the photo ─────────────────────────────────────────────────────

	private fun shoot(auto: Boolean = false) {
		val capture = imageCapture ?: return
		if (busy) {
			return
		}
		val path = intent.getStringExtra(EXTRA_OUTPUT_PATH) ?: return finishWith(Activity.RESULT_CANCELED)
		busy = true
		lastShotAuto = auto
		shutter.alpha = 0.4f
		overlay.progress = 0f
		overlay.show(FloatArray(0), Pair(4, 3), previewView.width, previewView.height)
		guideLabel.visibility = View.INVISIBLE
		val out = File(path)
		out.parentFile?.mkdirs()
		// focus and expose on the middle first; shoot when that's done (or after a second at most)
		val control = camera?.cameraControl
		if (control == null) {
			capture(capture, out)
			return
		}
		val centre = previewView.meteringPointFactory.createPoint(previewView.width / 2f, previewView.height / 2f)
		val action = FocusMeteringAction.Builder(centre, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
			.setAutoCancelDuration(3, TimeUnit.SECONDS).build()
		var started = false
		val go = {
			if (!started) {
				started = true
				capture(capture, out)
			}
		}
		val focus = control.startFocusAndMetering(action)
		focus.addListener({ go() }, ContextCompat.getMainExecutor(this))
		previewView.postDelayed({ go() }, 1000)
	}

	// The phone's multi-frame mode: one capture. Otherwise BURST captures: the sharpest one is the
	// photo, the others stay next to it as <name>_alt1.jpg, <name>_alt2.jpg for the game's second look.
	private fun capture(capture: ImageCapture, out: File) {
		if (extensionName.isNotEmpty()) {
			takeOne(capture, out) { ok -> if (ok) done(out) else failed() }
			return
		}
		val shots = (0 until BURST).map { File(out.parentFile, "burst_${it}_" + out.name) }
		fun next(i: Int) {
			if (isFinishing) {
				shots.forEach { it.delete() }      // closed mid-burst: nothing to keep
				return
			}
			if (i < shots.size) {
				takeOne(capture, shots[i]) { next(i + 1) }
				return
			}
			// sharpest first (each score decodes a JPEG: once per shot), then the shots are MOVED into
			// place — same folder, so no extra space and nothing half-written. This runs in CameraX's
			// callback on the main thread, where an exception ends the whole game: copying three JPEGs
			// on a nearly full phone threw (review 2026-11-01), so nothing here may throw.
			val ranked = try {
				shots.filter { it.exists() }.map { it to sharpness(it) }.sortedByDescending { it.second }.map { it.first }
			} catch (e: Throwable) {      // Throwable: an OutOfMemoryError while decoding ends the game too
				shots.filter { it.exists() }
			}
			var ok = false
			try {
				if (ranked.isNotEmpty()) {
					out.delete()
					ok = ranked[0].renameTo(out)
					if (!ok) {
						ranked[0].copyTo(out, overwrite = true)
						ok = true
					}
				}
			} catch (e: Throwable) {
				ok = false
				out.delete()
			}
			if (ok) {
				for ((k, f) in ranked.drop(1).withIndex()) {
					try {
						val alt = File(out.parentFile, out.nameWithoutExtension + "_alt${k + 1}.jpg")
						alt.delete()
						f.renameTo(alt)
					} catch (e: Exception) {
						// the other shots are a bonus only
					}
				}
			}
			shots.forEach { it.delete() }
			if (ok) done(out) else failed()
		}
		next(0)
	}

	private fun takeOne(capture: ImageCapture, file: File, then: (Boolean) -> Unit) {
		capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(this),
			object : ImageCapture.OnImageSavedCallback {
				override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) = then(true)
				override fun onError(exception: ImageCaptureException) = then(false)
			})
	}

	// Sharpness of a photo: mean squared Laplacian of the luminance over the middle half, on a
	// quarter-size decode (enough to tell a shaken or misfocused shot from a sharp one).
	private fun sharpness(file: File): Double {
		val opts = BitmapFactory.Options().apply { inSampleSize = 4 }
		val bmp = BitmapFactory.decodeFile(file.absolutePath, opts) ?: return -1.0
		val w = bmp.width
		val h = bmp.height
		val x0 = w / 4
		val y0 = h / 4
		val cw = w / 2
		val ch = h / 2
		val px = IntArray(cw * ch)
		bmp.getPixels(px, 0, cw, x0, y0, cw, ch)
		bmp.recycle()
		val lum = IntArray(px.size) { val c = px[it]; ((c shr 16 and 255) * 77 + (c shr 8 and 255) * 150 + (c and 255) * 29) shr 8 }
		var sum = 0.0
		for (y in 1 until ch - 1) {
			for (x in 1 until cw - 1) {
				val i = y * cw + x
				val l = 4 * lum[i] - lum[i - 1] - lum[i + 1] - lum[i - cw] - lum[i + cw]
				sum += (l * l).toDouble()
			}
		}
		return sum / ((cw - 2) * (ch - 2))
	}

	private fun done(out: File) {
		setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_OUTPUT_PATH, out.absolutePath))
		finish()
	}

	private fun failed() {
		busy = false
		readySince = 0L
		shutter.alpha = 1f
		if (lastShotAuto && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
			// a failed automatic shot would only fail again and again: AUTO off for now (not saved),
			// the shutter is still there (not when the shots failed because the player left the app)
			autoShoot = false
			applyAutoLook()
		}
	}

	private fun finishWith(result: Int) {
		setResult(result)
		finish()
	}
}
