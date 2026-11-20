package com.flutterreality.flutter_reality.Serialization

import com.google.ar.core.Pose
import kotlin.math.sqrt

/**
 * Converts a column-major rigid 4x4 transform into an ARCore Pose.
 *
 * ARCore requires the quaternion in x,y,z,w order. Do not pass SceneView's
 * Euler Rotation type through this boundary: it is not an ARCore quaternion.
 */
fun deserializeArCorePose(transform: List<Double>): Pose {
    require(transform.size == 16) { "AR transform must contain 16 matrix values" }
    require(transform.all { it.isFinite() }) { "AR transform must be finite" }

    // Matrix4 is column-major; read its upper-left 3x3 rotation matrix.
    val m00 = transform[0].toFloat()
    val m01 = transform[4].toFloat()
    val m02 = transform[8].toFloat()
    val m10 = transform[1].toFloat()
    val m11 = transform[5].toFloat()
    val m12 = transform[9].toFloat()
    val m20 = transform[2].toFloat()
    val m21 = transform[6].toFloat()
    val m22 = transform[10].toFloat()

    val trace = m00 + m11 + m22
    val qx: Float
    val qy: Float
    val qz: Float
    val qw: Float

    if (trace > 0f) {
        val s = sqrt(trace + 1f) * 2f
        qw = 0.25f * s
        qx = (m21 - m12) / s
        qy = (m02 - m20) / s
        qz = (m10 - m01) / s
    } else if (m00 > m11 && m00 > m22) {
        val s = sqrt(1f + m00 - m11 - m22) * 2f
        qw = (m21 - m12) / s
        qx = 0.25f * s
        qy = (m01 + m10) / s
        qz = (m02 + m20) / s
    } else if (m11 > m22) {
        val s = sqrt(1f + m11 - m00 - m22) * 2f
        qw = (m02 - m20) / s
        qx = (m01 + m10) / s
        qy = 0.25f * s
        qz = (m12 + m21) / s
    } else {
        val s = sqrt(1f + m22 - m00 - m11) * 2f
        qw = (m10 - m01) / s
        qx = (m02 + m20) / s
        qy = (m12 + m21) / s
        qz = 0.25f * s
    }

    val length = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    require(length.isFinite() && length > 1e-6f) {
        "AR transform rotation is not a valid quaternion"
    }

    return Pose(
        floatArrayOf(
            transform[12].toFloat(),
            transform[13].toFloat(),
            transform[14].toFloat(),
        ),
        floatArrayOf(qx / length, qy / length, qz / length, qw / length),
    )
}
