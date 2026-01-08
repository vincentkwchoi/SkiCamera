package com.vcnt.skicamera.shared

/**
 * Exponential Moving Average (EMA) filter.
 * [alpha] determines Smoothing vs. Lag.
 */
class SmoothingFilter(var alpha: Double = 0.5) {
    private var prevValue: Double? = null

    fun filter(rawValue: Double): Double {
        val prev = prevValue
        return if (prev == null) {
            prevValue = rawValue
            rawValue
        } else {
            val newValue = (alpha * rawValue) + ((1.0 - alpha) * prev)
            prevValue = newValue
            newValue
        }
    }

    fun currentValue(): Double? = prevValue

    fun reset() {
        prevValue = null
    }
}
