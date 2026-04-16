import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct SignInView: View {
    private let googleClientID: String? = {
        // Primary: GOOGLE_CLIENT_ID from Info.plist (populated by xcconfig).
        // Fallback: derive from the reversed CFBundleURLScheme Google Sign-In
        // registers (`com.googleusercontent.apps.<id>`) so we don't crash a
        // release build on missing xcconfig wiring.
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
           !clientID.isEmpty,
           !clientID.contains("YOUR_GOOGLE_CLIENT_ID") {
            return clientID
        }
        if let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] {
            for type in urlTypes {
                if let schemes = type["CFBundleURLSchemes"] as? [String] {
                    for scheme in schemes where scheme.hasPrefix("com.googleusercontent.apps.") {
                        let suffix = scheme.replacingOccurrences(of: "com.googleusercontent.apps.", with: "")
                        return "\(suffix).apps.googleusercontent.com"
                    }
                }
            }
        }
        return nil
    }()

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showError = false
    @State private var showEmailAuth = false
    @State private var showSuccessMessage = false
    @State private var successMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Logo and tagline
                VStack(spacing: 12) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)

                    Text("MindFriend")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Your AI wellness companion")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "sparkles", text: "Daily wellness quests")
                    FeatureRow(icon: "bubble.left.and.bubble.right.fill", text: "AI-powered chat support")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Track your mood journey")
                    FeatureRow(icon: "person.3.fill", text: "Connect with friends")
                }
                .padding(.horizontal, 32)

                Spacer()

                // Sign in buttons
                VStack(spacing: 12) {
                    SignInWithAppleButton { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(12)
                    .accessibilityLabel("Sign in with Apple")

                    Button {
                        handleGoogleSignIn()
                    } label: {
                        HStack(spacing: 12) {
                            Image("GoogleLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Continue with Google")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Continue with Google")

                    // Email sign in button
                    Button {
                        showEmailAuth = true
                    } label: {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text("Continue with Email")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Continue with Email")
                }
                .padding(.horizontal, 24)

                Text("By signing in, you agree to our Terms of Service and Privacy Policy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }
            .overlay {
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .alert("Sign In Error", isPresented: $showError, presenting: error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .alert("Success", isPresented: $showSuccessMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(successMessage)
            }
            .sheet(isPresented: $showEmailAuth) {
                EmailAuthView(
                    isLoading: $isLoading,
                    onSignIn: handleEmailSignIn,
                    onSignUp: handleEmailSignUp,
                    onForgotPassword: handleForgotPassword
                )
            }
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let authCode = credential.authorizationCode else {
                error = AuthError.invalidCredentials
                showError = true
                return
            }

            Task {
                isLoading = true
                do {
                    // Use SupabaseAuthService for Apple Sign-In
                    let user = try await container.supabaseAuthService.signInWithApple(
                        identityToken: identityToken,
                        authorizationCode: authCode,
                        fullName: credential.fullName,
                        email: credential.email
                    )

                    await MainActor.run {
                        appState.setAuthenticated(user: user)
                    }
                } catch {
                    self.error = error
                    showError = true
                }
                isLoading = false
            }

        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                self.error = error
                showError = true
            }
        }
    }

    private func handleGoogleSignIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        // Hard-fail gracefully instead of letting GIDSignIn raise
        // NSInvalidArgumentException on an empty clientID (was a release-only
        // crash when GOOGLE_CLIENT_ID wasn't plumbed through xcconfig).
        guard let clientID = googleClientID, !clientID.isEmpty else {
            self.error = AuthError.unknown("Google Sign-In is not configured for this build. Please use email sign-in or contact support.")
            self.showError = true
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

                guard let idToken = result.user.idToken?.tokenString else {
                    throw AuthError.missingIdToken
                }

                let accessToken = result.user.accessToken.tokenString
                guard !accessToken.isEmpty else {
                    throw AuthError.missingIdToken
                }

                isLoading = true
                // Use SupabaseAuthService for Google Sign-In
                let user = try await container.supabaseAuthService.signInWithGoogle(
                    idToken: idToken,
                    accessToken: accessToken
                )

                await MainActor.run {
                    appState.setAuthenticated(user: user)
                }
            } catch GIDSignInError.canceled {
                // User cancelled - ignore
            } catch {
                self.error = error
                showError = true
            }
            isLoading = false
        }
    }

    private func handleEmailSignIn(email: String, password: String) {
        Task {
            isLoading = true
            do {
                let user = try await container.supabaseAuthService.signIn(email: email, password: password)
                await MainActor.run {
                    showEmailAuth = false
                    appState.setAuthenticated(user: user)
                }
            } catch AuthError.emailConfirmationRequired {
                await MainActor.run {
                    showEmailAuth = false
                    successMessage = "Please check your email and click the confirmation link before signing in."
                    showSuccessMessage = true
                }
            } catch {
                self.error = error
                showError = true
            }
            isLoading = false
        }
    }

    private func handleEmailSignUp(email: String, password: String, displayName: String) {
        Task {
            isLoading = true
            do {
                let user = try await container.supabaseAuthService.signUp(
                    email: email,
                    password: password,
                    displayName: displayName.isEmpty ? nil : displayName
                )
                await MainActor.run {
                    showEmailAuth = false
                    appState.setAuthenticated(user: user)
                }
            } catch AuthError.emailConfirmationRequired {
                await MainActor.run {
                    showEmailAuth = false
                    successMessage = "Please check your email to confirm your account, then sign in."
                    showSuccessMessage = true
                }
            } catch {
                self.error = error
                showError = true
            }
            isLoading = false
        }
    }

    private func handleForgotPassword(email: String) {
        Task {
            isLoading = true
            do {
                try await container.supabaseAuthService.resetPassword(email: email)
                await MainActor.run {
                    successMessage = "Password reset email sent. Check your inbox."
                    showSuccessMessage = true
                }
            } catch {
                self.error = error
                showError = true
            }
            isLoading = false
        }
    }
}

// MARK: - Email Auth View

struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isLoading: Bool

    let onSignIn: (String, String) -> Void
    let onSignUp: (String, String, String) -> Void
    let onForgotPassword: (String) -> Void

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var showForgotPassword = false

    enum Field {
        case email, password, confirmPassword, displayName
    }

    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.accentColor)

                        Text(isSignUp ? "Create Account" : "Welcome Back")
                            .font(.title)
                            .fontWeight(.bold)

                        Text(isSignUp ? "Sign up with your email" : "Sign in with your email")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    // Form fields
                    VStack(spacing: 16) {
                        if isSignUp {
                            TextField("Display Name", text: $displayName)
                                .textContentType(.name)
                                .focused($focusedField, equals: .displayName)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }

                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                        if isSignUp {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirmPassword)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Action button
                    Button {
                        if isSignUp {
                            onSignUp(email, password, displayName)
                        } else {
                            onSignIn(email, password)
                        }
                    } label: {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(isFormValid ? Color.accentColor : Color.gray)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.horizontal, 24)

                    // Forgot password (sign in only)
                    if !isSignUp {
                        Button("Forgot Password?") {
                            showForgotPassword = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    }

                    // Toggle sign in/sign up
                    HStack {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .foregroundStyle(.secondary)
                        Button(isSignUp ? "Sign In" : "Sign Up") {
                            withAnimation {
                                isSignUp.toggle()
                                clearForm()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Reset Password", isPresented: $showForgotPassword) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                Button("Send Reset Link") {
                    onForgotPassword(email)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter your email to receive a password reset link.")
            }
            .keyboardDoneButton()
        }
    }

    private var isFormValid: Bool {
        let emailValid = email.range(of: "[^@]+@[^@]+\\.[^@]+", options: .regularExpression) != nil
        let passwordValid = password.count >= 6

        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword
        } else {
            return emailValid && passwordValid
        }
    }

    private func clearForm() {
        password = ""
        confirmPassword = ""
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            Text(text)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#Preview {
    SignInView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
