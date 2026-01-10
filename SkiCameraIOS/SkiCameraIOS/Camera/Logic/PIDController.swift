import Foundation

class PIDController {
    var kp: Double
    var kd: Double
    private var lastError: Double = 0.0
    
    init(kp: Double, kd: Double) {
        self.kp = kp
        self.kd = kd
    }
    
    func update(_ error: Double, _ dt: Double) -> Double {
        if dt <= 0 { return 0.0 }
        let derivative = (error - lastError) / dt
        lastError = error
        return (kp * error) + (kd * derivative)
    }
    
    func reset() {
        lastError = 0.0
    }
}
