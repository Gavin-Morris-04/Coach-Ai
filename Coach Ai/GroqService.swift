import Foundation

final class GroqService {
    static let shared = GroqService()
    
    // Groq offers free API access - you can get a key from https://console.groq.com
    // Free tier: ~14,400 requests/day, very fast responses
    
    var apiKey: String? {
        // Priority order:
        // 1. User-set key in UserDefaults (from settings - most common)
        // 2. Environment variable (for CI/CD or secure deployment)
        // 3. Config.swift static property (if file exists in project)
        
        // Check UserDefaults first (user can set via settings)
        if let savedKey = UserDefaults.standard.string(forKey: "groq.api.key"), !savedKey.isEmpty {
            return savedKey
        }
        
        // Check environment variable (for CI/CD or secure deployment)
        // Set this in Xcode: Edit Scheme > Run > Arguments > Environment Variables
        if let envKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        
        // Check Config.swift if it exists (compile-time configuration)
        // This file should be created from Config.swift.template and added to project
        // but excluded from version control
        if let configKey = Config.groqAPIKey, 
           configKey != "YOUR_GROQ_API_KEY_HERE", 
           !configKey.isEmpty {
            return configKey
        }
        
        // No key found - user must set it in settings
        return nil
    }
    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"
    
    var hasAPIKey: Bool {
        apiKey != nil && !apiKey!.isEmpty
    }
    
    struct GroqRequest: Codable {
        let model: String
        let messages: [Message]
        let temperature: Double?
        let max_tokens: Int?
        
        struct Message: Codable {
            let role: String
            let content: String
        }
    }
    
    struct GroqResponse: Codable {
        let choices: [Choice]?
        let error: ErrorResponse?
        
        struct Choice: Codable {
            let message: Message
            
            struct Message: Codable {
                let content: String
            }
        }
        
        struct ErrorResponse: Codable {
            let message: String
        }
    }
    
