package com.vcnt.skicamera.shared

data class Point(val x: Double, val y: Double)

data class Rect(
    val left: Double,
    val top: Double,
    val right: Double,
    val bottom: Double
) {
    val width: Double get() = right - left
    val height: Double get() = bottom - top
    val centerX: Double get() = left + width / 2.0
    val centerY: Double get() = top + height / 2.0
    val center: Point get() = Point(centerX, centerY)

    companion object {
        fun fromLTRB(left: Double, top: Double, right: Double, bottom: Double) = 
            Rect(left, top, right, bottom)
    }
}
