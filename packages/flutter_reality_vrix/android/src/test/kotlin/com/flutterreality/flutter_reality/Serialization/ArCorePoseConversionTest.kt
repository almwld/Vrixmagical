package com.flutterreality.flutter_reality.Serialization

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ArCorePoseConversionTest {
    private fun matrix(
        m00: Double, m01: Double, m02: Double,
        m10: Double, m11: Double, m12: Double,
        m20: Double, m21: Double, m22: Double,
    ): List<Double> = listOf(
        m00, m10, m20, 0.0,
        m01, m11, m21, 0.0,
        m02, m12, m22, 0.0,
        1.25, -2.5, 3.75, 1.0,
    )

    @Test
    fun identityRotationPreservesTranslation() {
        val pose = deserializeArCorePose(matrix(
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0,
        ))

        assertEquals(1.25f, pose.tx(), 1e-5f)
        assertEquals(-2.5f, pose.ty(), 1e-5f)
        assertEquals(3.75f, pose.tz(), 1e-5f)
        assertEquals(0f, pose.qx(), 1e-5f)
        assertEquals(0f, pose.qy(), 1e-5f)
        assertEquals(0f, pose.qz(), 1e-5f)
        assertEquals(1f, pose.qw(), 1e-5f)
    }

    @Test
    fun quarterTurnAroundYProducesNormalizedQuaternion() {
        val pose = deserializeArCorePose(matrix(
            0.0, 0.0, 1.0,
            0.0, 1.0, 0.0,
            -1.0, 0.0, 0.0,
        ))
        val halfRoot = kotlin.math.sqrt(0.5f)

        assertEquals(0f, pose.qx(), 1e-5f)
        assertEquals(halfRoot, pose.qy(), 1e-5f)
        assertEquals(0f, pose.qz(), 1e-5f)
        assertEquals(halfRoot, pose.qw(), 1e-5f)
    }

    @Test
    fun halfTurnsExerciseLargestDiagonalBranches() {
        val x = deserializeArCorePose(matrix(
            1.0, 0.0, 0.0,
            0.0, -1.0, 0.0,
            0.0, 0.0, -1.0,
        ))
        val y = deserializeArCorePose(matrix(
            -1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, -1.0,
        ))
        val z = deserializeArCorePose(matrix(
            -1.0, 0.0, 0.0,
            0.0, -1.0, 0.0,
            0.0, 0.0, 1.0,
        ))

        assertEquals(1f, kotlin.math.abs(x.qx()), 1e-5f)
        assertEquals(1f, kotlin.math.abs(y.qy()), 1e-5f)
        assertEquals(1f, kotlin.math.abs(z.qz()), 1e-5f)
        assertEquals(0f, x.qw(), 1e-5f)
        assertEquals(0f, y.qw(), 1e-5f)
        assertEquals(0f, z.qw(), 1e-5f)
    }

    @Test
    fun rejectsMalformedAndNonFiniteMatrices() {
        assertThrows(IllegalArgumentException::class.java) {
            deserializeArCorePose(listOf(1.0, 2.0))
        }
        assertThrows(IllegalArgumentException::class.java) {
            deserializeArCorePose(List(16) { if (it == 0) Double.NaN else 0.0 })
        }
    }
}
