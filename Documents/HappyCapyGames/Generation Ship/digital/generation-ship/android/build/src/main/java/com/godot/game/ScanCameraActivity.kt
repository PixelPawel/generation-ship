package com.godot.game

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
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
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
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
// 2026-11-01, after the first real tests with it:
//  - rings only round what really is a diamond (see analyzeFrame), all green; the guidance
//    counts and sizes those only
//  - the phone's own night mode where its maker offers it to apps (CameraX Extensions NIGHT;
//    with CameraX 1.6 that's the framework's Camera2 Extensions, Android 13+; Google's list of
//    phones with extensions has most recent Samsung, Pixel, Xiaomi, Honor, OPPO, OnePlus, vivo):
//    several frames merged, aligned and denoised. The camera app's night photo of a real ship
//    read 14 of 15 dials, this screen's plain photo of the same ship 9. One capture (no burst),
//    no automatic torch, no EV offset (that night photo was at 0 EV). CameraX 1.6 never streams
//    the guidance's small copy next to it: the guidance reads the preview off the screen. A night
//    picture that doesn't start, a night photo under 3000 px or a failed night shot switch to the
//    plain camera, and the night mode turns itself off on a phone where it fails (see nightAllowed).
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
	private lateinit var hint: TextView            // the line on top (the dim-room tip replaces it)
	private var imageCapture: ImageCapture? = null
	private var camera: Camera? = null
	private var provider: ProcessCameraProvider? = null
	private var previewUseCase: Preview? = null
	private var guideFromPreview = false     // the guidance reads the preview off the screen (no small copy streamed)
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
	private var readySince = 0L              // steady since (0: not steady)
	private var sizeOkAt = 0L                // the ship last seen framed close enough
	private var sizeOkSince = 0L             // ...continuously since (0: not)
	private var calmest = Float.MAX_VALUE    // the lowest smear since then
	private var oisFactor = 1f               // OIS_FACTOR where the lens has optical stabilisation
	private var lastAnalysis = 0L
	private var analysisBytes = ByteArray(0)
	private var analysisSeen = ByteArray(0)
	private var stack = IntArray(4096)
	private val analysing = AtomicBoolean(false)   // a preview picture is being analysed
	private var previewBytes = ByteArray(0)

	// Diamonds read as big enough above this many px per mm (the reader reads 3000 px photos of a
	// whole ship, ~7 px/mm, fine; ~5 px/mm loses the tech lights), and the photo is good to take
	// with at least READY_DIAMONDS of them, the picture smearing less than MAX_SMEAR_PX for READY_MS.
	// The estimate from a diamond's area is rough: on the real photos of 2026-10 it came out 1.1-1.4x
	// the true px/mm for the final borderless diamond, 0.4-0.8x for the old pale and blurry prints
	// (those photos were 12-18 px/mm; a 6-sector ship filling the frame is ~7.5-8).
	private val GOOD_PX_PER_MM = 7.5f
	private val READY_DIAMONDS = 2
	// 2026-11-02, AUTO never fired for the developer holding the phone as still as humanly possible: the
	// smear was the FASTEST turn of 0.4 s with no allowance for the lens's stabiliser, against
	// 1.2 px (= under 0.7 deg/s at a lamp-lit 1/30 s; the screenshots showed 15-19 px, the photos
	// still read fine). Now: the RMS turn of the last 0.3 s, a third of it where the lens has
	// optical stabilisation, against 3 px; and once the ship has been framed close enough for
	// CALM_WAIT_MS, AUTO takes the calmest moment anyway, at twice that whatever the shake (the
	// burst keeps the sharpest shot).
	private val MAX_SMEAR_PX = 3.0f
	private val READY_MS = 700L
	private val CALM_WAIT_MS = 2500L
	private val OIS_FACTOR = 3f
	// the torch comes on where exposure time (s) x ISO is above this (bright room ~1-2, lamp-lit
	// evening ~10-30) — or, without exposure figures, below DIM_LUX on the light sensor
	private val DIM_EXPOSURE = 8.0f
	private val DIM_LUX = 60f
	private val MIN_CAPTURE_LONG = 3000       // px: below this the reader loses the tech lights on a whole ship
	private val PREVIEW_GUIDE_MS = 250L       // reading the preview off the screen 4 times a second (each read costs the main thread ~10-20 ms)

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
		if (guideFromPreview) {
			previewView.removeCallbacks(previewGuide)
			previewView.postDelayed(previewGuide, 300)
		}
	}

	override fun onPause() {
		super.onPause()
		sensorManager?.unregisterListener(this)
		previewView.removeCallbacks(previewGuide)     // reading the screen costs: only while it's shown
	}

	override fun onDestroy() {
		super.onDestroy()
		previewView.removeCallbacks(previewGuide)
		previewView.removeCallbacks(nightWatch)
		nightTrying(false)                            // closed normally: the night mode didn't take the game down
		analysisExecutor.shutdown()
	}

	override fun onSensorChanged(event: SensorEvent) {
		when (event.sensor.type) {
			Sensor.TYPE_GYROSCOPE -> {
				val v = event.values
				val now = SystemClock.elapsedRealtime()
				synchronized(gyro) {
					gyro.addLast(Pair(now, sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])))
					while (gyro.isNotEmpty() && now - gyro.first().first > 300) gyro.removeFirst()
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

		hint = TextView(this)
		hint.text = intent.getStringExtra(EXTRA_HINT) ?: ""
		hint.setTextColor(Color.WHITE)
		hint.textSize = 16f
		hint.gravity = Gravity.CENTER
		hint.setShadowLayer(6f, 0f, 0f, Color.BLACK)
		hint.setPadding(dp(16f), dp(6f), dp(16f), dp(6f))
		// clear of the close and torch buttons in the corners when it wraps (the dim-room tip is long)
		root.addView(hint, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
			Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
			topMargin = dp(12f)
			marginStart = dp(84f)
			marginEnd = dp(100f)
		})

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
			sizeOkSince = 0L
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
				this.provider = provider
				// the phone's own night mode, if its maker offers it to apps (several frames merged by
				// the camera's processing, aligned and denoised); otherwise a plain capture + our burst
				val extFuture = ExtensionsManager.getInstanceAsync(this, provider)
				extFuture.addListener({
					var night: CameraSelector? = null
					var nightAnalysis = false
					try {
						val ext = extFuture.get()
						if (nightAllowed() && ext.isExtensionAvailable(CameraSelector.DEFAULT_BACK_CAMERA, ExtensionMode.NIGHT)) {
							night = ext.getExtensionEnabledCameraSelector(CameraSelector.DEFAULT_BACK_CAMERA, ExtensionMode.NIGHT)
							nightAnalysis = ext.isImageAnalysisSupported(CameraSelector.DEFAULT_BACK_CAMERA, ExtensionMode.NIGHT)
						}
					} catch (e: Throwable) {      // Throwable: the phone maker's code runs here, an Error would end the game
						night = null
					}
					bindCamera(provider, night, nightAnalysis)
				}, ContextCompat.getMainExecutor(this))
			} catch (e: Throwable) {
				finishWith(RESULT_FALLBACK)
			}
		}, ContextCompat.getMainExecutor(this))
	}

	// The night mode runs the phone maker's code inside the game. A night attempt that never came
	// back (the game died while binding, streaming or shooting with it), a night picture that never
	// started, or two failed night shots turn it off on this phone until the next app version.
	private val prefs by lazy { getSharedPreferences(PREFS, Context.MODE_PRIVATE) }

	private fun appVersion(): Long = try {
		PackageInfoCompat.getLongVersionCode(packageManager.getPackageInfo(packageName, 0))
	} catch (e: Throwable) {
		0L
	}

	private fun nightAllowed(): Boolean {
		val v = appVersion()
		if (prefs.getBoolean("night_trying", false)) {
			prefs.edit().putBoolean("night_trying", false).putLong("night_off", v).commit()
		}
		return prefs.getLong("night_off", -1L) != v
	}

	private fun nightTrying(on: Boolean) {
		try {
			val e = prefs.edit().putBoolean("night_trying", on)
			if (on) e.commit() else e.apply()    // commit: a crash may follow at once
		} catch (e: Throwable) {
		}
	}

	// the night mode failed on this phone: the plain camera and the burst from now on (offNow: for
	// good on this app version; else after the second failed night shot)
	private fun nightFailed(offNow: Boolean) {
		try {
			val v = appVersion()
			val fails = (if (prefs.getLong("night_fails_v", -1L) == v) prefs.getInt("night_fails", 0) else 0) + 1
			val e = prefs.edit().putBoolean("night_trying", false).putLong("night_fails_v", v).putInt("night_fails", fails)
			if (offNow || fails >= 2) e.putLong("night_off", v)
			e.apply()
		} catch (e: Throwable) {
		}
		val p = provider ?: return
		if (isFinishing || isDestroyed) return
		bindCamera(p, null, false)
	}

	// a night picture that hasn't started streaming a few seconds after binding (the phone's night
	// session failed to configure: a black screen otherwise)
	private val nightWatch = object : Runnable {
		override fun run() {
			if (isFinishing || isDestroyed || extensionName.isEmpty()) return
			if (busy || !lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
				previewView.postDelayed(this, 1500)
				return
			}
			if (previewView.previewStreamState.value == PreviewView.StreamState.STREAMING) {
				nightTrying(false)
			} else {
				nightFailed(offNow = true)
			}
		}
	}

	// One way of running the camera: which selector (night mode or plain), and whether the
	// guidance gets its own small copy of the picture (else it reads the preview off the screen).
	private class Setup(val selector: CameraSelector, val night: Boolean, val analysis: Boolean)

	@OptIn(ExperimentalCamera2Interop::class)
	private fun bindCamera(provider: ProcessCameraProvider, night: CameraSelector?, nightAnalysis: Boolean) {
		if (isFinishing || isDestroyed) return     // closed while CameraX was starting
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
			// the night mode runs the phone's own capture session: nothing of ours hooked into it
			// (without the figures the smear check assumes 1/60 s)
			val nightPreview = Preview.Builder()
				.setResolutionSelector(ResolutionSelector.Builder()
					.setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY).build())
				.build()
			nightPreview.setSurfaceProvider(previewView.surfaceProvider)
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
			// best first: the night mode with the guidance's own small copy (CameraX 1.6.2 never allows
			// that with the framework's night mode; kept for a later CameraX), the night mode with the
			// guidance reading the preview, then the plain camera the same two ways
			val setups = ArrayList<Setup>()
			if (night != null) {
				if (nightAnalysis) setups.add(Setup(night, night = true, analysis = true))
				setups.add(Setup(night, night = true, analysis = false))
			}
			setups.add(Setup(CameraSelector.DEFAULT_BACK_CAMERA, night = false, analysis = true))
			setups.add(Setup(CameraSelector.DEFAULT_BACK_CAMERA, night = false, analysis = false))
			fun previewOf(s: Setup): Preview = if (s.night) nightPreview else preview
			fun useCases(s: Setup): List<UseCase> = if (s.analysis) listOf(previewOf(s), capture, analysis) else listOf(previewOf(s), capture)
			fun longSide(): Int = capture.resolutionInfo?.resolution?.let { max(it.width, it.height) } ?: 0
			var chosen = setups.last()
			if (night != null) nightTrying(true)
			camera = bindFirst(provider, setups.map { Pair(it.selector, useCases(it)) }) { i -> chosen = setups[i] }
			// the small copy must not cost the photo its resolution (a phone that can't stream three
			// sizes at once may lower the capture): then the guidance reads the preview instead
			if (chosen.analysis && longSide() in 1 until MIN_CAPTURE_LONG) {
				val rest = setups.filter { !it.analysis && (chosen.night || !it.night) }
				camera = bindFirst(provider, rest.map { Pair(it.selector, useCases(it)) }) { i -> chosen = rest[i] }
			}
			// a night mode that only takes small photos loses the tech lights: the plain camera then
			if (chosen.night && longSide() in 1 until MIN_CAPTURE_LONG) {
				val plain = setups.filter { !it.night }
				camera = bindFirst(provider, plain.map { Pair(it.selector, useCases(it)) }) { i -> chosen = plain[i] }
				if (chosen.analysis && longSide() in 1 until MIN_CAPTURE_LONG) {
					val rest = plain.filter { !it.analysis }
					camera = bindFirst(provider, rest.map { Pair(it.selector, useCases(it)) }) { i -> chosen = rest[i] }
				}
			}
			extensionName = if (chosen.night) "Night" else ""
			previewView.removeCallbacks(nightWatch)
			if (chosen.night) previewView.postDelayed(nightWatch, 4000) else nightTrying(false)
			previewUseCase = previewOf(chosen)
			imageCapture = capture
			capture.resolutionInfo?.resolution?.let { captureLong = max(it.width, it.height) }
			focalPx = focalLengthPx()
			oisFactor = if (hasOis()) OIS_FACTOR else 1f
			// worked out again on every binding (a night mode may not allow the flash, the plain camera
			// after it does): the button where there is a torch to switch; the torch decided by itself
			// on the plain camera only (the night mode copes with dim light, the torch's spot only
			// costs) and never over a choice made by hand
			val hasFlash = camera?.cameraInfo?.hasFlashUnit() == true
			torchButton.visibility = if (hasFlash) View.VISIBLE else View.GONE
			torchDecided = torchByHand || !hasFlash || chosen.night
			applyTorch()
			val ev = applyExposure()
			statusBase = (if (extensionName.isEmpty()) "Burst $BURST" else extensionName) +
				(if (ev != 0f) " · %+.1f EV".format(ev) else "") +
				(capture.resolutionInfo?.resolution?.let { " · ${it.width}×${it.height}" } ?: "") +
				(if (chosen.analysis) "" else " · preview guide")
			status.text = statusBase
			guideFromPreview = !chosen.analysis
			previewView.removeCallbacks(previewGuide)
			if (guideFromPreview) previewView.postDelayed(previewGuide, 300)
			if (torchDecided) return
			// decide the torch once the exposure has settled
			previewView.postDelayed({ decideTorch() }, 1300)
		} catch (e: Throwable) {
			finishWith(RESULT_FALLBACK)
		}
	}

	private fun bindFirst(provider: ProcessCameraProvider, tries: List<Pair<CameraSelector, List<UseCase>>>, chose: (Int) -> Unit): Camera {
		var last: Throwable? = null
		for ((i, t) in tries.withIndex()) {
			try {
				provider.unbindAll()
				val cam = provider.bindToLifecycle(this, t.first, *t.second.toTypedArray())
				chose(i)
				return cam
			} catch (e: Throwable) {      // a night setup failing with an Error (maker code) still tries the plain camera
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
		} catch (e: Throwable) {
			0f
		}
	}

	@OptIn(ExperimentalCamera2Interop::class)
	private fun hasOis(): Boolean {
		return try {
			val modes = Camera2CameraInfo.from(camera!!.cameraInfo)
				.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION)
			modes?.contains(CameraCharacteristics.LENS_OPTICAL_STABILIZATION_MODE_ON) == true
		} catch (e: Throwable) {
			false
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
		// dim: the phone's own camera in its Night mode takes a far clearer photo (the game's
		// From Gallery button reads it) — say so where it matters (5th guide line, if the game sent it)
		if (dim && guideTexts.size >= 5) hint.text = guideTexts[4]
		status.text = statusBase
	}

	// darker by EXPOSURE_EV where the camera allows exposure compensation; returns what was set.
	// Not in the night mode: it sets its own exposure (the camera app's night photo was at 0 EV)
	private fun applyExposure(): Float {
		if (extensionName.isNotEmpty()) return 0f
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

	// ...and its strict one (DialReader._is_violet)
	private fun strictViolet(r: Int, g: Int, b: Int): Boolean =
		b * 100 > g * 127 && r * 100 > g * 108 && b * 100 >= r * 75 && b - g > 14

	private fun analyze(image: ImageProxy) {
		try {
			val now = SystemClock.elapsedRealtime()
			if (busy || now - lastAnalysis < 120) return
			lastAnalysis = now
			val plane = image.planes[0]
			val buf = plane.buffer
			buf.rewind()
			if (analysisBytes.size < buf.remaining()) analysisBytes = ByteArray(buf.remaining())
			buf.get(analysisBytes, 0, buf.remaining())
			analyzeFrame(analysisBytes, image.width, image.height, plane.rowStride, plane.pixelStride, image.imageInfo.rotationDegrees)
		} catch (e: Exception) {
			// guidance is a help only: never let it break the camera
		} finally {
			image.close()
		}
	}

	// Without the small copy (the night mode on most phones): the preview as shown on screen, a few
	// times a second — the 4:3 picture inside the letterboxed view, scaled to the small copy's size
	// so the same figures hold.
	private val previewGuide = object : Runnable {
		override fun run() {
			// stops while the screen is away (onResume starts it again)
			if (isFinishing || isDestroyed || !guideFromPreview || !lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return
			grabPreview()
			previewView.postDelayed(this, PREVIEW_GUIDE_MS)
		}
	}

	private fun grabPreview() {
		if (busy || !analysing.compareAndSet(false, true)) return
		var handedOver = false
		try {
			val info = previewUseCase?.resolutionInfo ?: return
			val turned = info.rotationDegrees % 180 != 0
			val uw = if (turned) info.cropRect.height() else info.cropRect.width()
			val uh = if (turned) info.cropRect.width() else info.cropRect.height()
			if (uw <= 0 || uh <= 0) return
			val full = previewView.bitmap ?: return
			val s = min(full.width.toFloat() / uw, full.height.toFloat() / uh)
			val dw = (uw * s).toInt().coerceIn(1, full.width)
			val dh = (uh * s).toInt().coerceIn(1, full.height)
			val left = (full.width - dw) / 2
			val top = (full.height - dh) / 2
			analysisExecutor.execute {
				try {
					val tw = if (dw >= dh) 1440 else (1440f * dw / dh).roundToInt()
					val th = if (dw >= dh) (1440f * dh / dw).roundToInt() else 1440
					val part = Bitmap.createBitmap(full, left, top, dw, dh)
					val small = Bitmap.createScaledBitmap(part, tw, th, true)
					val rowBytes = small.rowBytes
					if (previewBytes.size < small.byteCount) previewBytes = ByteArray(small.byteCount)
					small.copyPixelsToBuffer(ByteBuffer.wrap(previewBytes))   // ARGB_8888: R, G, B, A in memory
					if (small !== part) small.recycle()
					if (part !== full) part.recycle()
					full.recycle()
					analyzeFrame(previewBytes, tw, th, rowBytes, 4, 0)
				} catch (e: Throwable) {
					// a help only
				} finally {
					analysing.set(false)
				}
			}
			handedOver = true
		} catch (e: Throwable) {
			// a help only
		} finally {
			if (!handedOver) analysing.set(false)
		}
	}

	// The violet diamonds in one small picture of the live view, for the rings and the guidance.
	// Not every violet speck is a diamond: busy card art (pink text panels, magenta tints) gave
	// hundreds of rings, and its specks dragged the size estimate down to "Move closer" (first
	// real tests, 2026-11-01). Labelled by the dials the reader found on 14 real photos of
	// 2026-10/11, a diamond
	//  - is truly violet somewhere (2+ pixels pass the reader's strict test),
	//  - stands alone: at most one other violet speck within 5 of its own mm (the dial's lights
	//    are cream or dark; the art's specks come in crowds),
	//  - is set off from its surround: under 45 % of the ring round it magenta-ish, and its middle
	//    bluer than that ring (b - g) by 15 or more,
	//  - is not tiny next to the others (at least 0.3 x the typical diamond's area).
	// That kept 101 of the 121 diamonds and ~6 specks a photo (from ~430).
	private fun analyzeFrame(data: ByteArray, w: Int, h: Int, rowStride: Int, px: Int, rot: Int) {
		if (analysisSeen.size < w * h) analysisSeen = ByteArray(w * h) else java.util.Arrays.fill(analysisSeen, 0, w * h, 0)
		val seen = analysisSeen
		fun isV(x: Int, y: Int): Boolean {
			val o = y * rowStride + x * px
			return violet(data[o].toInt() and 255, data[o + 1].toInt() and 255, data[o + 2].toInt() and 255)
		}
		val blobs = ArrayList<FloatArray>()      // x, y (analysis px, upright later), area, strictly violet px
		var y = 0
		while (y < h) {
			for (x in 0 until w) {
				val i = y * w + x
				if (seen[i].toInt() != 0 || !isV(x, y)) continue
				var sp = 0
				stack[sp++] = i
				seen[i] = 1
				var count = 0
				var strict = 0
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
					val o = qy * rowStride + qx * px
					if (strictViolet(data[o].toInt() and 255, data[o + 1].toInt() and 255, data[o + 2].toInt() and 255)) strict++
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
				blobs.add(floatArrayOf(sx / count, sy / count, count.toFloat(), strict.toFloat()))
			}
			y += 2
		}
		val found = ArrayList<FloatArray>()
		for (b in blobs) {
			if (b[2] < 3f || b[3] < 2f) continue
			val reach = 5f * max(1f, sqrt(b[2] / 1.8f))     // 5 mm if this is a diamond
			var crowd = 0
			for (o in blobs) {
				if (o === b) continue
				val dx = o[0] - b[0]
				val dy = o[1] - b[1]
				if (dx * dx + dy * dy < reach * reach && ++crowd > 1) break
			}
			if (crowd <= 1 && setOff(data, w, h, rowStride, px, b)) found.add(b)
		}
		val areas = found.map { it[2] }.sorted()
		val typicalArea = if (areas.isEmpty()) 0f else areas[min(areas.size - 1, (areas.size * 3) / 4)]
		val diamonds = found.filter { it[2] >= 0.3f * typicalArea }
		// px per mm in the photo from each diamond's area (the kite is ~2.2 mm^2; blur and the
		// colour test take a little off, hence 1.8)
		val f = captureLong.toFloat() / max(w, h)
		val scales = diamonds.map { sqrt(it[2] / 1.8f) * f }
		// a far, blurred diamond reads smaller than it is: judge by the bigger ones
		val sorted = scales.sorted()
		val good = scales.count { it >= GOOD_PX_PER_MM }
		val typical = if (sorted.isEmpty()) 0f else sorted[(sorted.size * 3) / 4]
		val pts = FloatArray(diamonds.size * 2)
		for ((k, b) in diamonds.withIndex()) {
			// upright (as shown) coordinates in 0..1
			val (ux, uy) = when (rot) {
				90 -> Pair((h - b[1]) / h, b[0] / w)
				180 -> Pair((w - b[0]) / w, (h - b[1]) / h)
				270 -> Pair(b[1] / h, (w - b[0]) / w)
				else -> Pair(b[0] / w, b[1] / h)
			}
			pts[k * 2] = ux
			pts[k * 2 + 1] = uy
		}
		val upright = if (rot == 90 || rot == 270) Pair(h, w) else Pair(w, h)
		// how far the picture would smear right now: the turn of the last 0.3 s (RMS) x exposure
		// time x focal length in pixels, less what the lens's stabiliser takes out
		val omega = synchronized(gyro) { if (gyro.isEmpty()) 0f else sqrt(gyro.sumOf { (it.second * it.second).toDouble() }.toFloat() / gyro.size) }
		val t = if (exposureNs > 0) exposureNs / 1e9f else 1f / 60f
		val fpx = if (focalPx > 0f) focalPx else captureLong * 0.8f
		val smear = omega * t * fpx / oisFactor
		val hasGyro = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null
		runOnUiThread { guide(pts, upright, diamonds.size, good, typical, smear, hasGyro) }
	}

	// A violet blob against its surround (see analyzeFrame): the ring 1.5-3 blob radii out, and
	// the blob's middle.
	private fun setOff(data: ByteArray, w: Int, h: Int, rowStride: Int, px: Int, b: FloatArray): Boolean {
		val rad = sqrt(b[2] / Math.PI.toFloat())
		val r0 = 1.5f * rad + 1f
		val r1 = 3f * rad + 2f
		val rMid = max(1f, 0.8f * rad)
		val x0 = max(0, (b[0] - r1 - 1f).toInt())
		val x1 = min(w, (b[0] + r1 + 2f).toInt())
		val y0 = max(0, (b[1] - r1 - 1f).toInt())
		val y1 = min(h, (b[1] + r1 + 2f).toInt())
		var ring = 0
		var magenta = 0
		var ringBg = 0
		var mid = 0
		var midBg = 0
		for (y in y0 until y1) {
			for (x in x0 until x1) {
				val dx = x - b[0]
				val dy = y - b[1]
				val d = sqrt(dx * dx + dy * dy)
				val inRing = d >= r0 && d <= r1
				val inMid = d <= rMid
				if (!inRing && !inMid) continue
				val o = y * rowStride + x * px
				val r = data[o].toInt() and 255
				val g = data[o + 1].toInt() and 255
				val bl = data[o + 2].toInt() and 255
				if (inRing) {
					ring++
					ringBg += bl - g
					if (bl * 100 > g * 108 && r > g) magenta++
				}
				if (inMid) {
					mid++
					midBg += bl - g
				}
			}
		}
		val ringMean = if (ring > 0) ringBg.toFloat() / ring else 0f
		val midMean = if (mid > 0) midBg.toFloat() / mid else 0f
		return (ring == 0 || magenta < 0.45f * ring) && midMean - max(ringMean, 0f) >= 15f
	}

	private fun guide(pts: FloatArray, upright: Pair<Int, Int>, n: Int, good: Int, typical: Float, smear: Float, hasGyro: Boolean) {
		if (busy || isFinishing) return
		overlay.show(pts, upright, previewView.width, previewView.height)
		val now = SystemClock.elapsedRealtime()
		val steady = !hasGyro || smear < MAX_SMEAR_PX
		// the live figures, for tuning on real phones: diamonds seen (big enough), px per mm, smear px
		status.text = "%s · %d (%d) · %.1f px/mm · %.1f px".format(statusBase, n, good, typical, smear)
		// close enough: a little slack once reached, and a frame that misses a diamond doesn't
		// count for 0.6 s (the estimate flickers around the limit; the preview guide looks 4x a second)
		val slack = if (sizeOkAt > 0L && now - sizeOkAt < 1500) 0.9f else 1f
		if (n > 0 && good >= READY_DIAMONDS && typical >= GOOD_PX_PER_MM * slack) sizeOkAt = now
		val sizeOk = sizeOkAt > 0L && now - sizeOkAt < 600
		if (sizeOk) {
			if (sizeOkSince == 0L) {
				sizeOkSince = now
				calmest = Float.MAX_VALUE
			}
			calmest = min(calmest, smear)
		} else {
			sizeOkSince = 0L
		}
		if (sizeOk && steady) {
			if (readySince == 0L) readySince = now
		} else {
			readySince = 0L
		}
		val held = if (readySince > 0L) now - readySince else 0L
		val waited = if (sizeOkSince > 0L) now - sizeOkSince else 0L
		// nobody holds a phone perfectly still: after CALM_WAIT_MS framed, the calmest moment will do
		val fire = sizeOk && (held >= READY_MS || (waited >= CALM_WAIT_MS && smear <= calmest * 1.25f) || waited >= 2 * CALM_WAIT_MS)
		val text = when {
			n == 0 && !sizeOk -> guideTexts[0]
			!sizeOk -> guideTexts[1]
			steady || fire -> if (autoShoot) guideTexts[3] else guideTexts[2]
			else -> guideTexts[2]
		}
		val ready = sizeOk && (steady || fire)
		guideLabel.text = text
		guideLabel.visibility = if (now - openedAt > 600) View.VISIBLE else View.INVISIBLE
		guideLabel.setTextColor(if (ready) Color.rgb(140, 255, 160) else Color.WHITE)
		// the arc round the shutter: the steady hold, or the wait for the calmest moment
		overlay.progress = if (autoShoot && sizeOk) max(min(1f, held.toFloat() / READY_MS), min(1f, waited.toFloat() / CALM_WAIT_MS)) else 0f
		overlay.shutterAt = floatArrayOf(shutter.x + shutter.width / 2f, shutter.y + shutter.height / 2f, shutter.width / 2f + dp(6f))
		overlay.invalidate()
		// never straight away: a moment to frame the ship after the screen opens
		if (autoShoot && fire && now - openedAt > 1800 && torchDecided && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
			shoot(auto = true)
		}
	}

	// Green rings round the diamonds seen, and round the shutter the auto shot's countdown or a
	// night shot's progress.
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
			ring.color = Color.argb(230, 120, 255, 150)
			var k = 0
			while (k + 1 < pts.size) {
				canvas.drawCircle(rect.left + pts[k] * rect.width(), rect.top + pts[k + 1] * rect.height(), 9f * d, ring)
				k += 2
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
		// hold still until the photo is taken (a night shot takes a few seconds)
		guideLabel.text = guideTexts[3]
		guideLabel.setTextColor(Color.rgb(140, 255, 160))
		guideLabel.visibility = View.VISIBLE
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

	// The phone's night mode: one capture. Otherwise BURST captures: the sharpest one is the
	// photo, the others stay next to it as <name>_alt1.jpg, <name>_alt2.jpg for the game's second look.
	private fun capture(capture: ImageCapture, out: File) {
		if (extensionName.isNotEmpty()) {
			nightTrying(true)
			takeOne(capture, out) { error ->
				nightTrying(false)
				when {
					isFinishing -> out.delete()                // closed during the shot: nothing to keep
					error == null -> done(out)
					else -> {
						out.delete()
						// the night shot itself failed (not the camera taken away by a call or the Home
						// button): the plain camera and the burst from now on; AUTO stays, the next
						// shot is a different kind
						if ((error == ImageCapture.ERROR_CAPTURE_FAILED || error == ImageCapture.ERROR_UNKNOWN) &&
								lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
							nightFailed(offNow = false)
						}
						failed(keepAuto = true)
					}
				}
			}
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

	// then(null) when saved, else then(the ImageCapture error code)
	private fun takeOne(capture: ImageCapture, file: File, then: (Int?) -> Unit) {
		capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(this),
			object : ImageCapture.OnImageSavedCallback {
				override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) = then(null)
				override fun onError(exception: ImageCaptureException) = then(exception.imageCaptureError)
				// a night shot's processing, where the phone reports it: round the shutter
				override fun onCaptureProcessProgressed(progress: Int) {
					overlay.shutterAt = floatArrayOf(shutter.x + shutter.width / 2f, shutter.y + shutter.height / 2f, shutter.width / 2f + dp(6f))
					overlay.progress = progress.coerceIn(1, 100) / 100f
					overlay.invalidate()
				}
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

	private fun failed(keepAuto: Boolean = false) {
		busy = false
		readySince = 0L
		sizeOkSince = 0L
		shutter.alpha = 1f
		overlay.progress = 0f
		overlay.invalidate()
		if (!keepAuto && lastShotAuto && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
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
