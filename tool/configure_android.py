from pathlib import Path
import re

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
# Keep ABI selection in the build command. An ndk.abiFilters restriction conflicts
# with Flutter Gradle's --split-per-abi output configuration.
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
    # Bind the generated SVG-derived assets to the Android application.
    application = re.search(r"<application\b[^>]*>", xml, flags=re.DOTALL)
    if application is None:
        raise SystemExit("AndroidManifest.xml has no <application> element")
    tag = application.group(0)
    if re.search(r'android:icon="[^"]+"', tag):
        tag = re.sub(r'android:icon="[^"]+"', 'android:icon="@mipmap/ic_launcher"', tag)
    else:
        tag = tag[:-1] + ' android:icon="@mipmap/ic_launcher">'
    if re.search(r'android:roundIcon="[^"]+"', tag):
        tag = re.sub(r'android:roundIcon="[^"]+"', 'android:roundIcon="@mipmap/ic_launcher_round"', tag)
    else:
        tag = tag[:-1] + ' android:roundIcon="@mipmap/ic_launcher_round">'
    xml = xml[:application.start()] + tag + xml[application.end():]
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
            SplatKitViewFactory(flutterEngine.dartExecutor.binaryMessenger),
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
import android.os.Handler
import android.os.Looper
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
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) { showDeck() }
        override fun onDisplayChanged(displayId: Int) { if (presentation == null) showDeck() }
        override fun onDisplayRemoved(displayId: Int) {
            if (presentation?.display?.displayId == displayId) hideDeck()
        }
    }

    init {
        displayManager.registerDisplayListener(displayListener, Handler(Looper.getMainLooper()))
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
                    presentation?.update(fps, objectCount, physicsEnabled, physicsLabel, touchThreshold)
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
        displayManager.unregisterDisplayListener(displayListener)
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
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import com.splatkit.CameraPose
import com.splatkit.RenderPolicy
import com.splatkit.RenderQuality
import com.splatkit.SortDepth
import com.splatkit.SplatStats
import com.splatkit.SplatSurfaceView
import com.splatkit.WorldPoint
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File
import java.util.concurrent.CopyOnWriteArraySet

class SplatKitViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return SplatKitPlatformView(context, viewId, params, messenger)
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
    viewId: Int,
    params: Map<String, Any?>,
    messenger: BinaryMessenger,
) : PlatformView {
    private val container = FrameLayout(context)
    private val splatView = SplatSurfaceView(context)
    private val channel = MethodChannel(messenger, "virxmagical/splat_view/$viewId")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingEvents = mutableListOf<Map<String, Any?>>()
    private var dartAttached = false
    @Volatile private var disposed = false

    init {
        container.addView(
            splatView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        SplatKitViewRegistry.add(splatView)
        splatView.listener = object : SplatSurfaceView.Listener {
            override fun onWorldReady(splatCount: Int) =
                emit("worldReady", mapOf("splatCount" to splatCount))
            override fun onWorldFrameReady(splatCount: Int) =
                emit("worldFrameReady", mapOf("splatCount" to splatCount))
            override fun onGpuFailed(message: String) =
                emit("gpuFailed", mapOf("message" to message))
            override fun onWorldFailed(message: String) =
                emit("worldFailed", mapOf("message" to message))
            override fun onColliderReady() = emit("colliderReady")
            override fun onColliderFailed(message: String) =
                emit("colliderFailed", mapOf("message" to message))
        }
        splatView.cameraPoseIntervalMillis = 250
        splatView.cameraPoseListener = { pose ->
            emit("cameraPose", poseMap(pose))
        }
        channel.setMethodCallHandler(::handleMethodCall)

        val path = params["worldPath"] as? String
        val kind = params["worldKind"] as? String
        if (!path.isNullOrBlank()) {
            loadWorld(path, kind)
        }
    }

    override fun getView(): View = container

    private fun emit(type: String, values: Map<String, Any?> = emptyMap()) {
        val event = HashMap<String, Any?>(values)
        event["type"] = type
        mainHandler.post {
            if (disposed) return@post
            if (dartAttached) {
                channel.invokeMethod("event", event)
            } else {
                pendingEvents.add(event)
            }
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "attach" -> {
                    dartAttached = true
                    pendingEvents.toList().forEach { channel.invokeMethod("event", it) }
                    pendingEvents.clear()
                    result.success(deviceInfo())
                }
                "getDeviceInfo" -> result.success(deviceInfo())
                "readStats" -> result.success(statsMap(splatView.readStats()))
                "getCameraPose" -> result.success(poseMap(splatView.cameraPose))
                "setCameraPose" -> {
                    val args = arguments(call)
                    splatView.cameraPose = CameraPose(
                        requiredFloat(args, "x"),
                        requiredFloat(args, "y"),
                        requiredFloat(args, "z"),
                        optionalFloat(args, "yaw", 0f),
                        optionalFloat(args, "pitch", 0f),
                    )
                    result.success(true)
                }
                "setMotionEnabled" -> {
                    splatView.setMotionEnabled(call.argument<Boolean>("enabled") ?: false)
                    result.success(splatView.isMotionEnabled)
                }
                "applyQuality" -> {
                    val name = call.argument<String>("preset") ?: "medium"
                    val quality = RenderQuality.named(name)
                        ?: throw IllegalArgumentException("Unknown quality preset: $name")
                    splatView.applyQuality(quality)
                    result.success(true)
                }
                "setRenderScale" -> {
                    splatView.renderScale = requiredFloat(arguments(call), "value")
                    result.success(true)
                }
                "setShDegree" -> {
                    splatView.shDegree = requiredInt(arguments(call), "value")
                    result.success(true)
                }
                "setMaxFramesPerSecond" -> {
                    val value = (arguments(call)["value"] as? Number)?.toFloat()
                    splatView.maxFramesPerSecond = value
                    result.success(true)
                }
                "orbit" -> result.success(
                    splatView.orbit(
                        requiredFloat(arguments(call), "azimuth"),
                        requiredFloat(arguments(call), "elevation"),
                    ),
                )
                "dolly" -> result.success(
                    splatView.dolly(requiredFloat(arguments(call), "delta")),
                )
                "focus" -> result.success(
                    splatView.focus(
                        requiredFloat(arguments(call), "x"),
                        requiredFloat(arguments(call), "y"),
                    ),
                )
                "look" -> {
                    splatView.look(
                        requiredFloat(arguments(call), "yaw"),
                        requiredFloat(arguments(call), "pitch"),
                    )
                    result.success(true)
                }
                "setAnchor" -> {
                    val args = arguments(call)
                    splatView.setAnchor(
                        WorldPoint(
                            requiredFloat(args, "x"),
                            requiredFloat(args, "y"),
                            requiredFloat(args, "z"),
                        ),
                    )
                    result.success(true)
                }
                "setWalkVelocity" -> {
                    splatView.setWalkVelocity(
                        requiredFloat(arguments(call), "forward"),
                        requiredFloat(arguments(call), "right"),
                    )
                    result.success(true)
                }
                "loadCollider" -> {
                    val file = requiredFile(arguments(call), "path")
                    splatView.loadCollider(file)
                    result.success(true)
                }
                "loadTiledWorld" -> {
                    val file = requiredFile(arguments(call), "path")
                    splatView.loadTiledWorld(file)
                    result.success(true)
                }
                "loadWorld" -> {
                    val args = arguments(call)
                    loadWorld(requiredString(args, "path"), args["kind"] as? String)
                    result.success(true)
                }
                "applyRenderPolicy" -> {
                    val args = arguments(call)
                    val policyArgs = args["policy"] as? Map<*, *>
                        ?: throw IllegalArgumentException("policy map is required")
                    val sortWire = optionalInt(policyArgs, "sortDepth", 16)
                    val sortDepth = SortDepth.fromWire(sortWire)
                        ?: throw IllegalArgumentException("sortDepth must be 16 or 32")
                    val policy = RenderPolicy(
                        lodErrorPixels = optionalFloat(policyArgs, "lodErrorPixels", 1f),
                        lodSplatLimit = optionalInt(policyArgs, "lodSplatLimit", 0),
                        alphaThreshold = optionalFloat(policyArgs, "alphaThreshold", 1f / 255f),
                        subpixelThreshold = optionalFloat(policyArgs, "subpixelThreshold", 1f),
                        enableFrustumCulling = optionalBoolean(policyArgs, "enableFrustumCulling", true),
                        enableHiZOcclusion = optionalBoolean(policyArgs, "enableHiZOcclusion", false),
                        enableEarlyTermination = optionalBoolean(policyArgs, "enableEarlyTermination", true),
                        sortDepth = sortDepth,
                    )
                    splatView.applyRenderPolicy(policy) { resolution ->
                        result.success(
                            mapOf(
                                "accepted" to resolution.accepted,
                                "preparationFailed" to resolution.preparationFailed,
                                "error" to resolution.error,
                                "warnings" to resolution.warnings,
                            ),
                        )
                    }
                }
                "startBenchmark" -> {
                    splatView.startBenchmark(optionalFloat(arguments(call), "seconds", 10f))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("SPLAT_VIEW_ERROR", error.message ?: error.javaClass.simpleName, null)
        }
    }

    private fun loadWorld(path: String, kind: String?) {
        val file = File(path)
        if (!file.isFile || !file.canRead()) {
            emit("worldFailed", mapOf("message" to "World file is missing or unreadable: $path"))
            return
        }
        try {
            if (kind == "tiled" || file.extension.equals("json", ignoreCase = true)) {
                splatView.loadTiledWorld(file)
            } else {
                splatView.loadWorld(file)
            }
        } catch (error: Throwable) {
            emit("worldFailed", mapOf("message" to (error.message ?: "World load failed")))
        }
    }

    private fun deviceInfo(): Map<String, Any?> = mapOf(
        "isAvailable" to splatView.isAvailable,
        "gpuDescription" to splatView.gpuDescription,
        "cameraPose" to poseMap(splatView.cameraPose),
        "motionEnabled" to splatView.isMotionEnabled,
        "capabilities" to capabilitiesMap(),
    )

    private fun capabilitiesMap(): Map<String, Any?>? {
        val capabilities = splatView.deviceCapabilities ?: return null
        val limits = capabilities.limits
        val support = capabilities.policy
        return mapOf(
            "maxLodCapacitySplats" to limits.maxLodCapacitySplats,
            "minResidencyCapacitySplats" to limits.minResidencyCapacitySplats,
            "maxResidencyCapacitySplats" to limits.maxResidencyCapacitySplats,
            "supportsHiZOcclusion" to capabilities.supportsHiZOcclusion,
            "supportsSubgroups" to capabilities.supportsSubgroups,
            "maxTextureDimension" to capabilities.maxTextureDimension,
            "policySupport" to mapOf(
                "lodErrorPixels" to support.lodErrorPixels,
                "alphaThreshold" to support.alphaThreshold,
                "subpixelThreshold" to support.subpixelThreshold,
                "enableFrustumCulling" to support.enableFrustumCulling,
                "enableHiZOcclusion" to support.enableHiZOcclusion,
                "enableEarlyTermination" to support.enableEarlyTermination,
                "sortDepth" to support.sortDepth,
                "lodSplatLimit" to support.lodSplatLimit,
                "minLodErrorPixels" to support.minLodErrorPixels,
                "maxLodErrorPixels" to support.maxLodErrorPixels,
                "minSubpixelThreshold" to support.minSubpixelThreshold,
                "maxSubpixelThreshold" to support.maxSubpixelThreshold,
            ),
        )
    }

    private fun statsMap(stats: SplatStats): Map<String, Any> = mapOf(
        "fps" to stats.fps,
        "frameMillis" to stats.frameMillis,
        "gpuMillis" to stats.gpuMillis,
        "sortMillis" to stats.sortMillis,
        "loadedSplats" to stats.loadedSplatCount,
        "drawnSplats" to stats.drawnSplatCount,
        "loadedShDegree" to stats.loadedShDegree,
        "walking" to stats.walking,
        "motion" to stats.motion,
    )

    private fun poseMap(pose: CameraPose): Map<String, Any> = mapOf(
        "x" to pose.x,
        "y" to pose.y,
        "z" to pose.z,
        "yaw" to pose.yaw,
        "pitch" to pose.pitch,
    )

    private fun arguments(call: MethodCall): Map<*, *> =
        call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()

    private fun requiredString(args: Map<*, *>, key: String): String =
        (args[key] as? String)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("$key is required")

    private fun requiredFile(args: Map<*, *>, key: String): File {
        val file = File(requiredString(args, key))
        require(file.isFile && file.canRead()) { "$key is missing or unreadable" }
        return file
    }

    private fun requiredFloat(args: Map<*, *>, key: String): Float {
        val value = (args[key] as? Number)?.toFloat()
            ?: throw IllegalArgumentException("$key must be numeric")
        require(value.isFinite()) { "$key must be finite" }
        return value
    }

    private fun optionalFloat(args: Map<*, *>, key: String, default: Float): Float {
        val value = (args[key] as? Number)?.toFloat() ?: default
        require(value.isFinite()) { "$key must be finite" }
        return value
    }

    private fun requiredInt(args: Map<*, *>, key: String): Int =
        (args[key] as? Number)?.toInt()
            ?: throw IllegalArgumentException("$key must be an integer")

    private fun optionalInt(args: Map<*, *>, key: String, default: Int): Int =
        (args[key] as? Number)?.toInt() ?: default

    private fun optionalBoolean(args: Map<*, *>, key: String, default: Boolean): Boolean =
        args[key] as? Boolean ?: default

    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        splatView.cameraPoseListener = null
        splatView.listener = null
        splatView.setMotionEnabled(false)
        SplatKitViewRegistry.remove(splatView)
        splatView.release()
        pendingEvents.clear()
    }
}
""")

print("Configured Android host for SplatKit (API 29+, arm64-v8a, Vulkan runtime).")
