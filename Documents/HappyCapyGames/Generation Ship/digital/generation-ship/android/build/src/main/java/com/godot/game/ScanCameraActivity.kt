package com.godot.game

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
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
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import java.io.File

// Scan Tableau's own camera screen (CameraX), replacing the hand-off to the phone's camera
// app: that one decides flash, exposure and focus itself, and in the evening under lamps it
// shot at 1/25 s handheld — blurry dials, unreadable tokens (real photos 2026-10-06). Here the
// TORCH is on from the start (steady light, so a short exposure; the flash stays off, its
// glints on the cards fooled the reader), capture is at the highest 4:3 resolution in quality
// mode, and a tap focuses there. Returns the saved JPEG's path like the old intent did.
// Camera permission refused, no back camera or CameraX failing: RESULT_FALLBACK, and the
// plugin opens the camera app instead.
class ScanCameraActivity : ComponentActivity() {

	companion object {
		const val EXTRA_OUTPUT_PATH = "output_path"
		const val EXTRA_HINT = "hint"
		const val RESULT_FALLBACK = Activity.RESULT_FIRST_USER + 1
	}

	private lateinit var previewView: PreviewView
	private lateinit var shutter: View
	private lateinit var torchButton: TextView
	private var imageCapture: ImageCapture? = null
	private var camera: Camera? = null
	private var torchOn = true
	private var busy = false

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

		val hint = TextView(this)
		hint.text = intent.getStringExtra(EXTRA_HINT) ?: ""
		hint.setTextColor(Color.WHITE)
		hint.textSize = 16f
		hint.gravity = Gravity.CENTER
		hint.setShadowLayer(6f, 0f, 0f, Color.BLACK)
		hint.setPadding(dp(16f), dp(6f), dp(16f), dp(6f))
		root.addView(hint, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
			Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = dp(12f) })

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
			torchOn = !torchOn
			applyTorch()
		}
		root.addView(torchButton, FrameLayout.LayoutParams(dp(52f), dp(52f), Gravity.END or Gravity.TOP).apply {
			marginEnd = dp(40f)
			topMargin = dp(16f)
		})
		applyTorchLook()
		return root
	}

	private fun startCamera() {
		val future = ProcessCameraProvider.getInstance(this)
		future.addListener({
			try {
				val provider = future.get()
				val selector = ResolutionSelector.Builder()
					.setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
					.setResolutionStrategy(ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY)
					.build()
				val preview = Preview.Builder()
					.setResolutionSelector(ResolutionSelector.Builder()
						.setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY).build())
					.build()
				preview.setSurfaceProvider(previewView.surfaceProvider)
				val capture = ImageCapture.Builder()
					.setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
					.setFlashMode(ImageCapture.FLASH_MODE_OFF)
					.setResolutionSelector(selector)
					.build()
				provider.unbindAll()
				camera = provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
				imageCapture = capture
				if (camera?.cameraInfo?.hasFlashUnit() != true) {
					torchButton.visibility = View.GONE
				}
				applyTorch()
			} catch (e: Exception) {
				finishWith(RESULT_FALLBACK)
			}
		}, ContextCompat.getMainExecutor(this))
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

	private fun shoot() {
		val capture = imageCapture ?: return
		if (busy) {
			return
		}
		val path = intent.getStringExtra(EXTRA_OUTPUT_PATH) ?: return finishWith(Activity.RESULT_CANCELED)
		busy = true
		shutter.alpha = 0.4f
		val out = File(path)
		out.parentFile?.mkdirs()
		capture.takePicture(ImageCapture.OutputFileOptions.Builder(out).build(), ContextCompat.getMainExecutor(this),
			object : ImageCapture.OnImageSavedCallback {
				override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
					setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_OUTPUT_PATH, out.absolutePath))
					finish()
				}

				override fun onError(exception: ImageCaptureException) {
					busy = false
					shutter.alpha = 1f
				}
			})
	}

	private fun finishWith(result: Int) {
		setResult(result)
		finish()
	}
}
