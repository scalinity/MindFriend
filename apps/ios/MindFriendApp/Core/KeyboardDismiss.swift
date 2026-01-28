import SwiftUI

// MARK: - Keyboard Dismiss Helpers

/// View modifier that adds swipe-down gesture to dismiss keyboard
struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { gesture in
                        // Dismiss keyboard on swipe down
                        if gesture.translation.height > 0 && abs(gesture.translation.height) > abs(gesture.translation.width) {
                            hideKeyboard()
                        }
                    }
            )
    }
}

/// View modifier that adds tap gesture to dismiss keyboard
struct KeyboardDismissOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                hideKeyboard()
            }
    }
}

/// View modifier that adds both swipe-down and tap gestures to dismiss keyboard
struct KeyboardDismissAllModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { gesture in
                        if gesture.translation.height > 0 && abs(gesture.translation.height) > abs(gesture.translation.width) {
                            hideKeyboard()
                        }
                    }
            )
            .onTapGesture {
                hideKeyboard()
            }
    }
}

/// View modifier that adds a Done button toolbar to dismiss keyboard
struct KeyboardToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        hideKeyboard()
                    }
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Dismiss keyboard on swipe down gesture
    func dismissKeyboardOnSwipe() -> some View {
        modifier(KeyboardDismissModifier())
    }

    /// Dismiss keyboard on tap outside text fields
    func dismissKeyboardOnTap() -> some View {
        modifier(KeyboardDismissOnTapModifier())
    }

    /// Dismiss keyboard on both swipe down and tap gestures
    func dismissKeyboardInteractively() -> some View {
        modifier(KeyboardDismissAllModifier())
    }

    /// Add Done button to keyboard toolbar
    func keyboardDoneButton() -> some View {
        modifier(KeyboardToolbarModifier())
    }
}

// MARK: - Global Keyboard Hide Function

/// Hide keyboard by resigning first responder
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
