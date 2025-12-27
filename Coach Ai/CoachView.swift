import SwiftUI
import EventKit
import HealthKit
import Foundation

struct CoachMessage: Identifiable {
    let id = UUID()
    let text: String
    let isCoach: Bool
    let timestamp: Date = Date()
}

struct CoachResponse {
    let message: String
    let todoToAdd: (title: String, dueDate: Date?)?
    let todoToDelete: UUID?
    let goalModification: GoalModification?
    let workoutSplitToAdd: WorkoutSplit?
    let profileModification: ProfileModification?
    
    init(message: String, todoToAdd: (title: String, dueDate: Date?)? = nil, todoToDelete: UUID? = nil, goalModification: GoalModification? = nil, workoutSplitToAdd: WorkoutSplit? = nil, profileModification: ProfileModification? = nil) {
        self.message = message
        self.todoToAdd = todoToAdd
        self.todoToDelete = todoToDelete
        self.goalModification = goalModification
        self.workoutSplitToAdd = workoutSplitToAdd
        self.profileModification = profileModification
    }
}

enum ProfileModification {
    case updateHeight(Double) // in meters
    case updateWeight(Double) // in kg
    case updateGender(HKBiologicalSex)
}

enum GoalModification {
    case updatePrimaryGoal(String)
    case updateTargetWeight(Double?)
    case updateTargetSteps(Int)
    case updateTargetCalories(Int)
    case updateTargetWorkoutsPerWeek(Int)
    case addCustomGoal(CustomGoal)
    case removeCustomGoal(UUID)
}

final class CoachBot: ObservableObject {
    static let shared = CoachBot()
    
    // Use Groq for free unlimited access
    private let groqService = GroqService.shared

    @Published var messages: [CoachMessage] = [
        CoachMessage(text: "Hey! I'm your AI Coach. I'm here to help you crush your fitness goals, stay motivated, and build better habits. What's on your mind today? 💪", isCoach: true)
    ]
    @Published var latestCoachMessage: String = "Hey! I'm your AI Coach. I'm here to help you crush your fitness goals, stay motivated, and build better habits. What's on your mind today? 💪"
    @Published var isTyping: Bool = false
    @Published var apiError: String? = nil

