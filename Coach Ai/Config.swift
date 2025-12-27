import Foundation

/// Configuration file for API keys and sensitive data
/// 
/// ⚠️ SECURITY WARNING:
/// This file contains sensitive API keys and should NEVER be committed to version control.
/// 
/// SETUP INSTRUCTIONS:
/// 1. This file is already in .gitignore - it will not be tracked by git
/// 2. Replace "YOUR_GROQ_API_KEY_HERE" with your actual Groq API key
/// 3. Get your free Groq API key from: https://console.groq.com
/// 4. For team development, each developer should create their own Config.swift
/// 5. For production, use environment variables or secure key management
/// 
/// ALTERNATIVE: You can also set the API key via:
/// - UserDefaults (in app settings)
/// - Environment variable GROQ_API_KEY (in Xcode scheme settings)

struct Config {
    /// Groq API Key
    /// Set to nil or empty string to require user to set it in app settings
    /// Or replace with your actual API key for development
    static let groqAPIKey: String? = nil // Change to: "your_actual_api_key_here"
    
    // Note: GoogleService-Info.plist for Firebase should be added to your project
    // but is excluded from version control via .gitignore
}

