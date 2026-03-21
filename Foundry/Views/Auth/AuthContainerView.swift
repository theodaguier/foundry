import SwiftUI

enum AuthScreen {
    case login
    case loginOTP(isSignup: Bool)
    case signup
}

struct AuthContainerView: View {
    @Environment(AppState.self) private var appState

    @State private var screen: AuthScreen = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var otpDigits: [String] = Array(repeating: "", count: 6)
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case email, password, confirm
        case otpDigit(Int)
    }

    private var otpCode: String {
        otpDigits.joined()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: FoundryTheme.Spacing.xl) {
                // Header
                VStack(spacing: FoundryTheme.Spacing.sm) {
                    Text("FOUNDRY")
                        .font(FoundryTheme.Fonts.spaceGrotesk(32))
                        .tracking(2)
                        .foregroundStyle(FoundryTheme.Colors.textPrimary)

                    Text(headerSubtitle)
                        .font(FoundryTheme.Fonts.azeretMono(10))
                        .tracking(2)
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                }

                switch screen {
                case .login:
                    loginStep
                case .loginOTP(let isSignup):
                    otpStep(isSignup: isSignup)
                case .signup:
                    signupStep
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(FoundryTheme.Fonts.azeretMono(10))
                        .tracking(0.5)
                        .foregroundStyle(FoundryTheme.Colors.trafficRed)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 340)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FoundryTheme.Colors.background)
        .onAppear { focusedField = .email }
    }

    private var headerSubtitle: String {
        switch screen {
        case .login: "SIGN IN TO YOUR ACCOUNT"
        case .loginOTP: "ENTER VERIFICATION CODE"
        case .signup: "CREATE YOUR ACCOUNT"
        }
    }

    // MARK: - Login Step

    private var loginStep: some View {
        VStack(spacing: FoundryTheme.Spacing.xl) {
            fieldBlock {
                fieldRow(label: "EMAIL") {
                    TextField("", text: $email, prompt: Text("you@example.com").foregroundStyle(FoundryTheme.Colors.textDimmed))
                        .font(FoundryTheme.Fonts.azeretMono(13))
                        .textFieldStyle(.plain)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .onSubmit { sendCode() }
                }
            }

            primaryButton("SEND CODE", disabled: email.isEmpty, action: sendCode)

            HStack(spacing: 6) {
                Text("NO ACCOUNT?")
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .tracking(1)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)

                Button(action: { switchTo(.signup) }) {
                    Text("CREATE ONE")
                        .font(FoundryTheme.Fonts.azeretMono(10, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(FoundryTheme.Colors.textPrimary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - OTP Step

    private func otpStep(isSignup: Bool) -> some View {
        VStack(spacing: FoundryTheme.Spacing.xl) {
            VStack(spacing: FoundryTheme.Spacing.xs) {
                Text("CODE SENT TO")
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .tracking(1)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)

                Text(email.uppercased())
                    .font(FoundryTheme.Fonts.azeretMono(11, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(FoundryTheme.Colors.textPrimary)
            }

            // OTP digit boxes
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    otpDigitBox(index: index, isSignup: isSignup)
                }
            }

            primaryButton("VERIFY", disabled: otpCode.count != 6) {
                verifyCode(isSignup: isSignup)
            }

            HStack(spacing: FoundryTheme.Spacing.md) {
                linkButton("RESEND CODE", action: resendCode)
                linkButton("CHANGE EMAIL") { switchTo(.login) }
            }
        }
    }

    private func otpDigitBox(index: Int, isSignup: Bool) -> some View {
        ZStack {
            Color(.textBackgroundColor)

            Text(otpDigits[index])
                .font(FoundryTheme.Fonts.azeretMono(24, weight: .medium))
                .foregroundStyle(FoundryTheme.Colors.textPrimary)

            // Hidden text field to capture input
            TextField("", text: Binding(
                get: { otpDigits[index] },
                set: { newValue in
                    handleOTPInput(newValue, at: index, isSignup: isSignup)
                }
            ))
            .font(FoundryTheme.Fonts.azeretMono(24))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .focused($focusedField, equals: .otpDigit(index))
            .opacity(0.01) // Nearly invisible but still captures input
            .onKeyPress(.delete) {
                handleOTPDelete(at: index)
                return .handled
            }
        }
        .frame(width: 48, height: 56)
        .overlay(
            Rectangle()
                .strokeBorder(
                    focusedField == .otpDigit(index)
                        ? FoundryTheme.Colors.textPrimary
                        : FoundryTheme.Colors.border,
                    lineWidth: focusedField == .otpDigit(index) ? 2 : 1
                )
        )
        .onTapGesture {
            focusedField = .otpDigit(index)
        }
    }

    // MARK: - Signup Step

    private var signupStep: some View {
        VStack(spacing: FoundryTheme.Spacing.xl) {
            fieldBlock {
                fieldRow(label: "EMAIL") {
                    TextField("", text: $email, prompt: Text("you@example.com").foregroundStyle(FoundryTheme.Colors.textDimmed))
                        .font(FoundryTheme.Fonts.azeretMono(13))
                        .textFieldStyle(.plain)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                }

                fieldRow(label: "PASSWORD") {
                    SecureField("", text: $password, prompt: Text("minimum 8 characters").foregroundStyle(FoundryTheme.Colors.textDimmed))
                        .font(FoundryTheme.Fonts.azeretMono(13))
                        .textFieldStyle(.plain)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .onSubmit { focusedField = .confirm }
                }

                fieldRow(label: "CONFIRM PASSWORD") {
                    SecureField("", text: $confirmPassword, prompt: Text("repeat password").foregroundStyle(FoundryTheme.Colors.textDimmed))
                        .font(FoundryTheme.Fonts.azeretMono(13))
                        .textFieldStyle(.plain)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirm)
                        .onSubmit { createAccount() }
                }
            }

            if !confirmPassword.isEmpty && password != confirmPassword {
                Text("PASSWORDS DO NOT MATCH")
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .tracking(1)
                    .foregroundStyle(FoundryTheme.Colors.trafficRed)
            }

            primaryButton("CREATE ACCOUNT", disabled: !signupValid, action: createAccount)

            HStack(spacing: 6) {
                Text("ALREADY HAVE AN ACCOUNT?")
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .tracking(1)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)

                Button(action: { switchTo(.login) }) {
                    Text("SIGN IN")
                        .font(FoundryTheme.Fonts.azeretMono(10, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(FoundryTheme.Colors.textPrimary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var signupValid: Bool {
        !email.isEmpty && password.count >= 8 && password == confirmPassword && !confirmPassword.isEmpty
    }

    // MARK: - Reusable Components

    private func fieldBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .overlay(
            Rectangle()
                .strokeBorder(FoundryTheme.Colors.border, lineWidth: 1)
        )
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(FoundryTheme.Fonts.azeretMono(9))
                .tracking(2)
                .foregroundStyle(FoundryTheme.Colors.textMuted)
                .padding(.bottom, 6)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.textBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FoundryTheme.Colors.border)
                .frame(height: 1)
        }
    }

    private func primaryButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(title)
                        .font(FoundryTheme.Fonts.azeretMono(12))
                        .tracking(2)
                }
            }
            .foregroundStyle(Color(.windowBackgroundColor))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
        .opacity(disabled ? 0.4 : 1)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FoundryTheme.Fonts.azeretMono(10))
                .tracking(1)
                .foregroundStyle(FoundryTheme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - OTP Input Handling

    private func handleOTPInput(_ newValue: String, at index: Int, isSignup: Bool) {
        let filtered = newValue.filter(\.isNumber)

        if filtered.isEmpty {
            otpDigits[index] = ""
            return
        }

        // Handle paste of full code
        if filtered.count >= 6 {
            let digits = Array(filtered.prefix(6)).map(String.init)
            for i in 0..<6 {
                otpDigits[i] = digits[i]
            }
            focusedField = .otpDigit(5)
            // Auto-verify
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                verifyCode(isSignup: isSignup)
            }
            return
        }

        // Single digit input
        otpDigits[index] = String(filtered.last!)

        // Move to next field
        if index < 5 {
            focusedField = .otpDigit(index + 1)
        }

        // Auto-verify when all 6 filled
        if otpCode.count == 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                verifyCode(isSignup: isSignup)
            }
        }
    }

    private func handleOTPDelete(at index: Int) {
        if otpDigits[index].isEmpty && index > 0 {
            otpDigits[index - 1] = ""
            focusedField = .otpDigit(index - 1)
        } else {
            otpDigits[index] = ""
        }
    }

    // MARK: - Actions

    private func switchTo(_ newScreen: AuthScreen) {
        errorMessage = nil
        otpDigits = Array(repeating: "", count: 6)
        screen = newScreen
        switch newScreen {
        case .login: focusedField = .email
        case .loginOTP: focusedField = .otpDigit(0)
        case .signup: focusedField = .email
        }
    }

    private func sendCode() {
        guard !email.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await AuthService.shared.sendOTP(email: email)
                screen = .loginOTP(isSignup: false)
                focusedField = .otpDigit(0)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func verifyCode(isSignup: Bool) {
        guard otpCode.count == 6 else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await AuthService.shared.verifyOTP(email: email, code: otpCode, isSignup: isSignup)
                await appState.handleSignIn()
            } catch {
                errorMessage = error.localizedDescription
                otpDigits = Array(repeating: "", count: 6)
                focusedField = .otpDigit(0)
            }
            isLoading = false
        }
    }

    private func resendCode() {
        otpDigits = Array(repeating: "", count: 6)
        errorMessage = nil
        sendCode()
    }

    private func createAccount() {
        guard signupValid else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await AuthService.shared.signUp(email: email, password: password)
                // Supabase sends a 6-digit confirmation code to the email
                screen = .loginOTP(isSignup: true)
                focusedField = .otpDigit(0)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
