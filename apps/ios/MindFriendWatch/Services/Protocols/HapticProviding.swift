import Foundation

/// Protocol for haptic feedback abstraction (enables testing without hardware)
@MainActor
protocol HapticProviding {
    // Breathing exercise haptics
    func playInhaleStart()
    func playInhaleProgress()
    func playHoldStart()
    func playHoldProgress()
    func playExhaleStart()
    func playExhaleComplete()
    func playSessionComplete()

    // General haptics
    func playClick()
    func playSuccess()
    func playFailure()
}
