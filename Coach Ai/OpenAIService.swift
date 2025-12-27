import Foundation

struct OpenAIRequest: Codable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let role: String
            let content: String
        }
    }
}

final class OpenAIService: ObservableObject {
    static let shared = OpenAIService()
    
    private let apiKeyKey = "openai.api.key"
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    var apiKey: String? {
        get {
            UserDefaults.standard.string(forKey: apiKeyKey)
        }
        set {
            if let key = newValue {
                UserDefaults.standard.set(key, forKey: apiKeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: apiKeyKey)
            }
        }
    }
    
    var hasAPIKey: Bool {
        apiKey != nil && !apiKey!.isEmpty
    }
    
    func generateResponse(
        userMessage: String,
        context: String,
        conversationHistory: [CoachMessage]
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        
        // Build conversation history
        var messages: [OpenAIRequest.Message] = []
        
        // System prompt - encouraging, stern, fitness-focused
        let systemPrompt = """
        You are an expert fitness and health coach AI assistant. Your role is to help users achieve their fitness goals through encouragement, accountability, and expert guidance.
        
        **Your Personality:**
        - Encouraging and supportive, but also firm and direct when needed
        - Always on the user's side - you want them to succeed
        - Use a mix of motivation and tough love
        - Be specific, actionable, and science-based
        - Use emojis sparingly but effectively (💪 🎯 🔥 ✅)
        
        **Your Expertise:**
        - Exercise science, nutrition, weight management, muscle building, cardiovascular health
        - Habit formation, motivation, goal setting, recovery
        - You ONLY answer questions about health, fitness, nutrition, and wellness
        - If asked about non-fitness topics, politely redirect: "I'm your fitness coach! I can help with workouts, nutrition, goals, and motivation. What fitness question can I help with?"
        
        **Your Approach:**
        - Celebrate wins but don't sugarcoat reality
        - Give specific, actionable advice
        - Use the user's data (steps, calories, tasks) to personalize responses
        - Be direct about what needs to happen, but supportive about how to get there
        - Keep responses concise but detailed (2-4 paragraphs max)
        
        **Context about the user:**
        \(context)
        
        Remember: You're here to help them become their best self. Be their biggest cheerleader AND their toughest coach.
        """
        
        messages.append(OpenAIRequest.Message(role: "system", content: systemPrompt))
        
        // Add conversation history (last 10 messages to keep context manageable)
        let recentHistory = conversationHistory.suffix(10)
        for msg in recentHistory {
            messages.append(OpenAIRequest.Message(
                role: msg.isCoach ? "assistant" : "user",
                content: msg.text
            ))
        }
        
        // Add current user message
        messages.append(OpenAIRequest.Message(role: "user", content: userMessage))
        
        // Create request
        let request = OpenAIRequest(
            model: "gpt-4o-mini", // Using mini for cost efficiency, can change to gpt-4o for better responses
            messages: messages,
            temperature: 0.7, // Balanced creativity and consistency
            max_tokens: 500 // Keep responses concise
        )
        
        // Make API call
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw OpenAIError.encodingError
        }
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorDict["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw OpenAIError.apiError(message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }
        
        do {
            let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            guard let content = openAIResponse.choices.first?.message.content else {
                throw OpenAIError.noResponse
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw OpenAIError.decodingError
        }
    }
}

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case encodingError
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noResponse
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not set. Please add your API key in settings."
        case .invalidURL:
            return "Invalid API URL"
        case .encodingError:
            return "Failed to encode request"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .noResponse:
            return "No response from AI"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

