package com.vcnt.skicamera.shared

import kotlin.math.sqrt

/**
 * A standard PD Controller (Integral is omitted for auto-zoom stability).
 */
class PIDController(
    var kp: Double,
    var kd: Double
) {
    private var prevError: Double = 0.0

    /**
     * Calculates the control output (velocity).
     * @param error The difference between Target and Current.
     * @param dt Delta time in seconds.
     */
    fun update(error: Double, dt: Double): Double {
        if (dt <= 0) return 0.0

        // Derivative term: Rate of change of error
        val derivative = (error - prevError) / dt
        prevError = error

        return (kp * error) + (kd * derivative)
    }

    fun reset() {
        prevError = 0.0
    }
}
