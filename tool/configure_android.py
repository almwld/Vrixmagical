from pathlib import Path

gradle = Path("android/app/build.gradle.kts")
if not gradle.exists():
    raise SystemExit("Android host is missing. Run flutter create --platforms=android first.")

text = gradle.read_text()
text = text.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 36")
text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 29")
splatkit_dependency = 'implementation("io.github.xget7:splatkit-android:0.1.0-beta.3")'
if splatkit_dependency not in text:
    if "dependencies {" in text:
        text = text.replace(
            "dependencies {",
            "dependencies {\n    " + splatkit_dependency,
            1,
        )
    else:
        text += "\n\ndependencies {\n    " + splatkit_dependency + "\n}\n"
if splatkit_dependency not in text:
    raise SystemExit("Failed to add the SplatKit Android dependency to app/build.gradle.kts.")
if "abiFilters" not in text:
    text = text.replace(
        "minSdk = 29",
        'minSdk = 29\n        ndk { abiFilters += listOf("arm64-v8a") }',
        1,
    )
gradle.write_text(text)

manifest = Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    xml = manifest.read_text()
    if "xmlns:tools=" not in xml:
        xml = xml.replace("<manifest", '<manifest xmlns:tools="http://schemas.android.com/tools"', 1)
    if "android.permission.INTERNET" not in xml:
        xml = xml.replace(
            "<application",
            '    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-feature android:name="android.hardware.camera.ar" android:required="false" tools:replace="android:required" />\n    <application',
            1,
        )
    manifest.write_text(xml)

main_activity = Path("android/app/src/main/kotlin/com/virxmagical/virxmagical/MainActivity.kt")
main_activity.parent.mkdir(parents=True, exist_ok=True)
main_activity.write_text("""package com.virxmagical.virxmagical

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var wingDeck: LgWingDeckController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "virxmagical/splat_view",
            SplatKitViewFactory(),
        )
        wingDeck = LgWingDeckController(this, flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        SplatKitViewRegistry.resumeAll()
    }

    override fun onPause() {
        SplatKitViewRegistry.pauseAll()
        super.onPause()
    }

    override fun onDestroy() {
        wingDeck?.dispose()
        wingDeck = null
        super.onDestroy()
    }
}
""")

