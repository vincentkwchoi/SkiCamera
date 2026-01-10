import Foundation

class SmoothingFilter {
    var alpha: Double
    private var value: Double?
    
    init(alpha: Double) {
        self.alpha = alpha
    }
    
    func filter(_ input: Double) -> Double {
        guard let current = value else {
            value = input
            return input
        }
        let newValue = (alpha * input) + ((1.0 - alpha) * current)
        value = newValue
        return newValue
    }
    
    func reset() {
        value = nil
    }
}