    func generateResponse(userMessage: String, context: String, conversationHistory: [CoachMessage], maxRetries: Int = 3) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw NSError(domain: "GroqService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not set"])
        }
        
        // Try the request with automatic retry for rate limits
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                return try await performRequest(userMessage: userMessage, context: context, conversationHistory: conversationHistory, apiKey: apiKey)
            } catch let error as NSError where error.code == 429 && attempt < maxRetries {
                // Rate limit hit - extract wait time and retry
                let waitTime = error.userInfo["retryAfter"] as? Double ?? Double(attempt * 2) // Default exponential backoff
                print("⏳ Rate limit hit (attempt \(attempt)/\(maxRetries)). Waiting \(waitTime) seconds before retry...")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                lastError = error
                continue
            } catch {
                throw error
            }
        }
        
        // If we exhausted retries, throw the last error
        throw lastError ?? NSError(domain: "GroqService", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded. Please wait a moment and try again."])
    }
    
    private func performRequest(userMessage: String, context: String, conversationHistory: [CoachMessage], apiKey: String) async throws -> String {
        
        // Build messages array
        var messages: [GroqRequest.Message] = []
        
        // System prompt with coaching instructions
        let systemPrompt = """
        You are a personal fitness and health coach. Your ONLY purpose is to provide guidance, motivation, and expert advice related to:
        
        - Physical health and fitness
        - Exercise science and training
        - Nutrition and diet
        - Weight management
        - Mental health and wellness
        - Habit formation and motivation
        - Recovery and rest
        
        **CRITICAL RULES:**
        1. You MUST ONLY respond to questions about health, fitness, nutrition, diet, exercise, and mental health
        2. If asked about ANY other topic, you MUST politely but firmly redirect: "I'm your fitness and health coach. I can only help with health, fitness, nutrition, exercise, and mental wellness. What health or fitness question can I help you with?"
        3. Never provide information outside of health, fitness, nutrition, diet, exercise, or mental health topics
        4. Always speak as a coach - be encouraging, supportive, but also direct and firm when needed
        5. Use the user's data (steps, calories, tasks, goals, calendar events, to-do lists) to personalize your responses
        6. Be SPECIFIC, DETAILED, ACTIONABLE, and SCIENCE-BASED - provide comprehensive but concise answers
        7. ALWAYS provide complete, thorough responses - don't cut off mid-sentence or give incomplete answers. If creating a workout plan, list ALL days and exercises completely - never stop mid-plan
        8. If you need more information to give a proper answer, ASK FOLLOW-UP QUESTIONS to better understand the user's situation, goals, experience level, limitations, or preferences
        9. Give detailed explanations with specific examples, numbers, and actionable steps
        10. Use emojis sparingly (💪 🎯 🔥 ✅)
        11. Keep responses concise - aim for 2-4 paragraphs maximum. Be direct and to the point while still being helpful. However, when creating workout plans or detailed lists, provide the COMPLETE plan - don't abbreviate or cut off
        12. AVOID excessive markdown formatting - use minimal asterisks (*) and avoid bold/italic unless absolutely necessary. Write naturally without heavy formatting
        13. CRITICAL: When asked to create a workout plan or split, you MUST IMMEDIATELY create the complete split with ALL 7 days and ALL exercises. Do NOT explain the format, do NOT ask for more information - just create it using real exercises with specific set/rep ranges.
        
        **WORKOUT SPLIT CREATION (CRITICAL - READ CAREFULLY):**
        When the user asks for a workout split, plan, or training program, you MUST:
        1. IMMEDIATELY create the actual workout split - do NOT explain the format, do NOT show examples, do NOT ask for more information
        2. Use REAL exercise names (e.g., "Barbell Bench Press", "Squats", "Deadlifts", "Pull-ups", "Overhead Press", "Barbell Rows")
        3. Include SPECIFIC set and rep ranges (e.g., "4 sets × 8-12 reps", "3 sets × 10 reps", "5 sets × 6 reps")
        4. Format it EXACTLY like this (create the actual split, not an example):
        
        WORKOUT_SPLIT_START
        Monday:
        - Exercise Name: X sets × Y reps
        - Exercise Name: X sets × Y reps
        Tuesday:
        - Exercise Name: X sets × Y reps
        Wednesday:
        - Exercise Name: X sets × Y reps
        Thursday:
        - Exercise Name: X sets × Y reps
        Friday:
        - Exercise Name: X sets × Y reps
        Saturday:
        - Exercise Name: X sets × Y reps (or "Rest Day" if no exercises)
        Sunday:
        - Exercise Name: X sets × Y reps (or "Rest Day" if no exercises)
        WORKOUT_SPLIT_END
        
        SUMMARY_START
        [Write a 2-3 sentence summary here including key goals, focus areas, and important notes from the user's request]
        SUMMARY_END
        
        CRITICAL RULES FOR WORKOUT SPLITS:
        - You MUST include all 7 days of the week (Monday through Sunday)
        - Use REAL exercise names (e.g., "Barbell Bench Press", "Squats", "Deadlifts", "Pull-ups", "Overhead Press", "Barbell Rows", "Leg Press", "Lunges", "Bicep Curls", "Tricep Dips")
        - Include SPECIFIC set and rep ranges (e.g., "3 sets × 8-12 reps", "4 sets × 6 reps", "5 sets × 10 reps")
        - Days without exercises should have "- Rest Day: 0 sets × 0 reps" or just "- Rest Day"
        - DO NOT explain the format - just create the split immediately
        - DO NOT show examples - create the actual split for the user
        - DO NOT ask for more information - use your knowledge to create an appropriate split based on the user's goals (weight loss, muscle gain, strength, etc.)
        - Start your response with a brief 1-2 sentence introduction, then immediately include the WORKOUT_SPLIT_START block
        
        **Context about the user:**
        \(context)
        
        Remember: You are their coach. Be their biggest cheerleader AND their toughest coach. Stay focused ONLY on health, fitness, nutrition, and mental wellness.
        """
        
        // System prompt
        messages.append(GroqRequest.Message(
            role: "system",
            content: systemPrompt
        ))
        
        // Add conversation history (last 10 messages to keep context manageable)
        let recentHistory = conversationHistory.suffix(10)
        for msg in recentHistory {
            messages.append(GroqRequest.Message(
                role: msg.isCoach ? "assistant" : "user",
                content: msg.text
            ))
        }
        
        // Add current user message
        messages.append(GroqRequest.Message(
            role: "user",
            content: userMessage
        ))
        
        let request = GroqRequest(
            model: "llama-3.1-8b-instant", // Fast and free on Groq - reliable model
            messages: messages,
            temperature: 0.7,
            max_tokens: 2048 // Reduced to avoid rate limits on free tier
        )
        
        // Debug: Print request details (without exposing API key)
        print("📤 Groq API Request:")
        print("   Model: \(request.model)")
        print("   Messages: \(messages.count)")
        print("   Max tokens: \(request.max_tokens ?? 0)")
        
        guard let url = URL(string: baseURL) else {
            throw NSError(domain: "GroqService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw NSError(domain: "GroqService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request"])
        }
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GroqService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to decode error response for better error messages
            if let errorData = try? JSONDecoder().decode(GroqResponse.ErrorResponse.self, from: data) {
                let errorMessage = errorData.message ?? "API request failed"
                print("❌ Groq API Error (\(httpResponse.statusCode)): \(errorMessage)")
                
                // Handle rate limiting (429) with retry information
                if httpResponse.statusCode == 429 {
                    // Extract wait time from error message if available
                    var waitTime: Double = 5.0 // Default 5 seconds
                    if let waitRange = errorMessage.range(of: #"try again in (\d+\.?\d*)s"#, options: .regularExpression) {
                        let waitString = String(errorMessage[waitRange])
                        if let timeRange = waitString.range(of: #"\d+\.?\d*"#, options: .regularExpression) {
                            waitTime = Double(String(waitString[timeRange])) ?? 5.0
                        }
                    }
                    throw NSError(domain: "GroqService", code: 429, userInfo: [
                        NSLocalizedDescriptionKey: errorMessage,
                        "retryAfter": waitTime
                    ])
                }
                
                throw NSError(domain: "GroqService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            // If we can't decode the error, print the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Groq API Error (\(httpResponse.statusCode)) - Raw response: \(responseString)")
            }
            throw NSError(domain: "GroqService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API request failed with status \(httpResponse.statusCode)"])
        }
        
        let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        if let error = groqResponse.error {
            throw NSError(domain: "GroqService", code: 500, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        
        guard let choice = groqResponse.choices?.first else {
            throw NSError(domain: "GroqService", code: 500, userInfo: [NSLocalizedDescriptionKey: "No response from API"])
        }
        
        return choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