wing_deck = Path("android/app/src/main/kotlin/com/virxmagical/virxmagical/LgWingDeckController.kt")
wing_deck.write_text("""package com.virxmagical.virxmagical

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

internal class LgWingDeckController(
    private val context: Context,
    engine: FlutterEngine,
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "vrix/wing_deck")
    private val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private var presentation: DeckPresentation? = null
    private var fps = 0.0
    private var objectCount = 0
    private var physicsEnabled = true
    private var physicsLabel = "Jolt"
    private var touchThreshold = 0.18

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> result.success(showDeck())
                "hide" -> {
                    hideDeck()
                    result.success(null)
                }
                "updateTelemetry" -> {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    fps = (values["fps"] as? Number)?.toDouble() ?: fps
                    objectCount = (values["placedObjects"] as? Number)?.toInt() ?: objectCount
                    physicsEnabled = values["physicsEnabled"] as? Boolean ?: physicsEnabled
                    physicsLabel = values["physicsLabel"] as? String ?: physicsLabel
                    touchThreshold = (values["touchThreshold"] as? Number)?.toDouble() ?: touchThreshold
                    presentation?.refresh()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun showDeck(): Boolean {
        if (presentation?.isShowing == true) return true
        val displays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .filter { it.displayId != Display.DEFAULT_DISPLAY }
            .ifEmpty {
                displayManager.displays.filter { it.displayId != Display.DEFAULT_DISPLAY }
            }
        val target = displays.firstOrNull() ?: return false
        return try {
            presentation = DeckPresentation(context, target).also {
                it.setOnAction { action, data ->
                    channel.invokeMethod("deckAction", mapOf("action" to action) + data)
                }
                it.update(fps, objectCount, physicsEnabled, physicsLabel, touchThreshold)
                it.show()
            }
            true
        } catch (_: Throwable) {
            presentation = null
            false
        }
    }

    private fun hideDeck() {
        presentation?.dismiss()
        presentation = null
    }

    fun dispose() {
        hideDeck()
        channel.setMethodCallHandler(null)
    }

    private class DeckPresentation(context: Context, display: Display) :
        Presentation(context, display) {
        private var fpsView: TextView? = null
        private var objectsView: TextView? = null
        private var physicsView: TextView? = null
        private var thresholdView: TextView? = null
        private var physicsButton: Button? = null
        private var threshold = 0.18
        private var action: ((String, Map<String, Any>) -> Unit)? = null

        fun setOnAction(listener: (String, Map<String, Any>) -> Unit) {
            action = listener
        }

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            val root = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(20, 18, 20, 18)
                setBackgroundColor(0xFF080D16.toInt())
            }
            val scroll = ScrollView(context)
            val content = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
            }
            scroll.addView(content)
            root.addView(scroll, LinearLayout.LayoutParams(-1, -1))

            content.addView(label("VRIX  /  CONTROL DECK", 18, 0xFF45E2D1.toInt()))
            content.addView(label("لوحة التحكم الهندسية", 16, 0xFFF2F6FC.toInt()))
            content.addView(label("الشاشة الرئيسية مخصصة للمشهد المكاني", 11, 0xFF91A3B8.toInt()))
            content.addView(divider())

            content.addView(section("الأداء المباشر"))
            fpsView = label("FPS  —", 22, 0xFF63D9A5.toInt())
            content.addView(fpsView)
            objectsView = label("الأصول المثبتة: 0", 12, 0xFFF2F6FC.toInt())
            content.addView(objectsView)
            content.addView(divider())

            content.addView(section("المحاكاة الفيزيائية"))
            physicsView = label("Jolt: نشط", 12, 0xFF63D9A5.toInt())
            content.addView(physicsView)
            physicsButton = button("إيقاف محاكاة Jolt") {
                action?.invoke("togglePhysics", emptyMap())
            }
            content.addView(physicsButton)
            content.addView(button("XPBD · غير مدمج بعد") { })
            content.addView(label("XPBD غير متاح في إصدار المحرك الحالي؛ لا يتم تمثيل Jolt على أنه XPBD.", 10, 0xFF91A3B8.toInt()))
            content.addView(divider())

            content.addView(section("تتبع اليد واللمس"))
            content.addView(button("حالة MediaPipe / المعايرة") {
                action?.invoke("handTrackingInfo", emptyMap())
            })
            thresholdView = label("عتبة اللمس: 0.18", 12, 0xFFF2F6FC.toInt())
            content.addView(thresholdView)
            val slider = SeekBar(context).apply {
                max = 100
                progress = 18
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                        threshold = progress / 100.0
                        thresholdView?.text = "عتبة اللمس: " + String.format("%.2f", threshold)
                        if (fromUser) action?.invoke("touchThreshold", mapOf("value" to threshold))
                    }
                    override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                    override fun onStopTrackingTouch(seekBar: SeekBar?) {}
                })
            }
            content.addView(slider)
            content.addView(divider())

            content.addView(section("المسح والبيانات"))
            content.addView(label("Voxel Fusion: بانتظار بيانات RGB-D", 11, 0xFF91A3B8.toInt()))
            content.addView(button("حالة بيانات المسح") {
                action?.invoke("scanInfo", emptyMap())
            })
            content.addView(label("حفظ RGB-D متاح من شاشة المسح. تصدير GLB يتطلب اكتمال إعادة بناء الشبكة.", 10, 0xFF91A3B8.toInt()))
            content.addView(divider())
            content.addView(button("إغلاق لوحة التحكم") {
                action?.invoke("hideDeck", emptyMap())
            })
            setContentView(root)
        }

        fun refresh() {
            update(0.0, 0, true, "Jolt", threshold)
        }

        fun update(fps: Double, count: Int, enabled: Boolean, label: String, touch: Double) {
            if (fps > 0.0) this.fpsView?.text = "FPS  " + String.format("%.0f", fps)
            this.objectsView?.text = "الأصول المثبتة: " + count
            this.physicsView?.text = label + if (enabled) ": نشط" else ": متوقف"
            this.physicsButton?.text = if (enabled) "إيقاف محاكاة Jolt" else "تشغيل محاكاة Jolt"
            this.threshold = touch
            this.thresholdView?.text = "عتبة اللمس: " + String.format("%.2f", touch)
        }

        private fun label(text: String, size: Int, color: Int) = TextView(context).apply {
            this.text = text
            textSize = size.toFloat()
            setTextColor(color)
            gravity = Gravity.START
            setPadding(0, 8, 0, 8)
        }

        private fun section(text: String) = label(text, 13, 0xFF45E2D1.toInt())

        private fun divider() = View(context).apply {
            setBackgroundColor(0xFF26384D.toInt())
            layoutParams = LinearLayout.LayoutParams(-1, 1).apply {
                topMargin = 8
                bottomMargin = 8
            }
        }

        private fun button(text: String, onClick: () -> Unit) = Button(context).apply {
            this.text = text
            isAllCaps = false
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(-1, -2).apply {
                topMargin = 4
                bottomMargin = 4
            }
        }
    }
}
""")
print("Configured Android host with an LG Wing secondary-display control deck.")

native_view = Path("android/app/src/main/kotlin/com/virxmagical/virxmagical/SplatKitViewFactory.kt")
native_view.write_text("""package com.virxmagical.virxmagical

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import com.splatkit.SplatSurfaceView
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File
import java.util.concurrent.CopyOnWriteArraySet

class SplatKitViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return SplatKitPlatformView(context, params)
    }
}

internal object SplatKitViewRegistry {
    private val views = CopyOnWriteArraySet<SplatSurfaceView>()
    @Volatile private var hostResumed = false

    fun add(view: SplatSurfaceView) {
        views.add(view)
        if (hostResumed) view.resume()
    }
    fun remove(view: SplatSurfaceView) { views.remove(view) }
    fun resumeAll() {
        hostResumed = true
        views.forEach { it.resume() }
    }
    fun pauseAll() {
        hostResumed = false
        views.forEach { it.pause() }
    }
}

private class SplatKitPlatformView(
    context: Context,
    params: Map<String, Any?>,
) : PlatformView {
    private val container = FrameLayout(context)
    private val splatView = SplatSurfaceView(context)

    init {
        container.addView(
            splatView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        SplatKitViewRegistry.add(splatView)
        val path = params["worldPath"] as? String
        if (!path.isNullOrBlank()) {
            val world = File(path)
            if (world.isFile) splatView.loadWorld(world)
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        SplatKitViewRegistry.remove(splatView)
        splatView.release()
    }
}
""")
print("Configured Android host for SplatKit (API 29+, arm64-v8a, Vulkan runtime).")
