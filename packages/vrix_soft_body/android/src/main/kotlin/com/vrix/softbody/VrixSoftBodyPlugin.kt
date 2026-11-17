package com.vrix.softbody

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Loads the native XPBD library as part of the Android plugin artifact. */
class VrixSoftBodyPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Dart FFI loads libvrix_soft_body.so directly. Keep plugin registration
        // explicit so Flutter includes this Android library in the host APK.
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
