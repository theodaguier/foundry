import Foundation
import Supabase
import Auth

// MARK: - UserDefaults Auth Storage

/// Stores Supabase auth tokens in UserDefaults instead of Keychain
/// to avoid the macOS Keychain access prompt on every launch.
struct UserDefaultsAuthStorage: AuthLocalStorage {
    private let prefix = "supabase.auth."

    func store(key: String, value: Data) throws {
        UserDefaults.standard.set(value, forKey: prefix + key)
    }

    func retrieve(key: String) throws -> Data? {
        UserDefaults.standard.data(forKey: prefix + key)
    }

    func remove(key: String) throws {
        UserDefaults.standard.removeObject(forKey: prefix + key)
    }
}

@MainActor
final class AuthService {
    static let shared = AuthService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: FoundryConfig.supabaseURL,
            supabaseKey: FoundryConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: UserDefaultsAuthStorage()
                )
            )
        )
    }

    // MARK: - Authentication

    /// Create a new account with email + password
    func signUp(email: String, password: String) async throws -> Auth.User {
        let response = try await client.auth.signUp(email: email, password: password)
        // Profile is created automatically by Postgres trigger on auth.users insert
        return response.user
    }

    /// Send an OTP code to sign in (passwordless login)
    func sendOTP(email: String) async throws {
        try await client.auth.signInWithOTP(email: email)
    }

    /// Verify the OTP code and establish a session
    func verifyOTP(email: String, code: String, isSignup: Bool = false) async throws -> Session {
        let response = try await client.auth.verifyOTP(
            email: email,
            token: code,
            type: isSignup ? .signup : .email
        )
        guard let session = response.session else {
            throw AuthError.verificationFailed
        }
        return session
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - Session

    var currentSession: Session? {
        get async {
            try? await client.auth.session
        }
    }

    var currentUser: Auth.User? {
        get async {
            await currentSession?.user
        }
    }

    var isAuthenticated: Bool {
        get async {
            await currentSession != nil
        }
    }

    // MARK: - Auth State Changes

    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    continuation.yield((event: event, session: session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Profile

    func getProfile(userId: UUID) async throws -> UserProfile {
        let response: UserProfile = try await client.from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value

        return response
    }

    func updateProfile(userId: UUID, displayName: String) async throws {
        try await client.from("profiles")
            .update(["display_name": displayName])
            .eq("id", value: userId.uuidString)
            .execute()
    }

    func deleteAccount() async throws {
        if let userId = await currentUser?.id {
            try await client.from("profiles")
                .delete()
                .eq("id", value: userId.uuidString)
                .execute()
        }
        try await client.auth.signOut()
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .verificationFailed:
                "Verification failed. Please try again."
            }
        }
    }
}

// MARK: - AnyJSON Helpers

private extension AnyJSON {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
