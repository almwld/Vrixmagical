package com.flutterreality.flutter_reality

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class DepthIntrinsicsScalingTest {
    @Test
    fun scalesFocalLengthAndPrincipalPointIntoDepthPixelGrid() {
        val scaled = scaleDepthIntrinsics(
            focalX = 600f,
            focalY = 580f,
            principalX = 320f,
            principalY = 240f,
            imageWidth = 640,
            imageHeight = 480,
            depthWidth = 320,
            depthHeight = 240,
        )

        assertEquals(300.0, scaled.fx, 1e-6)
        assertEquals(290.0, scaled.fy, 1e-6)
        assertEquals(160.0, scaled.cx, 1e-6)
        assertEquals(120.0, scaled.cy, 1e-6)
        assertEquals(320, scaled.width)
        assertEquals(240, scaled.height)
    }

    @Test
    fun supportsNonUniformDepthScaling() {
        val scaled = scaleDepthIntrinsics(
            focalX = 800f,
            focalY = 600f,
            principalX = 400f,
            principalY = 300f,
            imageWidth = 800,
            imageHeight = 600,
            depthWidth = 400,
            depthHeight = 300,
        )

        assertEquals(400.0, scaled.fx, 1e-6)
        assertEquals(300.0, scaled.fy, 1e-6)
        assertEquals(200.0, scaled.cx, 1e-6)
        assertEquals(150.0, scaled.cy, 1e-6)
    }

    @Test
    fun rejectsInvalidDimensionsAndNonFiniteIntrinsics() {
        assertThrows(IllegalArgumentException::class.java) {
            scaleDepthIntrinsics(1f, 1f, 0f, 0f, 0, 480, 320, 240)
        }
        assertThrows(IllegalArgumentException::class.java) {
            scaleDepthIntrinsics(Float.NaN, 1f, 0f, 0f, 640, 480, 320, 240)
        }
    }
}
