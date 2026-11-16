from pathlib import Path

gradle = Path("android/app/build.gradle.kts")
if not gradle.exists():
    raise SystemExit("Android host is missing. Run flutter create --platforms=android first.")

text = gradle.read_text()
text = text.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 36")
text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 29")
if 'implementation("io.github.xget7:splatkit-android:0.1.0-beta.3")' not in text:
    text = text.replace(
        "dependencies {",
        'dependencies {\n    implementation("io.github.xget7:splatkit-android:0.1.0-beta.3")',
        1,
    )
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
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "virxmagical/splat_view",
            SplatKitViewFactory(),
        )
    }

    override fun onResume() {
        super.onResume()
        SplatKitViewRegistry.resumeAll()
    }

    override fun onPause() {
        SplatKitViewRegistry.pauseAll()
        super.onPause()
    }

}
""")

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
    fun add(view: SplatSurfaceView) { views.add(view) }
    fun remove(view: SplatSurfaceView) { views.remove(view) }
    fun resumeAll() { views.forEach { it.resume() } }
    fun pauseAll() { views.forEach { it.pause() } }
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