    func generateResponse(to userMessage: String, health: HealthKitManager, todos: TodoStore, calories: CaloriesStore, fitnessGoals: FitnessGoalsStore, splitStore: WorkoutSplitStore, calendarManager: CalendarManager) async -> CoachResponse {
        let lowercased = userMessage.lowercased()
        
        // Parse todo addition requests (keep this functionality)
        let addTodoPatterns = ["add", "remind me", "remember", "todo", "task", "need to", "should"]
        let hasAddIntent = addTodoPatterns.contains { lowercased.contains($0) }
        
        var todoToAdd: (title: String, dueDate: Date?)? = nil
        
        if hasAddIntent {
            // Extract task title
            var taskTitle = userMessage
            for pattern in addTodoPatterns {
                if let range = lowercased.range(of: pattern) {
                    let afterPattern = String(userMessage[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !afterPattern.isEmpty && afterPattern.count > 3 {
                        taskTitle = afterPattern
                        break
                    }
                }
            }
            
            // Clean up common phrases
            taskTitle = taskTitle
                .replacingOccurrences(of: "to my list", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "to do list", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "to-do list", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "to do", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "to the list", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "that", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Parse date if mentioned
            var dueDate: Date? = nil
            let calendar = Calendar.current
            if lowercased.contains("today") {
                dueDate = calendar.startOfDay(for: Date())
            } else if lowercased.contains("tomorrow") {
                dueDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
            } else if lowercased.contains("this week") {
                dueDate = calendar.date(byAdding: .day, value: 3, to: Date())
            } else if lowercased.contains("next week") {
                dueDate = calendar.date(byAdding: .day, value: 7, to: Date())
            }
            
            if taskTitle.count > 3 && taskTitle.count < 100 {
                todoToAdd = (title: taskTitle, dueDate: dueDate)
            }
        }
        
        // Parse todo deletion requests
        var todoToDelete: UUID? = nil
        let deletePatterns = ["delete", "remove", "cancel", "get rid of"]
        let hasDeleteIntent = deletePatterns.contains { lowercased.contains($0) }
        
        if hasDeleteIntent {
            // Try to match task title from user's message
            for item in todos.items {
                if lowercased.contains(item.title.lowercased()) {
                    todoToDelete = item.id
                    break
                }
            }
        }
        
        // Parse profile modification requests
        var profileModification: ProfileModification? = nil
        
        // Height updates (e.g., "I'm 6 feet tall", "update height to 5'10\"")
        if let heightMatch = lowercased.range(of: #"(?:height|tall).*?(\d+)\s*(?:feet|ft|')\s*(\d+)?\s*(?:inches|in|"|'')?"#, options: .regularExpression) {
            let matchString = String(lowercased[heightMatch])
            let numbers = matchString.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.filter { $0 > 0 }
            if numbers.count >= 1 {
                let feet = numbers[0]
                let inches = numbers.count > 1 ? numbers[1] : 0
                let totalInches = Double(feet * 12 + inches)
                let heightInMeters = totalInches * 0.0254
                profileModification = .updateHeight(heightInMeters)
            }
        }
        
        // Weight updates (e.g., "I weigh 180 pounds", "update weight to 75 kg")
        if let weightMatch = lowercased.range(of: #"(?:weight|weigh).*?(\d+(?:\.\d+)?)\s*(?:pounds|lbs|kg|kilograms)"#, options: .regularExpression) {
            let matchString = String(lowercased[weightMatch])
            if let numberRange = matchString.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression),
               let weightValue = Double(String(matchString[numberRange])) {
                let weightInKg: Double
                if matchString.contains("pound") || matchString.contains("lb") {
                    weightInKg = weightValue * 0.453592
                } else {
                    weightInKg = weightValue
                }
                profileModification = .updateWeight(weightInKg)
            }
        }
        
        // Gender updates
        if lowercased.contains("male") || lowercased.contains("man") {
            profileModification = .updateGender(.male)
        } else if lowercased.contains("female") || lowercased.contains("woman") {
            profileModification = .updateGender(.female)
        } else if lowercased.contains("other") || lowercased.contains("non-binary") {
            profileModification = .updateGender(.other)
        }
        
        // Parse goal modification requests
        var goalModification: GoalModification? = nil
        
        // Parse step goal changes
        if let stepMatch = lowercased.range(of: #"step.*goal.*(\d+)"#, options: .regularExpression) {
            let numberString = String(lowercased[stepMatch])
            if let number = Int(numberString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                goalModification = .updateTargetSteps(number)
            }
        } else if let stepMatch = lowercased.range(of: #"(\d+).*step"#, options: .regularExpression) {
            let numberString = String(lowercased[stepMatch])
            if let number = Int(numberString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                goalModification = .updateTargetSteps(number)
            }
        }
        
        // Parse target weight changes
        if let weightMatch = lowercased.range(of: #"target.*weight.*(\d+)"#, options: .regularExpression) {
            let numberString = String(lowercased[weightMatch])
            if let number = Double(numberString.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()) {
                // Convert lbs to kg if mentioned
                if lowercased.contains("lb") || lowercased.contains("pound") {
                    goalModification = .updateTargetWeight(number / 2.20462)
                } else {
                    goalModification = .updateTargetWeight(number)
                }
            }
        } else if let weightMatch = lowercased.range(of: #"weight.*goal.*(\d+)"#, options: .regularExpression) {
            let numberString = String(lowercased[weightMatch])
            if let number = Double(numberString.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()) {
                if lowercased.contains("lb") || lowercased.contains("pound") {
                    goalModification = .updateTargetWeight(number / 2.20462)
                } else {
                    goalModification = .updateTargetWeight(number)
                }
            }
        }
        
        // Parse calorie goal changes
        if let calorieMatch = lowercased.range(of: #"calorie.*goal.*(\d+)"#, options: .regularExpression) {
            let numberString = String(lowercased[calorieMatch])
            if let number = Int(numberString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                goalModification = .updateTargetCalories(number)
            }
        } else if let calorieMatch = lowercased.range(of: #"burn.*(\d+).*calorie"#, options: .regularExpression) {
            let numberString = String(lowercased[calorieMatch])
            if let number = Int(numberString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                goalModification = .updateTargetCalories(number)
            }
        }
        
        // Parse workouts per week changes
        if let workoutMatch = lowercased.range(of: #"workout.*(\d+)"#, options: .regularExpression) {
            let numberString = String(lowercased[workoutMatch])
            if let number = Int(numberString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()), number > 0 && number <= 7 {
                goalModification = .updateTargetWorkoutsPerWeek(number)
            }
        }
        
        // Parse primary goal changes
        if lowercased.contains("primary goal") || lowercased.contains("main goal") {
            if lowercased.contains("lose weight") || lowercased.contains("weight loss") {
                goalModification = .updatePrimaryGoal("Lose Weight")
            } else if lowercased.contains("build muscle") || lowercased.contains("gain muscle") {
                goalModification = .updatePrimaryGoal("Build Muscle")
            } else if lowercased.contains("maintain") {
                goalModification = .updatePrimaryGoal("Maintain Fitness")
            } else if lowercased.contains("endurance") || lowercased.contains("cardio") {
                goalModification = .updatePrimaryGoal("Improve Endurance")
            }
        }
        
        // Parse custom goal additions - match to predefined fitness goals
        if lowercased.contains("add goal") || lowercased.contains("new goal") || lowercased.contains("set goal") || lowercased.contains("add fitness goal") {
            // Try to match user's request to a predefined goal
            var matchedGoal: PredefinedFitnessGoal? = nil
            
            for predefinedGoal in PredefinedFitnessGoal.allCases {
                let goalLower = predefinedGoal.rawValue.lowercased()
                if lowercased.contains(goalLower) || goalLower.contains(lowercased) {
                    matchedGoal = predefinedGoal
                    break
                }
            }
            
            // Also check for common variations
            if matchedGoal == nil {
                if lowercased.contains("5k") || lowercased.contains("5 k") {
                    matchedGoal = .run5K
                } else if lowercased.contains("10k") || lowercased.contains("10 k") {
                    matchedGoal = .run10K
                } else if lowercased.contains("marathon") {
                    matchedGoal = .runMarathon
                } else if (lowercased.contains("lose") && lowercased.contains("10")) || lowercased.contains("lose ten") {
                    matchedGoal = .lose10lbs
                } else if (lowercased.contains("lose") && lowercased.contains("20")) || lowercased.contains("lose twenty") {
                    matchedGoal = .lose20lbs
                } else if (lowercased.contains("gain") && lowercased.contains("10")) || lowercased.contains("gain ten") {
                    matchedGoal = .gain10lbs
                } else if lowercased.contains("bench") && (lowercased.contains("225") || lowercased.contains("two twenty five")) {
                    matchedGoal = .benchPress225
                } else if lowercased.contains("squat") && (lowercased.contains("315") || lowercased.contains("three fifteen")) {
                    matchedGoal = .squat315
                } else if lowercased.contains("deadlift") && (lowercased.contains("405") || lowercased.contains("four oh five")) {
                    matchedGoal = .deadlift405
                } else if lowercased.contains("push") && (lowercased.contains("100") || lowercased.contains("hundred")) {
                    matchedGoal = .do100Pushups
                } else if lowercased.contains("pull") && (lowercased.contains("50") || lowercased.contains("fifty")) {
                    matchedGoal = .do50Pullups
                }
            }
            
            if let matched = matchedGoal {
                // Parse deadline if mentioned
                var deadline: Date? = nil
                let calendar = Calendar.current
                if lowercased.contains("in 30 days") || lowercased.contains("within 30 days") {
                    deadline = calendar.date(byAdding: .day, value: 30, to: Date())
                } else if lowercased.contains("in 3 months") || lowercased.contains("within 3 months") {
                    deadline = calendar.date(byAdding: .month, value: 3, to: Date())
                } else if lowercased.contains("in 6 months") || lowercased.contains("within 6 months") {
                    deadline = calendar.date(byAdding: .month, value: 6, to: Date())
                }
                
                let customGoal = CustomGoal(
                    goalType: matched,
                    targetDate: deadline
                )
                goalModification = .addCustomGoal(customGoal)
            }
        }
        
        // Parse workout split creation requests
        var workoutSplitToAdd: WorkoutSplit? = nil
        // Expanded patterns to detect split creation requests
        let splitPatterns = [
            "workout split", "workout plan", "training split", "exercise plan",
            "create a split", "make me a split", "build a workout", "make a split",
            "add to splits", "add to my splits", "add that to splits", "add that to my splits",
            "save that split", "save that workout", "add that workout", "add that plan",
            "add it to splits", "save it to splits", "add this split", "save this split",
            "add split", "new split", "another split", "one more split"
        ]
        let hasSplitIntent = splitPatterns.contains { lowercased.contains($0) }
        
        if hasSplitIntent {
            // Extract split name and determine split type
            var splitName = "Custom Workout Split"
            var splitType: String = "custom"
            
            if lowercased.contains("push pull legs") || lowercased.contains("ppl") {
                splitName = "Push/Pull/Legs"
                splitType = "ppl"
            } else if lowercased.contains("upper lower") {
                splitName = "Upper/Lower"
                splitType = "upperlower"
            } else if lowercased.contains("full body") {
                splitName = "Full Body"
                splitType = "fullbody"
            } else if lowercased.contains("bro split") {
                splitName = "Bro Split"
                splitType = "bro"
            } else if lowercased.contains("lose weight") || lowercased.contains("weight loss") {
                splitName = "Weight Loss & Muscle Gain"
                splitType = "weightloss"
            }
            
            // Create a complete split structure with days and exercises
            // We'll create all 7 days, with rest days for days without exercises
            let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            var days: [WorkoutDay] = []
            
            switch splitType {
            case "ppl":
                // Push/Pull/Legs - 6 days
                days = [
                    WorkoutDay(dayOfWeek: "Monday", exercises: [
                        Exercise(name: "Bench Press", sets: 4, reps: 8),
                        Exercise(name: "Overhead Press", sets: 3, reps: 10),
                        Exercise(name: "Tricep Dips", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Tuesday", exercises: [
                        Exercise(name: "Deadlift", sets: 4, reps: 6),
                        Exercise(name: "Barbell Rows", sets: 4, reps: 8),
                        Exercise(name: "Pull-ups", sets: 3, reps: 10)
                    ]),
                    WorkoutDay(dayOfWeek: "Wednesday", exercises: [
                        Exercise(name: "Squats", sets: 4, reps: 8),
                        Exercise(name: "Leg Press", sets: 3, reps: 12),
                        Exercise(name: "Leg Curls", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Thursday", exercises: [
                        Exercise(name: "Incline Bench Press", sets: 4, reps: 8),
                        Exercise(name: "Lateral Raises", sets: 3, reps: 12),
                        Exercise(name: "Tricep Extensions", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Friday", exercises: [
                        Exercise(name: "Bent-Over Rows", sets: 4, reps: 8),
                        Exercise(name: "Lat Pulldowns", sets: 3, reps: 10),
                        Exercise(name: "Bicep Curls", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Saturday", exercises: [
                        Exercise(name: "Romanian Deadlifts", sets: 4, reps: 8),
                        Exercise(name: "Lunges", sets: 3, reps: 12),
                        Exercise(name: "Calf Raises", sets: 3, reps: 15)
                    ])
                ]
            case "upperlower":
                // Upper/Lower - 4 days
                days = [
                    WorkoutDay(dayOfWeek: "Monday", exercises: [
                        Exercise(name: "Bench Press", sets: 4, reps: 8),
                        Exercise(name: "Barbell Rows", sets: 4, reps: 8),
                        Exercise(name: "Overhead Press", sets: 3, reps: 10),
                        Exercise(name: "Pull-ups", sets: 3, reps: 10)
                    ]),
                    WorkoutDay(dayOfWeek: "Tuesday", exercises: [
                        Exercise(name: "Squats", sets: 4, reps: 8),
                        Exercise(name: "Romanian Deadlifts", sets: 4, reps: 8),
                        Exercise(name: "Leg Press", sets: 3, reps: 12),
                        Exercise(name: "Leg Curls", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Thursday", exercises: [
                        Exercise(name: "Incline Bench Press", sets: 4, reps: 8),
                        Exercise(name: "Lat Pulldowns", sets: 4, reps: 10),
                        Exercise(name: "Lateral Raises", sets: 3, reps: 12),
                        Exercise(name: "Bicep Curls", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Friday", exercises: [
                        Exercise(name: "Deadlift", sets: 4, reps: 6),
                        Exercise(name: "Lunges", sets: 3, reps: 12),
                        Exercise(name: "Calf Raises", sets: 3, reps: 15),
                        Exercise(name: "Leg Extensions", sets: 3, reps: 12)
                    ])
                ]
            case "fullbody":
                // Full Body - 3 days
                days = [
                    WorkoutDay(dayOfWeek: "Monday", exercises: [
                        Exercise(name: "Squats", sets: 4, reps: 8),
                        Exercise(name: "Bench Press", sets: 4, reps: 8),
                        Exercise(name: "Barbell Rows", sets: 4, reps: 8),
                        Exercise(name: "Overhead Press", sets: 3, reps: 10)
                    ]),
                    WorkoutDay(dayOfWeek: "Wednesday", exercises: [
                        Exercise(name: "Deadlift", sets: 4, reps: 6),
                        Exercise(name: "Incline Bench Press", sets: 4, reps: 8),
                        Exercise(name: "Pull-ups", sets: 3, reps: 10),
                        Exercise(name: "Lunges", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Friday", exercises: [
                        Exercise(name: "Romanian Deadlifts", sets: 4, reps: 8),
                        Exercise(name: "Dumbbell Press", sets: 4, reps: 10),
                        Exercise(name: "Lat Pulldowns", sets: 3, reps: 10),
                        Exercise(name: "Leg Press", sets: 3, reps: 12)
                    ])
                ]
            case "weightloss":
                // Weight Loss & Muscle Gain - 5 days with cardio focus
                days = [
                    WorkoutDay(dayOfWeek: "Monday", exercises: [
                        Exercise(name: "Squats", sets: 4, reps: 12),
                        Exercise(name: "Bench Press", sets: 4, reps: 10),
                        Exercise(name: "Barbell Rows", sets: 4, reps: 10),
                        Exercise(name: "Cardio (20 min)", sets: 1, reps: 1)
                    ]),
                    WorkoutDay(dayOfWeek: "Tuesday", exercises: [
                        Exercise(name: "Deadlift", sets: 4, reps: 8),
                        Exercise(name: "Overhead Press", sets: 3, reps: 10),
                        Exercise(name: "Pull-ups", sets: 3, reps: 10),
                        Exercise(name: "Cardio (20 min)", sets: 1, reps: 1)
                    ]),
                    WorkoutDay(dayOfWeek: "Wednesday", exercises: [
                        Exercise(name: "Lunges", sets: 3, reps: 12),
                        Exercise(name: "Incline Bench Press", sets: 4, reps: 10),
                        Exercise(name: "Lat Pulldowns", sets: 3, reps: 12),
                        Exercise(name: "Cardio (30 min)", sets: 1, reps: 1)
                    ]),
                    WorkoutDay(dayOfWeek: "Thursday", exercises: [
                        Exercise(name: "Romanian Deadlifts", sets: 4, reps: 10),
                        Exercise(name: "Dumbbell Press", sets: 4, reps: 12),
                        Exercise(name: "Bent-Over Rows", sets: 4, reps: 10),
                        Exercise(name: "Cardio (20 min)", sets: 1, reps: 1)
                    ]),
                    WorkoutDay(dayOfWeek: "Friday", exercises: [
                        Exercise(name: "Leg Press", sets: 4, reps: 15),
                        Exercise(name: "Cable Flies", sets: 3, reps: 12),
                        Exercise(name: "Cable Rows", sets: 3, reps: 12),
                        Exercise(name: "Cardio (30 min)", sets: 1, reps: 1)
                    ])
                ]
            default:
                // Custom - create a basic 5-day split
                days = [
                    WorkoutDay(dayOfWeek: "Monday", exercises: [
                        Exercise(name: "Bench Press", sets: 4, reps: 8),
                        Exercise(name: "Barbell Rows", sets: 4, reps: 8),
                        Exercise(name: "Overhead Press", sets: 3, reps: 10)
                    ]),
                    WorkoutDay(dayOfWeek: "Tuesday", exercises: [
                        Exercise(name: "Squats", sets: 4, reps: 8),
                        Exercise(name: "Leg Press", sets: 3, reps: 12),
                        Exercise(name: "Leg Curls", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Wednesday", exercises: [
                        Exercise(name: "Deadlift", sets: 4, reps: 6),
                        Exercise(name: "Pull-ups", sets: 3, reps: 10),
                        Exercise(name: "Bicep Curls", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Thursday", exercises: [
                        Exercise(name: "Incline Bench Press", sets: 4, reps: 8),
                        Exercise(name: "Lateral Raises", sets: 3, reps: 12),
                        Exercise(name: "Tricep Dips", sets: 3, reps: 12)
                    ]),
                    WorkoutDay(dayOfWeek: "Friday", exercises: [
                        Exercise(name: "Romanian Deadlifts", sets: 4, reps: 8),
                        Exercise(name: "Lunges", sets: 3, reps: 12),
                        Exercise(name: "Calf Raises", sets: 3, reps: 15)
                    ])
                ]
            }
            
            // Ensure all 7 days are present (fill missing days as rest days)
            var allDays: [WorkoutDay] = []
            for dayName in weekDays {
                if let existingDay = days.first(where: { $0.dayOfWeek == dayName }) {
                    allDays.append(existingDay)
                } else {
                    // Create rest day
                    allDays.append(WorkoutDay(dayOfWeek: dayName, exercises: []))
                }
            }
            
            // Create a new split with a unique ID
            let newSplit = WorkoutSplit(name: splitName, days: allDays, summary: "")
            workoutSplitToAdd = newSplit
            print("🏗️ Created initial split structure: '\(splitName)' (ID: \(newSplit.id.uuidString.prefix(8)))")
        }
        
        // Check if Groq API key is set
        guard groqService.hasAPIKey else {
            // Fallback response if no API key
            if let todo = todoToAdd {
                return CoachResponse(
                    message: "Got it! I've added '\(todo.title)' to your tasks. To get AI-powered coaching, please add your Groq API key in settings. 💪",
                    todoToAdd: todo,
                    todoToDelete: todoToDelete,
                    goalModification: goalModification,
                    workoutSplitToAdd: workoutSplitToAdd,
                    profileModification: profileModification
                )
            }
            return CoachResponse(
                message: "I'd love to help! To enable AI coaching, please add your Groq API key. You can get one at https://console.groq.com. Once added, I'll be your expert fitness coach! 💪",
                todoToDelete: todoToDelete,
                goalModification: goalModification,
                workoutSplitToAdd: workoutSplitToAdd,
                profileModification: profileModification
            )
        }
        
        // Build context string
        let context = buildContext(health: health, todos: todos, calories: calories, fitnessGoals: fitnessGoals, splitStore: splitStore, calendarManager: calendarManager)
        
        // Use Groq for AI responses
        do {
            let aiResponse: String
            aiResponse = try await groqService.generateResponse(
                userMessage: userMessage,
                context: context,
                conversationHistory: messages
            )
            
            // Parse workout split from AI response if one was requested OR if the response contains a split
            var finalSplit = workoutSplitToAdd
            var finalMessage = aiResponse
            
            // Check if AI response contains a workout split (even if user didn't explicitly request it)
            let responseHasSplit = aiResponse.contains("WORKOUT_SPLIT_START") && aiResponse.contains("WORKOUT_SPLIT_END")
            
            // If user wants to add a split but current response doesn't have one, check conversation history
            if hasSplitIntent && !responseHasSplit && workoutSplitToAdd == nil {
                // Look for the most recent message in conversation history that contains a split
                for message in messages.reversed() {
                    if message.isCoach && message.text.contains("WORKOUT_SPLIT_START") && message.text.contains("WORKOUT_SPLIT_END") {
                        print("📋 Found split in conversation history, extracting...")
                        // Create a basic split structure to parse into
                        let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
                        let allDays = weekDays.map { WorkoutDay(dayOfWeek: $0, exercises: []) }
                        let basicSplit = WorkoutSplit(name: "Custom Workout Split", days: allDays, summary: "")
                        
                        if let parsedSplit = parseWorkoutSplitFromResponse(message.text, originalSplit: basicSplit) {
                            finalSplit = parsedSplit
                            print("✅ Successfully extracted split from conversation history")
                            break
                        }
                    }
                }
            }
            
            if hasSplitIntent || responseHasSplit {
                // Try to parse the split from AI response
                if let parsedSplit = parseWorkoutSplitFromResponse(aiResponse, originalSplit: workoutSplitToAdd) {
                    finalSplit = parsedSplit
                    // Remove the structured format from the message for cleaner display
                    finalMessage = cleanWorkoutSplitFromMessage(aiResponse)
                    print("✅ Successfully parsed workout split from AI response")
                } else if let originalSplit = workoutSplitToAdd {
                    // If parsing fails, use the original split (with basic structure)
                    finalSplit = originalSplit
                    print("⚠️ Could not parse workout split from AI response, using original split structure")
                } else if responseHasSplit {
                    // AI created a split but we don't have an original - create a basic one
                    print("⚠️ AI response contains split markers but no original split found. Creating basic split structure.")
                    let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
                    let allDays = weekDays.map { WorkoutDay(dayOfWeek: $0, exercises: []) }
                    finalSplit = WorkoutSplit(name: "Custom Workout Split", days: allDays, summary: "")
                }
            }
            
            return CoachResponse(message: finalMessage, todoToAdd: todoToAdd, todoToDelete: todoToDelete, goalModification: goalModification, workoutSplitToAdd: finalSplit, profileModification: profileModification)
        } catch {
            // Handle errors gracefully with detailed logging
            let errorDescription = error.localizedDescription
            print("❌ Groq API Error in generateResponse: \(errorDescription)")
            print("   Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("   Error domain: \(nsError.domain)")
                print("   Error code: \(nsError.code)")
            }
            
            await MainActor.run {
                apiError = errorDescription
            }
            
            // Fallback response with more helpful error message
            let errorMessage: String
            if errorDescription.contains("429") || errorDescription.contains("rate limit") || errorDescription.contains("Rate limit") {
                errorMessage = "I'm processing requests too quickly! The free tier has rate limits. I'll automatically retry in a few seconds - please wait a moment and try again. 💪"
            } else if errorDescription.contains("401") || errorDescription.contains("authentication") {
                errorMessage = "Please check your Groq API key in settings. You can get a free key from https://console.groq.com 💪"
            } else if errorDescription.contains("400") {
                errorMessage = "There was an issue with the API request. Please try again or check your API key. 💪"
            } else if errorDescription.contains("network") || errorDescription.contains("connection") {
                errorMessage = "I'm having trouble connecting to the API. Please check your internet connection. 💪"
            } else {
                errorMessage = "I'm having trouble connecting right now. Error: \(errorDescription). Please check your API key and internet connection. 💪"
            }
            
            if let todo = todoToAdd {
                return CoachResponse(
                    message: "Got it! I've added '\(todo.title)' to your tasks. (Note: AI response unavailable) 💪",
                    todoToAdd: todo,
                    todoToDelete: todoToDelete,
                    goalModification: goalModification,
                    workoutSplitToAdd: workoutSplitToAdd,
                    profileModification: profileModification
                )
            }
            
            return CoachResponse(
                message: errorMessage,
                todoToDelete: todoToDelete,
                goalModification: goalModification,
                workoutSplitToAdd: workoutSplitToAdd,
                profileModification: profileModification
            )
        }
    }
    
    private func buildContext(health: HealthKitManager, todos: TodoStore, calories: CaloriesStore, fitnessGoals: FitnessGoalsStore, splitStore: WorkoutSplitStore, calendarManager: CalendarManager) -> String {
        var context = "**User's Complete Fitness Profile:**\n\n"
        
        // Physical Profile
        context += "**Physical Profile:**\n"
        if health.height > 0 {
            let totalInches = health.height * 39.3701
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            context += "- Height: \(feet)'\(inches)\"\n"
        } else {
            context += "- Height: Not set\n"
        }
        
        if health.weight > 0 {
            let pounds = health.weight * 2.20462
            context += "- Weight: \(String(format: "%.1f", pounds)) lbs\n"
        } else {
            context += "- Weight: Not set\n"
        }
        
        let genderString: String
        switch health.biologicalSex {
        case .female: genderString = "Female"
        case .male: genderString = "Male"
        case .other: genderString = "Other"
        default: genderString = "Not set"
        }
        context += "- Gender: \(genderString)\n\n"
        
        // Today's Activity Stats
        context += "**Today's Activity:**\n"
        context += "- Steps: \(health.todaySteps) (Goal: \(fitnessGoals.goals.targetSteps))\n"
        context += "- Active calories burned: \(Int(health.todayActiveEnergy)) (Goal: \(fitnessGoals.goals.targetCalories))\n"
        
        if health.activeHeartRate > 0 {
            context += "- Active heart rate: \(Int(health.activeHeartRate)) bpm\n"
        }
        if health.averageHeartRate > 0 {
            context += "- Average heart rate today: \(Int(health.averageHeartRate)) bpm\n"
        }
        context += "\n"
        
        // Fitness Goals
        context += "**Fitness Goals:**\n"
        context += "- Primary goal: \(fitnessGoals.goals.primaryGoal)\n"
        if let targetWeight = fitnessGoals.goals.targetWeight {
            let pounds = targetWeight * 2.20462
            context += "- Target weight: \(String(format: "%.1f", pounds)) lbs\n"
        }
        context += "- Daily steps goal: \(fitnessGoals.goals.targetSteps)\n"
        context += "- Daily calories burn goal: \(fitnessGoals.goals.targetCalories)\n"
        context += "- Workouts per week goal: \(fitnessGoals.goals.targetWorkoutsPerWeek)\n"
        
        // Custom Goals
        if !fitnessGoals.goals.customGoals.isEmpty {
            context += "- Custom goals:\n"
            for customGoal in fitnessGoals.goals.customGoals {
                context += "  • \(customGoal.title)"
                context += " - \(customGoal.description)"
                if let targetDate = customGoal.targetDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .none
                    context += " (Target Date: \(formatter.string(from: targetDate)))"
                }
                if customGoal.isCompleted {
                    context += " [Completed]"
                }
                context += "\n"
            }
        }
        context += "\n"
        
        // Tasks & To-Do List
        context += "**Tasks & To-Do List:**\n"
        context += "- Total: \(todos.completedItems.count) completed, \(todos.activeItems.count) active\n"
        context += "- Task completion: \(Int(todos.completionPercentage * 100))%\n"
        
        let overdue = todos.activeItems.filter { $0.isOverdue }
        if !overdue.isEmpty {
            context += "- Overdue tasks (\(overdue.count)):\n"
            for task in overdue.prefix(5) {
                context += "  • \(task.title)"
                if let dueDate = task.dueDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    context += " (was due: \(formatter.string(from: dueDate)))"
                }
                context += "\n"
            }
        }
        
        let dueSoon = todos.activeItems.filter { $0.isDueSoon && !$0.isOverdue }
        if !dueSoon.isEmpty {
            context += "- Due soon (\(dueSoon.count)):\n"
            for task in dueSoon.prefix(5) {
                context += "  • \(task.title)"
                if let dueDate = task.dueDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    context += " (due: \(formatter.string(from: dueDate)))"
                }
                context += "\n"
            }
        }
        
        let todayTasks = todos.todayItems
        if !todayTasks.isEmpty {
            context += "- Today's tasks (\(todayTasks.count)):\n"
            for task in todayTasks.prefix(5) {
                context += "  • \(task.title)\n"
            }
        }
        
        let upcomingTasks = todos.activeItems.filter { !$0.isOverdue && !$0.isDueSoon && $0.dueDate != nil }
        if !upcomingTasks.isEmpty {
            context += "- Upcoming tasks (\(upcomingTasks.count)):\n"
            for task in upcomingTasks.prefix(5) {
                context += "  • \(task.title)"
                if let dueDate = task.dueDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    context += " (due: \(formatter.string(from: dueDate)))"
                }
                context += "\n"
            }
        }
        
        let noDateTasks = todos.activeItems.filter { $0.dueDate == nil }
        if !noDateTasks.isEmpty {
            context += "- Tasks without due dates (\(noDateTasks.count)):\n"
            for task in noDateTasks.prefix(5) {
                context += "  • \(task.title)\n"
            }
        }
        context += "\n"
        
        // Calendar Events (up to 1 month in advance)
        context += "**Calendar & Schedule (Next 30 Days):**\n"
        let today = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: today)
        
        var allUpcomingEvents: [(date: Date, event: EKEvent)] = []
        for dayOffset in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) {
                let events = calendarManager.getEvents(for: date)
                for event in events {
                    allUpcomingEvents.append((date: date, event: event))
                }
            }
        }
        
        if allUpcomingEvents.isEmpty {
            context += "- No upcoming events in the next 30 days\n"
        } else {
            context += "- Upcoming events (\(allUpcomingEvents.count)):\n"
            let sortedEvents = allUpcomingEvents.sorted { $0.date < $1.date || ($0.date == $1.date && ($0.event.startDate ?? Date()) < ($1.event.startDate ?? Date())) }
            for (_, event) in sortedEvents.prefix(50) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                dateFormatter.timeStyle = .short
                
                context += "  • \(event.title ?? "Untitled Event")"
                if let startDate = event.startDate {
                    if calendar.isDate(startDate, inSameDayAs: today) {
                        context += " (Today"
                    } else if calendar.isDate(startDate, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!) {
                        context += " (Tomorrow"
                    } else {
                        dateFormatter.dateStyle = .medium
                        context += " (\(dateFormatter.string(from: startDate))"
                    }
                    dateFormatter.timeStyle = .short
                    context += " at \(dateFormatter.string(from: startDate)))"
                }
                if let location = event.location, !location.isEmpty {
                    context += " - Location: \(location)"
                }
                context += "\n"
            }
        }
        context += "\n"
        
        // Nutrition
        context += "**Nutrition Today:**\n"
        context += "- Calories: \(calories.todayTotal)/\(calories.goals.calories)\n"
        context += "- Protein: \(Int(calories.todayProtein))g/\(Int(calories.goals.protein))g\n"
        context += "- Carbs: \(Int(calories.todayCarbs))g/\(Int(calories.goals.carbs))g\n"
        context += "- Fat: \(Int(calories.todayFat))g/\(Int(calories.goals.fat))g\n"
        context += "- Fiber: \(Int(calories.todayFiber))g/\(Int(calories.goals.fiber))g\n\n"
        
        // Workout Splits
        if !splitStore.splits.isEmpty {
            context += "**Workout Splits:**\n"
            for split in splitStore.splits {
                context += "- \(split.name): \(split.days.count) days per week\n"
                for day in split.days {
                    context += "  • \(day.dayOfWeek): \(day.exercises.count) exercises"
                    if !day.exercises.isEmpty {
                        context += " ("
                        context += day.exercises.prefix(3).map { "\($0.name) \($0.sets)×\($0.reps)" }.joined(separator: ", ")
                        if day.exercises.count > 3 {
                            context += ", ..."
                        }
                        context += ")"
                    }
                    context += "\n"
                }
            }
            context += "\n"
        }
        
        return context
    }
    
    private func parseWorkoutSplitFromResponse(_ response: String, originalSplit: WorkoutSplit?) -> WorkoutSplit? {
        guard let originalSplit = originalSplit else { return nil }
        
        // Extract workout split section
        guard let splitStart = response.range(of: "WORKOUT_SPLIT_START"),
              let splitEnd = response.range(of: "WORKOUT_SPLIT_END") else {
            return nil
        }
        
        let splitContent = String(response[splitStart.upperBound..<splitEnd.lowerBound])
        
        // Extract summary
        var summary = ""
        if let summaryStart = response.range(of: "SUMMARY_START"),
           let summaryEnd = response.range(of: "SUMMARY_END") {
            summary = String(response[summaryStart.upperBound..<summaryEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Parse days
        let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var parsedDays: [WorkoutDay] = []
        
        let lines = splitContent.components(separatedBy: .newlines)
        var currentDay: String? = nil
        var currentExercises: [Exercise] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Check if this is a day header
            if let day = weekDays.first(where: { trimmed.hasPrefix($0) || trimmed == $0 || trimmed == "\($0):" }) {
                // Save previous day if exists
                if let prevDay = currentDay {
                    parsedDays.append(WorkoutDay(dayOfWeek: prevDay, exercises: currentExercises))
                }
                currentDay = day
                currentExercises = []
            } else if trimmed.hasPrefix("- ") {
                // This is an exercise line
                let exerciseText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                
                // Parse exercise name and sets/reps
                // Format: "Exercise Name: X sets × Y reps" or "Exercise Name: X sets x Y reps"
                if let colonRange = exerciseText.range(of: ":") {
                    let exerciseName = String(exerciseText[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let setsRepsText = String(exerciseText[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    
                    // Check if it's a rest day
                    if exerciseName.lowercased().contains("rest day") || setsRepsText.lowercased().contains("rest day") {
                        // Rest day - no exercises
                        continue
                    }
                    
                    // Parse sets and reps
                    // Look for patterns like "4 sets × 8-12 reps" or "3 sets x 10 reps"
                    let setsRepsPattern = #"(\d+)\s*sets?\s*[×x]\s*(\d+)(?:\s*-\s*(\d+))?\s*reps?"#
                    if let regex = try? NSRegularExpression(pattern: setsRepsPattern, options: .caseInsensitive),
                       let match = regex.firstMatch(in: setsRepsText, range: NSRange(setsRepsText.startIndex..., in: setsRepsText)) {
                        
                        if let setsRange = Range(match.range(at: 1), in: setsRepsText),
                           let repsRange = Range(match.range(at: 2), in: setsRepsText),
                           let sets = Int(setsRepsText[setsRange]),
                           let reps = Int(setsRepsText[repsRange]) {
                            
                            currentExercises.append(Exercise(name: exerciseName, sets: sets, reps: reps))
                        }
                    }
                }
            }
        }
        
        // Save last day
        if let lastDay = currentDay {
            parsedDays.append(WorkoutDay(dayOfWeek: lastDay, exercises: currentExercises))
        }
        
        // Ensure all 7 days are present
        var allDays: [WorkoutDay] = []
        for dayName in weekDays {
            if let existingDay = parsedDays.first(where: { $0.dayOfWeek == dayName }) {
                allDays.append(existingDay)
            } else {
                // Create rest day
                allDays.append(WorkoutDay(dayOfWeek: dayName, exercises: []))
            }
        }
        
        // Create updated split - preserve the original ID to ensure uniqueness
        var updatedSplit = originalSplit
        updatedSplit.days = allDays
        updatedSplit.summary = summary
        
        print("📝 Parsed split from AI response: '\(updatedSplit.name)' (ID: \(updatedSplit.id.uuidString.prefix(8)))")
        print("   Days: \(updatedSplit.days.count), Summary length: \(updatedSplit.summary.count)")
        
        return updatedSplit
    }
    
    private func cleanWorkoutSplitFromMessage(_ message: String) -> String {
        // Remove the structured format markers for cleaner display
        var cleaned = message
        
        // Remove WORKOUT_SPLIT_START and WORKOUT_SPLIT_END
        cleaned = cleaned.replacingOccurrences(of: "WORKOUT_SPLIT_START", with: "")
        cleaned = cleaned.replacingOccurrences(of: "WORKOUT_SPLIT_END", with: "")
        cleaned = cleaned.replacingOccurrences(of: "SUMMARY_START", with: "")
        cleaned = cleaned.replacingOccurrences(of: "SUMMARY_END", with: "")
        
        // Clean up extra whitespace
        cleaned = cleaned.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func userSaid(_ text: String, health: HealthKitManager, todos: TodoStore, calories: CaloriesStore, fitnessGoals: FitnessGoalsStore, splitStore: WorkoutSplitStore, calendarManager: CalendarManager) {
        // Add user message
        self.messages.append(CoachMessage(text: text, isCoach: false))
        
        // Show typing indicator
        self.isTyping = true
        
        // Generate response using Groq
        Task {
            let response = await self.generateResponse(to: text, health: health, todos: todos, calories: calories, fitnessGoals: fitnessGoals, splitStore: splitStore, calendarManager: calendarManager)
            
            await MainActor.run {
                self.isTyping = false
                
                // Add todo if coach suggested one
                if let todo = response.todoToAdd {
                    todos.add(todo.title, dueDate: todo.dueDate)
                }
                
                // Apply goal modifications
                if let goalMod = response.goalModification {
                    switch goalMod {
                    case .updatePrimaryGoal(let goal):
                        fitnessGoals.updatePrimaryGoal(goal)
                    case .updateTargetWeight(let weight):
                        fitnessGoals.updateTargetWeight(weight)
                    case .updateTargetSteps(let steps):
                        fitnessGoals.updateTargetSteps(steps)
                    case .updateTargetCalories(let calories):
                        fitnessGoals.updateTargetCalories(calories)
                    case .updateTargetWorkoutsPerWeek(let workouts):
                        fitnessGoals.updateTargetWorkoutsPerWeek(workouts)
                    case .addCustomGoal(let goal):
                        fitnessGoals.addCustomGoal(goal)
                    case .removeCustomGoal(let id):
                        if let goal = fitnessGoals.goals.customGoals.first(where: { $0.id == id }) {
                            fitnessGoals.removeCustomGoal(goal)
                        }
                    }
                }
                
                // Add workout split if coach created one
                if var split = response.workoutSplitToAdd {
                    // Ensure all 7 days are present
                    let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
                    var allDays: [WorkoutDay] = []
                    for dayName in weekDays {
                        if let existingDay = split.days.first(where: { $0.dayOfWeek == dayName }) {
                            allDays.append(existingDay)
                        } else {
                            // Create rest day
                            allDays.append(WorkoutDay(dayOfWeek: dayName, exercises: []))
                        }
                    }
                    split.days = allDays
                    
                    // Count existing "Coach AI split" splits to determine the number
                    // Get the latest count from the store to ensure uniqueness
                    let existingAISplits = splitStore.splits.filter { $0.name.hasPrefix("Coach AI split") }
                    
                    // Find the highest number used to avoid conflicts
                    var maxNumber = 0
                    for existingSplit in existingAISplits {
                        let name = existingSplit.name
                        if let numberRange = name.range(of: #"\d+"#, options: .regularExpression) {
                            if let number = Int(name[numberRange]) {
                                maxNumber = max(maxNumber, number)
                            }
                        }
                    }
                    
                    // Use the next available number
                    let splitNumber = maxNumber + 1
                    split.name = "Coach AI split \(splitNumber)"
                    
                    print("🔄 Adding workout split to store:")
                    print("   Name: \(split.name)")
                    print("   Split ID: \(split.id.uuidString.prefix(8))")
                    print("   Days: \(split.days.count)")
                    print("   Existing AI splits: \(existingAISplits.count)")
                    print("   Max number found: \(maxNumber), using: \(splitNumber)")
                    print("   Current total splits: \(splitStore.splits.count)")
                    
                    splitStore.addSplit(split)
                    
                    // Verify it was added
                    let newCount = splitStore.splits.count
                    print("✅ Split added. New total splits in store: \(newCount)")
                    print("   All split names: \(splitStore.splits.map { $0.name }.joined(separator: ", "))")
                } else {
                    print("⚠️ No workout split in response (workoutSplitToAdd is nil)")
                }
                
                let reply = CoachMessage(text: response.message, isCoach: true)
                self.messages.append(reply)
                self.latestCoachMessage = response.message
            }
        }
    }
}

struct CoachView: View {
    @StateObject private var coach = CoachBot.shared
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var todos = TodoStore.shared
    @StateObject private var calories = CaloriesStore.shared
    @StateObject private var fitnessGoals = FitnessGoalsStore.shared
    @StateObject private var splitStore = WorkoutSplitStore.shared
    @StateObject private var calendarManager = CalendarManager.shared
    @State private var input: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showAPISettings = false
    @State private var apiKeyInput = ""

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 16) {
                                ForEach(coach.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                                
                                if coach.isTyping {
                                    HStack {
                                        TypingIndicator()
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .id("typing-indicator") // Give it an ID for scrolling
                                }
                            }
                            .padding(.vertical, 20)
                        }
                        .onChange(of: coach.messages.count) { _, _ in
                            if let last = coach.messages.last {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: coach.isTyping) { oldValue, newValue in
                            if newValue {
                                // Scroll to show typing indicator when it appears
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("typing-indicator", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Input area
                    HStack(spacing: 12) {
                        TextField("Ask your coach anything...", text: $input)
                            .textFieldStyle(.plain)
                            .padding(16)
                            .background(.white.opacity(0.1))
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                            .focused($isInputFocused)
                            .onSubmit {
                                sendMessage()
                            }
                        
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.purple, Color.blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.05, blue: 0.1).opacity(0.95),
                                Color(red: 0.1, green: 0.1, blue: 0.2).opacity(0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Show Groq API key settings
                        apiKeyInput = UserDefaults.standard.string(forKey: "groq.api.key") ?? ""
                        showAPISettings = true
                    }) {
                        let hasKey = GroqService.shared.hasAPIKey
                        Image(systemName: hasKey ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(hasKey ? .green : .orange)
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("AI Coach")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showAPISettings) {
                APISettingsSheet(apiKey: $apiKeyInput, isPresented: $showAPISettings)
            }
        }
    }
    
    private func sendMessage() {
                        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
        input = "" // Clear input immediately to prevent double sends
        isInputFocused = false
        coach.userSaid(text, health: health, todos: todos, calories: calories, fitnessGoals: fitnessGoals, splitStore: splitStore, calendarManager: calendarManager)
    }
}

struct MessageBubble: View {
    let message: CoachMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isCoach {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isCoach ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if message.isCoach {
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                Color.white.opacity(0.15)
                            }
                        }
                    )
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                
                Text(message.timestamp, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 4)
            }
            
            if !message.isCoach {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct TypingIndicator: View {
    @State private var dotScales: [CGFloat] = [0.5, 0.5, 0.5]
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.white.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .scaleEffect(dotScales[index])
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: dotScales[index]
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .onAppear {
            // Start animation immediately
            for index in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                    withAnimation {
                        dotScales[index] = 1.0
                    }
                }
            }
        }
    }
}

struct APISettingsSheet: View {
    @Binding var apiKey: String
    @Binding var isPresented: Bool
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI API Key")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("Get a FREE Groq API key from https://console.groq.com\n(14,400 requests/day free, very fast!)")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        SecureField("Enter your API key...", text: $apiKey)
                            .textFieldStyle(.plain)
                            .padding(16)
                            .background(.white.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    
                    if showError {
                        Text(errorMessage)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.red)
                .padding()
                            .background(.red.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedKey.isEmpty {
                            // Remove Groq key
                            UserDefaults.standard.removeObject(forKey: "groq.api.key")
                            isPresented = false
                        } else {
                            // Save as Groq key
                            UserDefaults.standard.set(trimmedKey, forKey: "groq.api.key")
                            isPresented = false
                        }
                    }) {
                        Text(apiKey.isEmpty ? "Remove API Key" : "Save Groq API Key")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                    }
                }
                .padding(20)
            }
            .navigationTitle("API Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

#Preview {
    CoachView()
}
