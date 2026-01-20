import Foundation

/// Safe subscript extension for all Collection types
/// Returns nil instead of crashing when accessing out-of-bounds indices
extension Collection {
    /// Safely access an element at the given index
    /// - Parameter index: The index to access
    /// - Returns: The element at the index, or nil if out of bounds
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
