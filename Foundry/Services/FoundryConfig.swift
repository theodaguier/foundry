import Foundation

enum FoundryConfig {
    // MARK: - Supabase

    /// Replace these with your Supabase project credentials.
    /// For production, inject via .xcconfig or build settings instead of hardcoding.
    static let supabaseURL: URL = {
        guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              let url = URL(string: urlString)
        else {
            // Fallback for development — replace with your project URL
            return URL(string: "https://bpqqfpdaigphewgobmpe.supabase.co")!
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        if let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !key.isEmpty {
            return key
        }
        // Fallback for development — replace with your anon key
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJwcXFmcGRhaWdwaGV3Z29ibXBlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwODc3NTYsImV4cCI6MjA4OTY2Mzc1Nn0.YKFmmJk39st-P68Dvztn9YHSCteXWGAvMNyM3hNofy4"
    }()
}
