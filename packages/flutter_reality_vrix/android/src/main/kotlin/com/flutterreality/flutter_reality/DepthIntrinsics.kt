package com.flutterreality.flutter_reality

internal data class ScaledDepthIntrinsics(
    val fx: Double,
    val fy: Double,
    val cx: Double,
    val cy: Double,
    val width: Int,
    val height: Int,
) {
    fun toChannelMap(): Map<String, Any> = mapOf(
        "fx" to fx,
        "fy" to fy,
        "cx" to cx,
        "cy" to cy,
        "width" to width,
        "height" to height,
    )
}

/** Scale CPU camera-image intrinsics into the depth image's pixel grid. */
internal fun scaleDepthIntrinsics(
    focalX: Float,
    focalY: Float,
    principalX: Float,
    principalY: Float,
    imageWidth: Int,
    imageHeight: Int,
    depthWidth: Int,
    depthHeight: Int,
): ScaledDepthIntrinsics {
    require(imageWidth > 0 && imageHeight > 0) { "CPU image dimensions must be positive." }
    require(depthWidth > 0 && depthHeight > 0) { "Depth image dimensions must be positive." }
    require(
        focalX.isFinite() && focalY.isFinite() &&
            principalX.isFinite() && principalY.isFinite(),
    ) { "Camera intrinsics must be finite." }

    val scaleX = depthWidth.toFloat() / imageWidth
    val scaleY = depthHeight.toFloat() / imageHeight
    return ScaledDepthIntrinsics(
        fx = (focalX * scaleX).toDouble(),
        fy = (focalY * scaleY).toDouble(),
        cx = (principalX * scaleX).toDouble(),
        cy = (principalY * scaleY).toDouble(),
        width = depthWidth,
        height = depthHeight,
    )
}
