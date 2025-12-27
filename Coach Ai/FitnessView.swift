import SwiftUI
import HealthKit

// Workout Split Models
struct Exercise: Identifiable, Codable {
    let id: UUID
    var name: String
    var sets: Int
    var reps: Int
    
    init(id: UUID = UUID(), name: String, sets: Int = 3, reps: Int = 10) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
    }
}

struct WorkoutDay: Identifiable, Codable {
    let id: UUID
    var dayOfWeek: String // "Monday", "Tuesday", etc.
    var exercises: [Exercise]
    
    init(id: UUID = UUID(), dayOfWeek: String, exercises: [Exercise] = []) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.exercises = exercises
    }
}

struct WorkoutSplit: Identifiable, Codable {
    let id: UUID
    var name: String
    var days: [WorkoutDay]
    var summary: String // 250 word max summary/notes
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, days: [WorkoutDay] = [], summary: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.days = days
        self.summary = summary
        self.createdAt = createdAt
    }
    
    // Ensure all 7 days are present
    var allDays: [WorkoutDay] {
        let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var allDaysList: [WorkoutDay] = []
        
        for dayName in weekDays {
            if let existingDay = days.first(where: { $0.dayOfWeek == dayName }) {
                allDaysList.append(existingDay)
            } else {
                // Create a rest day
                allDaysList.append(WorkoutDay(dayOfWeek: dayName, exercises: []))
            }
        }
        
        return allDaysList
    }
}

final class WorkoutSplitStore: ObservableObject {
    static let shared = WorkoutSplitStore()
    
    @Published var splits: [WorkoutSplit] {
        didSet {
            persistSplits()
            syncToFirebase()
        }
    }
    
    private let splitsKey = "workout.splits.v1"
    private var isSyncing = false
    
    init() {
        // Only load from local storage if user is authenticated
        if FirebaseService.shared.isAuthenticated {
            if let data = UserDefaults.standard.data(forKey: splitsKey),
               let decoded = try? JSONDecoder().decode([WorkoutSplit].self, from: data) {
                self.splits = decoded
            } else {
                self.splits = []
            }
        } else {
            self.splits = []
        }
        Task {
            await loadFromFirebase()
        }
    }
    
    private func persistSplits() {
        if let data = try? JSONEncoder().encode(splits) {
            UserDefaults.standard.set(data, forKey: splitsKey)
        }
    }
    
    private func syncToFirebase() {
        guard !isSyncing, FirebaseService.shared.isAuthenticated else { return }
        isSyncing = true
        Task {
            do {
                try await FirebaseService.shared.syncWorkoutSplits(splits)
                await MainActor.run {
                    isSyncing = false
                }
            } catch {
                print("Error syncing workout splits to Firebase: \(error)")
                await MainActor.run {
                    isSyncing = false
                    ErrorManager.shared.showErrorMessage(
                        "Failed to sync workout splits to cloud. Your changes are saved locally and will sync when connection is restored.",
                        title: "Sync Error"
                    )
                }
            }
        }
    }
    
    func loadFromFirebase() async {
        guard FirebaseService.shared.isAuthenticated else {
            await MainActor.run {
                self.splits = []
            }
            return
        }
        do {
            let firebaseSplits = try await FirebaseService.shared.loadWorkoutSplits()
            await MainActor.run {
                // Only merge if we're not currently syncing (to avoid race conditions)
                guard !self.isSyncing else {
                    print("⏸️ Skipping Firebase load - sync in progress")
                    return
                }
                
                // Merge Firebase splits with local splits to avoid overwriting newly added splits
                // Use a set to track IDs we've seen
                var mergedSplits: [WorkoutSplit] = []
                var seenIds: Set<UUID> = []
                
                // First, add all Firebase splits
                for firebaseSplit in firebaseSplits {
                    mergedSplits.append(firebaseSplit)
                    seenIds.insert(firebaseSplit.id)
                }
                
                // Then, add any local splits that aren't in Firebase (newly added)
                for localSplit in self.splits {
                    if !seenIds.contains(localSplit.id) {
                        mergedSplits.append(localSplit)
                        seenIds.insert(localSplit.id)
                        print("➕ Keeping local split not yet in Firebase: \(localSplit.name)")
                    }
                }
                
                // Only update if we have changes to avoid unnecessary updates
                let currentIds = Set(self.splits.map { $0.id })
                let mergedIds = Set(mergedSplits.map { $0.id })
                
                if currentIds != mergedIds || mergedSplits.count != self.splits.count {
                    print("🔄 Updating splits from Firebase:")
                    print("   Firebase splits: \(firebaseSplits.count)")
                    print("   Local splits: \(self.splits.count)")
                    print("   Merged total: \(mergedSplits.count)")
                    print("   Firebase names: \(firebaseSplits.map { $0.name }.joined(separator: ", "))")
                    print("   Local names: \(self.splits.map { $0.name }.joined(separator: ", "))")
                    print("   Merged names: \(mergedSplits.map { $0.name }.joined(separator: ", "))")
                    
                    // Ensure we're not losing any splits
                    if mergedSplits.count < max(firebaseSplits.count, self.splits.count) {
                        print("⚠️ WARNING: Merge resulted in fewer splits! Firebase: \(firebaseSplits.count), Local: \(self.splits.count), Merged: \(mergedSplits.count)")
                    }
                    
                    self.splits = mergedSplits
                } else {
                    print("✅ Splits already in sync, no update needed")
                    print("   Total splits: \(self.splits.count)")
                }
            }
        } catch {
            print("Error loading workout splits from Firebase: \(error)")
            // Don't show error for loading - we have local data and it's not critical
        }
    }
    
    func addSplit(_ split: WorkoutSplit) {
        // Check if split with same ID already exists (avoid duplicates)
        if !splits.contains(where: { $0.id == split.id }) {
            // Also check if a split with the same name already exists (additional safety)
            let nameExists = splits.contains(where: { $0.name == split.name })
            if nameExists {
                print("⚠️ Split with name '\(split.name)' already exists, but different ID. Adding anyway.")
            }
            
            print("➕ Adding new split: '\(split.name)' (ID: \(split.id.uuidString.prefix(8)))")
            print("   Current splits before add: \(splits.count)")
            print("   Split has \(split.days.count) days")
            
            // Add the split
            splits.append(split)
            
            print("✅ Successfully added split. New total: \(splits.count)")
            print("   All split names: \(splits.map { $0.name }.joined(separator: ", "))")
            print("   All split IDs: \(splits.map { $0.id.uuidString.prefix(8) }.joined(separator: ", "))")
        } else {
            print("⚠️ Split with ID \(split.id.uuidString.prefix(8)) already exists, skipping duplicate")
            print("   Existing splits: \(splits.map { "\($0.name) (\($0.id.uuidString.prefix(8)))" }.joined(separator: ", "))")
        }
    }
    
    func removeSplit(_ split: WorkoutSplit) {
        splits.removeAll { $0.id == split.id }
    }
    
    func updateSplit(_ split: WorkoutSplit) {
        if let index = splits.firstIndex(where: { $0.id == split.id }) {
            splits[index] = split
        }
    }
}

// Workout Session Models
struct CompletedSet: Identifiable, Codable {
    let id: UUID
    let exerciseId: UUID
    let setNumber: Int
    let repsCompleted: Int
    let weight: Double? // Optional weight tracking
    let completedAt: Date
    
    init(id: UUID = UUID(), exerciseId: UUID, setNumber: Int, repsCompleted: Int, weight: Double? = nil, completedAt: Date = Date()) {
        self.id = id
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.repsCompleted = repsCompleted
        self.weight = weight
        self.completedAt = completedAt
    }
}

struct ExerciseProgress: Identifiable, Codable {
    let id: UUID
    let exerciseId: UUID
    var completedSets: [CompletedSet]
    var isCompleted: Bool
    
    init(id: UUID = UUID(), exerciseId: UUID, completedSets: [CompletedSet] = [], isCompleted: Bool = false) {
        self.id = id
        self.exerciseId = exerciseId
        self.completedSets = completedSets
        self.isCompleted = isCompleted
    }
}

struct WorkoutSession: Identifiable, Codable {
    let id: UUID
    let splitId: UUID
    let splitName: String
    let dayId: UUID
    let dayName: String
    var exercises: [Exercise]
    var exerciseProgress: [ExerciseProgress]
    var startTime: Date
    var endTime: Date?
    var isActive: Bool
    
    init(id: UUID = UUID(), splitId: UUID, splitName: String, dayId: UUID, dayName: String, exercises: [Exercise], startTime: Date = Date(), endTime: Date? = nil, isActive: Bool = true) {
        self.id = id
        self.splitId = splitId
        self.splitName = splitName
        self.dayId = dayId
        self.dayName = dayName
        self.exercises = exercises
        self.exerciseProgress = exercises.map { ExerciseProgress(exerciseId: $0.id) }
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
    }
    
    var completionPercentage: Double {
        guard !exercises.isEmpty else { return 0 }
        let completed = exerciseProgress.filter { $0.isCompleted }.count
        return Double(completed) / Double(exercises.count)
    }
    
    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
}

final class WorkoutSessionStore: ObservableObject {
    static let shared = WorkoutSessionStore()
    
    @Published var activeSession: WorkoutSession? {
        didSet {
            persistSessions()
            Task {
                await syncToFirebase()
            }
        }
    }
    @Published var pastSessions: [WorkoutSession] {
        didSet {
            persistSessions()
            Task {
                await syncToFirebase()
            }
        }
    }
    
    private let sessionsKey = "workout.sessions.v1"
    private var isSyncing = false
    
    init() {
        // Start with empty - will load from Firebase
        self.pastSessions = []
        Task {
            await loadFromFirebase()
        }
    }
    
    private func persistSessions() {
        var allSessions = pastSessions
        if let active = activeSession {
            allSessions.append(active)
        }
        if let data = try? JSONEncoder().encode(allSessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
    
    func syncToFirebase() async {
        guard !isSyncing, FirebaseService.shared.isAuthenticated else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        var allSessions = pastSessions
        if let active = activeSession {
            allSessions.append(active)
        }
        
        do {
            try await FirebaseService.shared.syncWorkoutSessions(allSessions)
        } catch {
            print("Error syncing workout sessions: \(error)")
        }
    }
    
    func loadFromFirebase() async {
        guard FirebaseService.shared.isAuthenticated else {
            // Fallback to local storage if not authenticated
            if let data = UserDefaults.standard.data(forKey: sessionsKey),
               let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) {
                await MainActor.run {
                    self.activeSession = decoded.first { $0.isActive }
                    self.pastSessions = decoded.filter { !$0.isActive }.sorted { $0.startTime > $1.startTime }
                }
            }
            return
        }
        
        do {
            let sessions = try await FirebaseService.shared.loadWorkoutSessions()
            await MainActor.run {
                // Separate active and past sessions
                self.activeSession = sessions.first { $0.isActive }
                self.pastSessions = sessions.filter { !$0.isActive }.sorted { $0.startTime > $1.startTime }
            }
        } catch {
            print("Error loading workout sessions: \(error)")
            // Fallback to local storage
            if let data = UserDefaults.standard.data(forKey: sessionsKey),
               let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) {
                await MainActor.run {
                    self.activeSession = decoded.first { $0.isActive }
                    self.pastSessions = decoded.filter { !$0.isActive }.sorted { $0.startTime > $1.startTime }
                }
            }
        }
    }
    
    func startSession(splitId: UUID, splitName: String, dayId: UUID, dayName: String, exercises: [Exercise]) {
        // End any existing active session
        if let existing = activeSession {
            endSession(existing.id)
        }
        
        let session = WorkoutSession(
            splitId: splitId,
            splitName: splitName,
            dayId: dayId,
            dayName: dayName,
            exercises: exercises
        )
        activeSession = session
        persistSessions()
        Task {
            await syncToFirebase()
        }
    }
    
    func completeSet(exerciseId: UUID, setNumber: Int, repsCompleted: Int, weight: Double? = nil) {
        guard var session = activeSession else { return }
        
        if let progressIndex = session.exerciseProgress.firstIndex(where: { $0.exerciseId == exerciseId }) {
            let completedSet = CompletedSet(
                exerciseId: exerciseId,
                setNumber: setNumber,
                repsCompleted: repsCompleted,
                weight: weight
            )
            session.exerciseProgress[progressIndex].completedSets.append(completedSet)
            
            // Check if all sets are completed
            if let exercise = session.exercises.first(where: { $0.id == exerciseId }) {
                let completedCount = session.exerciseProgress[progressIndex].completedSets.count
                if completedCount >= exercise.sets {
                    session.exerciseProgress[progressIndex].isCompleted = true
                }
            }
        }
        
        activeSession = session
        persistSessions()
        Task {
            await syncToFirebase()
        }
    }
    
    func toggleExerciseCompletion(exerciseId: UUID) {
        guard var session = activeSession else { return }
        
        if let progressIndex = session.exerciseProgress.firstIndex(where: { $0.exerciseId == exerciseId }) {
            session.exerciseProgress[progressIndex].isCompleted.toggle()
            
            // If marking as incomplete, clear completed sets
            if !session.exerciseProgress[progressIndex].isCompleted {
                session.exerciseProgress[progressIndex].completedSets = []
            }
        }
        
        activeSession = session
        persistSessions()
        Task {
            await syncToFirebase()
        }
    }
    
    func endSession(_ sessionId: UUID) {
        guard var session = activeSession, session.id == sessionId else { return }
        session.endTime = Date()
        session.isActive = false
        activeSession = nil
        pastSessions.insert(session, at: 0)
        persistSessions()
        Task {
            await syncToFirebase()
        }
    }
}

// Predefined Fitness Goals
enum PredefinedFitnessGoal: String, CaseIterable, Identifiable, Codable {
    case run5K = "Run a 5K"
    case run10K = "Run a 10K"
    case runMarathon = "Run a Marathon"
    case lose10lbs = "Lose 10 lbs"
    case lose20lbs = "Lose 20 lbs"
    case gain10lbs = "Gain 10 lbs (Muscle)"
    case benchPress225 = "Bench Press 225 lbs"
    case squat315 = "Squat 315 lbs"
    case deadlift405 = "Deadlift 405 lbs"
    case do100Pushups = "Do 100 Push-ups"
    case do50Pullups = "Do 50 Pull-ups"
    case runMileUnder6 = "Run a Mile Under 6 Minutes"
    case completeTriathlon = "Complete a Triathlon"
    case yogaEveryDay = "Yoga Every Day for 30 Days"
    case noSugar30Days = "No Sugar for 30 Days"
    case drinkWaterDaily = "Drink 8 Glasses of Water Daily"
    case sleep8Hours = "Sleep 8 Hours Every Night"
    case meditateDaily = "Meditate Daily for 30 Days"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .run5K: return "Complete a 5K run"
        case .run10K: return "Complete a 10K run"
        case .runMarathon: return "Complete a full marathon (26.2 miles)"
        case .lose10lbs: return "Lose 10 pounds"
        case .lose20lbs: return "Lose 20 pounds"
        case .gain10lbs: return "Gain 10 pounds of muscle"
        case .benchPress225: return "Bench press 225 pounds"
        case .squat315: return "Squat 315 pounds"
        case .deadlift405: return "Deadlift 405 pounds"
        case .do100Pushups: return "Complete 100 push-ups in one session"
        case .do50Pullups: return "Complete 50 pull-ups in one session"
        case .runMileUnder6: return "Run a mile in under 6 minutes"
        case .completeTriathlon: return "Complete a triathlon"
        case .yogaEveryDay: return "Practice yoga every day for 30 days"
        case .noSugar30Days: return "Avoid added sugar for 30 days"
        case .drinkWaterDaily: return "Drink 8 glasses of water every day"
        case .sleep8Hours: return "Get 8 hours of sleep every night"
        case .meditateDaily: return "Meditate daily for 30 days"
        }
    }
}

// Custom Goal Model - now just tracks which predefined goals are selected
struct CustomGoal: Identifiable, Codable {
    let id: UUID
    var goalType: PredefinedFitnessGoal
    var targetDate: Date?
    var isCompleted: Bool
    var createdAt: Date
    
    init(id: UUID = UUID(), goalType: PredefinedFitnessGoal, targetDate: Date? = nil, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.goalType = goalType
        self.targetDate = targetDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
    
    var title: String { goalType.rawValue }
    var description: String { goalType.description }
}

// Fitness Goals Model
struct FitnessGoals: Codable {
    var primaryGoal: String // e.g., "Lose Weight", "Build Muscle", "Improve Cardio", "Maintain"
    var targetWeight: Double? // in kg
    var targetSteps: Int // daily step goal
    var targetCalories: Int // daily calorie burn goal
    var targetWorkoutsPerWeek: Int
    var customGoals: [CustomGoal] // Custom goals added by user or AI
    
    init() {
        self.primaryGoal = "Maintain"
        self.targetWeight = nil
        self.targetSteps = 10000
        self.targetCalories = 500
        self.targetWorkoutsPerWeek = 3
        self.customGoals = []
    }
}

final class FitnessGoalsStore: ObservableObject {
    static let shared = FitnessGoalsStore()
    
    @Published var goals: FitnessGoals {
        didSet {
            persistGoals()
            syncToFirebase()
        }
    }
    
    private let goalsKey = "fitness.goals.v2" // Updated version for custom goals
    private var isSyncing = false
    
    init() {
        // Only load from local storage if user is authenticated
        if FirebaseService.shared.isAuthenticated {
            if let data = UserDefaults.standard.data(forKey: goalsKey),
               let decoded = try? JSONDecoder().decode(FitnessGoals.self, from: data) {
                self.goals = decoded
            } else {
                // Try loading old version
                if let oldData = UserDefaults.standard.data(forKey: "fitness.goals.v1"),
                   let oldDecoded = try? JSONDecoder().decode(FitnessGoals.self, from: oldData) {
                    var migrated = oldDecoded
                    if migrated.customGoals.isEmpty {
                        migrated.customGoals = []
                    }
                    self.goals = migrated
                } else {
                    self.goals = FitnessGoals()
                }
            }
        } else {
            self.goals = FitnessGoals()
        }
        Task {
            await loadFromFirebase()
        }
    }
    
    private func persistGoals() {
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
        }
    }
    
    private func syncToFirebase() {
        guard !isSyncing, FirebaseService.shared.isAuthenticated else { return }
        isSyncing = true
        Task {
            do {
                try await FirebaseService.shared.syncFitnessGoals(goals)
                await MainActor.run {
                    isSyncing = false
                }
            } catch {
                print("Error syncing fitness goals to Firebase: \(error)")
                await MainActor.run {
                    isSyncing = false
                    ErrorManager.shared.showErrorMessage(
                        "Failed to sync fitness goals to cloud. Your changes are saved locally and will sync when connection is restored.",
                        title: "Sync Error"
                    )
                }
            }
        }
    }
    
    func loadFromFirebase() async {
        guard FirebaseService.shared.isAuthenticated else {
            await MainActor.run {
                self.goals = FitnessGoals()
            }
            return
        }
        do {
            if let firebaseGoals = try await FirebaseService.shared.loadFitnessGoals() {
                await MainActor.run {
                    self.goals = firebaseGoals
                }
            } else {
                // If Firebase returns nil, keep default goals (new user)
                await MainActor.run {
                    self.goals = FitnessGoals()
                }
            }
        } catch {
            print("Error loading fitness goals from Firebase: \(error)")
            await MainActor.run {
                ErrorManager.shared.showErrorMessage(
                    "Failed to load fitness goals from cloud. Using local data. Changes will sync when connection is restored.",
                    title: "Connection Error"
                )
            }
        }
    }
    
    // Methods for managing goals
    func updatePrimaryGoal(_ goal: String) {
        goals.primaryGoal = goal
    }
    
    func updateTargetWeight(_ weight: Double?) {
        goals.targetWeight = weight
    }
    
    func updateTargetSteps(_ steps: Int) {
        goals.targetSteps = steps
    }
    
    func updateTargetCalories(_ calories: Int) {
        goals.targetCalories = calories
    }
    
    func updateTargetWorkoutsPerWeek(_ workouts: Int) {
        goals.targetWorkoutsPerWeek = workouts
    }
    
    func addCustomGoal(_ goal: CustomGoal) {
        goals.customGoals.append(goal)
    }
    
    func removeCustomGoal(_ goal: CustomGoal) {
        goals.customGoals.removeAll { $0.id == goal.id }
    }
    
    func updateCustomGoal(_ goal: CustomGoal) {
        if let index = goals.customGoals.firstIndex(where: { $0.id == goal.id }) {
            goals.customGoals[index] = goal
        }
    }
}

struct FitnessView: View {
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var location = LocationManager.shared
    @StateObject private var goalsStore = FitnessGoalsStore.shared
    @StateObject private var splitStore = WorkoutSplitStore.shared
    @StateObject private var sessionStore = WorkoutSessionStore.shared
    @State private var showGymMap = false
    @State private var showGoalsEditor = false
    @State private var showSplitEditor = false
    @State private var showStartWorkout = false
    @State private var editingSplit: WorkoutSplit? = nil
    @State private var showProfileEditor = false
    
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Health Stats Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Today's Stats")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                FitnessStatCard(
                                    title: "Steps",
                                    value: "\(health.todaySteps)",
                                    subtitle: "Goal: \(goalsStore.goals.targetSteps)",
                                    icon: "figure.walk",
                                    color: .blue
                                )
                                
                                FitnessStatCard(
                                    title: "Calories",
                                    value: "\(Int(health.todayActiveEnergy))",
                                    subtitle: "Goal: \(goalsStore.goals.targetCalories)",
                                    icon: "flame.fill",
                                    color: .orange
                                )
                                
                                FitnessStatCard(
                                    title: "Active HR",
                                    value: health.activeHeartRate > 0 ? "\(Int(health.activeHeartRate))" : "—",
                                    subtitle: "bpm",
                                    icon: "heart.fill",
                                    color: .red
                                )
                                
                                FitnessStatCard(
                                    title: "Avg HR",
                                    value: health.averageHeartRate > 0 ? "\(Int(health.averageHeartRate))" : "—",
                                    subtitle: "bpm today",
                                    icon: "heart.circle.fill",
                                    color: .pink
                                )
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // User Profile Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Profile")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Button(action: {
                                    showProfileEditor = true
                                }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [Color.blue, Color.cyan],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            VStack(spacing: 12) {
                                ProfileRow(
                                    label: "Height",
                                    value: health.height > 0 ? formatHeight(health.height) : "Not set",
                                    icon: "ruler.fill"
                                )
                                
                                ProfileRow(
                                    label: "Weight",
                                    value: health.weight > 0 ? formatWeight(health.weight) : "Not set",
                                    icon: "scalemass.fill"
                                )
                                
                                ProfileRow(
                                    label: "Gender",
                                    value: formatBiologicalSex(health.biologicalSex),
                                    icon: "person.fill"
                                )
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Fitness Goals Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Fitness Goals")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Button(action: {
                                    showGoalsEditor = true
                                }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [Color.orange, Color.red],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            VStack(spacing: 12) {
                                GoalRow(
                                    label: "Primary Goal",
                                    value: goalsStore.goals.primaryGoal,
                                    icon: "target"
                                )
                                
                                if let targetWeight = goalsStore.goals.targetWeight {
                                    GoalRow(
                                        label: "Target Weight",
                                        value: formatWeight(targetWeight),
                                        icon: "scalemass"
                                    )
                                }
                                
                                GoalRow(
                                    label: "Daily Steps Goal",
                                    value: "\(goalsStore.goals.targetSteps)",
                                    icon: "figure.walk"
                                )
                                
                                GoalRow(
                                    label: "Daily Calories Goal",
                                    value: "\(goalsStore.goals.targetCalories) cal",
                                    icon: "flame"
                                )
                                
                                GoalRow(
                                    label: "Workouts Per Week",
                                    value: "\(goalsStore.goals.targetWorkoutsPerWeek)",
                                    icon: "dumbbell.fill"
                                )
                                
                                // Custom Goals
                                if !goalsStore.goals.customGoals.isEmpty {
                                    Divider()
                                        .background(.white.opacity(0.2))
                                        .padding(.vertical, 8)
                                    
                                    ForEach(goalsStore.goals.customGoals) { customGoal in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: customGoal.isCompleted ? "checkmark.circle.fill" : "star.fill")
                                                    .foregroundStyle(customGoal.isCompleted ? .green : .yellow)
                                                    .font(.system(size: 14))
                                                Text(customGoal.title)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(customGoal.isCompleted ? .white.opacity(0.6) : .white)
                                                    .strikethrough(customGoal.isCompleted)
                                            }
                                            
                                            Text(customGoal.description)
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white.opacity(0.7))
                                                .padding(.leading, 20)
                                            
                                            if let targetDate = customGoal.targetDate {
                                                Text("Target Date: \(targetDate.formatted(date: .abbreviated, time: .omitted))")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.white.opacity(0.6))
                                                    .padding(.leading, 20)
                                            }
                                        }
                                        .padding(12)
                                        .background(.white.opacity(0.05))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Active Workout Section
                        if let activeSession = sessionStore.activeSession {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("Active Workout")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        sessionStore.endSession(activeSession.id)
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "stop.circle.fill")
                                            Text("End Workout")
                                        }
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            LinearGradient(
                                                colors: [Color.red, Color.orange],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(20)
                                    }
                                }
                                .padding(.horizontal, 20)
                                
                                NavigationLink(destination: WorkoutSessionView()) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text(activeSession.splitName)
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text("\(Int(activeSession.completionPercentage * 100))%")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(.green)
                                        }
                                        
                                        Text(activeSession.dayName)
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white.opacity(0.7))
                                        
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                            Text("\(activeSession.exerciseProgress.filter { $0.isCompleted }.count)/\(activeSession.exercises.count) exercises completed")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white.opacity(0.8))
                                            
                                            Spacer()
                                            
                                            Image(systemName: "clock.fill")
                                                .foregroundStyle(.blue)
                                            Text(formatDuration(activeSession.duration))
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                    }
                                    .padding(20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.white.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(.green.opacity(0.5), lineWidth: 2)
                                            )
                                    )
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Start Workout Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Start Workout")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Button(action: {
                                    showStartWorkout = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.circle.fill")
                                        Text("Start")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.green, Color.mint],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(20)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Workout Splits Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Workout Splits")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Button(action: {
                                    editingSplit = nil
                                    showSplitEditor = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("New Split")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.purple, Color.pink],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(20)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            if splitStore.splits.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "dumbbell")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.white.opacity(0.3))
                                    
                                    Text("No workout splits yet")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                    
                                    Text("Create a split or ask your AI coach to make one for you")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .padding(.horizontal, 20)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(splitStore.splits) { split in
                                        WorkoutSplitCard(split: split, splitStore: splitStore) {
                                            editingSplit = split
                                            showSplitEditor = true
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Gym Tracking Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Gym Tracking")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Button(action: {
                                    showGymMap = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "map.fill")
                                        Text("Manage Gyms")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.blue, Color.cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(20)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            if location.gyms.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "mappin.circle")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.white.opacity(0.3))
                                    
                                    Text("No gyms added yet")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                    
                                    Text("Add gyms to track your workout time automatically")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                                .padding(.horizontal, 20)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(location.gyms) { gym in
                                        GymSummaryCard(gym: gym, location: location)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("Fitness")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showGymMap) {
                GymMapView()
            }
            .sheet(isPresented: $showGoalsEditor) {
                FitnessGoalsEditor(goals: $goalsStore.goals, isPresented: $showGoalsEditor)
            }
            .sheet(isPresented: $showSplitEditor) {
                WorkoutSplitEditor(split: editingSplit, isPresented: $showSplitEditor)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorSheet(health: health, isPresented: $showProfileEditor)
            }
            .sheet(isPresented: $showStartWorkout) {
                StartWorkoutSheet(isPresented: $showStartWorkout)
            }
            .sheet(isPresented: Binding(
                get: { location.pendingGymWorkout != nil },
                set: { if !$0 { location.pendingGymWorkout = nil } }
            )) {
                if let gymId = location.pendingGymWorkout {
                    GymWorkoutSelectionSheet(gymId: gymId, isPresented: Binding(
                        get: { location.pendingGymWorkout != nil },
                        set: { if !$0 { location.pendingGymWorkout = nil } }
                    ))
                }
            }
            .task {
                await health.ensureAuthorization()
                await health.refreshToday()
                await health.refreshProfile()
            }
            .refreshable {
                await health.refreshToday()
                await health.refreshProfile()
            }
        }
    }
    
    private func formatHeight(_ meters: Double) -> String {
        if meters == 0 { return "Not set" }
        let totalInches = meters * 39.3701
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
        return "\(feet)'\(inches)\""
    }
    
    private func formatWeight(_ kg: Double) -> String {
        if kg == 0 { return "Not set" }
        let pounds = kg * 2.20462
        return String(format: "%.1f lbs", pounds)
    }
    
    private func formatBiologicalSex(_ sex: HKBiologicalSex) -> String {
        switch sex {
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        default: return "Not set"
        }
    }
}

struct FitnessStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct ProfileRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 30)
            
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct GoalRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 30)
            
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct GymSummaryCard: View {
    let gym: Gym
    @ObservedObject var location: LocationManager
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(gym.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Label("\(formatTime(gym.effectiveTotalTime))", systemImage: "clock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            if location.activeWorkouts[gym.id] != nil {
                VStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                    Text("Active")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct FitnessGoalsEditor: View {
    @Binding var goals: FitnessGoals
    @Binding var isPresented: Bool
    @State private var selectedGoal: String = "Maintain"
    @State private var targetWeightText: String = ""
    @State private var targetStepsText: String = "10000"
    @State private var targetCaloriesText: String = "500"
    @State private var targetWorkoutsText: String = "3"
    
    let goalOptions = ["Lose Weight", "Build Muscle", "Improve Cardio", "Maintain", "Gain Weight"]
    
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Primary Goal
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Primary Goal")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            Picker("Goal", selection: $selectedGoal) {
                                ForEach(goalOptions, id: \.self) { goal in
                                    Text(goal).tag(goal)
                                }
                            }
                            .pickerStyle(.segmented)
                            .colorMultiply(.white.opacity(0.2))
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Target Weight (if applicable)
                        if selectedGoal == "Lose Weight" || selectedGoal == "Gain Weight" {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Target Weight (lbs)")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                
                                TextField("Enter target weight", text: $targetWeightText)
                                    .textFieldStyle(.plain)
                                    .keyboardType(.decimalPad)
                                    .padding(16)
                                    .background(.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .foregroundStyle(.white)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        
                        // Daily Steps Goal
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Daily Steps Goal")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            TextField("Steps", text: $targetStepsText)
                                .textFieldStyle(.plain)
                                .keyboardType(.numberPad)
                                .padding(16)
                                .background(.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundStyle(.white)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Daily Calories Goal
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Daily Calories Burn Goal")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            TextField("Calories", text: $targetCaloriesText)
                                .textFieldStyle(.plain)
                                .keyboardType(.numberPad)
                                .padding(16)
                                .background(.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundStyle(.white)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Workouts Per Week
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Workouts Per Week")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            TextField("Number", text: $targetWorkoutsText)
                                .textFieldStyle(.plain)
                                .keyboardType(.numberPad)
                                .padding(16)
                                .background(.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundStyle(.white)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Custom Fitness Goals Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Custom Fitness Goals")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Menu {
                                    ForEach(PredefinedFitnessGoal.allCases) { predefinedGoal in
                                        // Only show goals that aren't already added
                                        if !goals.customGoals.contains(where: { $0.goalType == predefinedGoal }) {
                                            Button(action: {
                                                let newGoal = CustomGoal(goalType: predefinedGoal)
                                                goals.customGoals.append(newGoal)
                                            }) {
                                                Text(predefinedGoal.rawValue)
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.green)
                                }
                            }
                            
                            if goals.customGoals.isEmpty {
                                Text("No custom fitness goals yet. Tap + to select from predefined goals.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(goals.customGoals) { customGoal in
                                    CustomGoalRow(goal: customGoal, goals: $goals)
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        Button(action: {
                            saveGoals()
                        }) {
                            Text("Save Goals")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.orange, Color.red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Edit Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                selectedGoal = goals.primaryGoal
                if let weight = goals.targetWeight {
                    targetWeightText = String(format: "%.1f", weight * 2.20462)
                }
                targetStepsText = "\(goals.targetSteps)"
                targetCaloriesText = "\(goals.targetCalories)"
                targetWorkoutsText = "\(goals.targetWorkoutsPerWeek)"
            }
        }
    }
    
    private func saveGoals() {
        goals.primaryGoal = selectedGoal
        
        if !targetWeightText.isEmpty, let weight = Double(targetWeightText) {
            goals.targetWeight = weight / 2.20462 // Convert lbs to kg
        } else {
            goals.targetWeight = nil
        }
        
        if let steps = Int(targetStepsText) {
            goals.targetSteps = steps
        }
        
        if let calories = Int(targetCaloriesText) {
            goals.targetCalories = calories
        }
        
        if let workouts = Int(targetWorkoutsText) {
            goals.targetWorkoutsPerWeek = workouts
        }
        
        isPresented = false
    }
}

struct CustomGoalRow: View {
    let goal: CustomGoal
    @Binding var goals: FitnessGoals
    @State private var isEditing = false
    @State private var editTargetDate: Date?
    
    private var goalIndex: Int? {
        goals.customGoals.firstIndex(where: { $0.id == goal.id })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    
                    Text(goal.description)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    DatePicker("Target Date (optional)", selection: Binding(
                        get: { editTargetDate ?? Date() },
                        set: { editTargetDate = $0 }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .foregroundStyle(.white)
                    
                    Toggle("Completed", isOn: Binding(
                        get: { goal.isCompleted },
                        set: { newValue in
                            if let index = goalIndex {
                                goals.customGoals[index].isCompleted = newValue
                            }
                        }
                    ))
                    .foregroundStyle(.white)
                    
                    HStack {
                        Button("Cancel") {
                            isEditing = false
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        
                        Spacer()
                        
                        Button("Save") {
                            if let index = goalIndex {
                                goals.customGoals[index].targetDate = editTargetDate
                            }
                            isEditing = false
                        }
                        .foregroundStyle(.green)
                    }
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "star.fill")
                                .foregroundStyle(goal.isCompleted ? .green : .yellow)
                                .font(.system(size: 14))
                            Text(goal.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(goal.isCompleted ? .white.opacity(0.6) : .white)
                                .strikethrough(goal.isCompleted)
                        }
                        
                        Text(goal.description)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.leading, 20)
                        
                        if let targetDate = goal.targetDate {
                            Text("Target Date: \(formatDate(targetDate))")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.leading, 20)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            editTargetDate = goal.targetDate
                            isEditing = true
                        }) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.blue)
                        }
                        
                        Button(action: {
                            goals.customGoals.removeAll { $0.id == goal.id }
                        }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct WorkoutSplitCard: View {
    let split: WorkoutSplit
    @ObservedObject var splitStore: WorkoutSplitStore
    let onEdit: () -> Void
    
    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(split.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    // Only show delete button, no edit button
                    Button(action: {
                        splitStore.removeSplit(split)
                    }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                
                // Show workout days count (excluding rest days)
                let workoutDays = split.allDays.filter { !$0.exercises.isEmpty }
                Text("\(workoutDays.count) workout days, \(split.allDays.count - workoutDays.count) rest days")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                
                // Show a preview of the days
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(split.allDays.prefix(3)) { day in
                        HStack {
                            Text(day.dayOfWeek)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            Spacer()
                            
                            if day.exercises.isEmpty {
                                Text("Rest Day")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            } else {
                                Text("\(day.exercises.count) exercises")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    
                    if split.allDays.count > 3 {
                        Text("+ \(split.allDays.count - 3) more days")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct WorkoutSplitEditor: View {
    let split: WorkoutSplit?
    @Binding var isPresented: Bool
    @StateObject private var splitStore = WorkoutSplitStore.shared
    
    @State private var splitName: String = ""
    @State private var days: [WorkoutDay] = []
    @State private var summary: String = ""
    @State private var selectedDay: WorkoutDay? = nil
    @State private var showDayEditor = false
    
    let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
    // Ensure all 7 days are present
    private var allDays: [WorkoutDay] {
        var allDaysList: [WorkoutDay] = []
        let existingDayNames = Set(days.map { $0.dayOfWeek })
        
        for dayName in weekDays {
            if let existingDay = days.first(where: { $0.dayOfWeek == dayName }) {
                allDaysList.append(existingDay)
            } else {
                // Create a rest day
                allDaysList.append(WorkoutDay(dayOfWeek: dayName, exercises: []))
            }
        }
        
        return allDaysList
    }
    
    private var wordCount: Int {
        summary.split { $0 == " " || $0.isNewline }.count
    }
    
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Split Name
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Split Name")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            TextField("e.g., Push/Pull/Legs", text: $splitName)
                                .textFieldStyle(.plain)
                                .padding(16)
                                .background(.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundStyle(.white)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Summary/Notes Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Summary & Notes")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Text("\(wordCount)/250 words")
                                    .font(.system(size: 12))
                                    .foregroundStyle(wordCount > 250 ? .red : .white.opacity(0.6))
                            }
                            
                            TextEditor(text: $summary)
                                .frame(minHeight: 100)
                                .padding(12)
                                .background(.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .onChange(of: summary) { oldValue, newValue in
                                    // Limit to 250 words
                                    let words = newValue.split { $0 == " " || $0.isNewline }
                                    if words.count > 250 {
                                        let limited = words.prefix(250).joined(separator: " ")
                                        summary = limited
                                    }
                                }
                            
                            Text("Add notes, tips, or a summary about this workout split (250 words max)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Days Section - Show all 7 days
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Weekly Schedule")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            Text("All 7 days of the week are shown. Days without exercises are rest days.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                            
                            // Show all 7 days
                            ForEach(allDays) { day in
                                WorkoutDayCard(day: day, days: $days)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Save Button
                        Button(action: {
                            saveSplit()
                        }) {
                            Text("Save Split")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.purple, Color.pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(split == nil ? "New Workout Split" : "Edit Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                if let existingSplit = split {
                    splitName = existingSplit.name
                    summary = existingSplit.summary
                    // Ensure all 7 days are present
                    days = existingSplit.allDays
                } else {
                    // For new splits, initialize with all 7 days (all rest days initially)
                    days = weekDays.map { WorkoutDay(dayOfWeek: $0, exercises: []) }
                }
            }
        }
    }
    
    private func addNewDay() {
        // Find the first day of the week that's not already used
        let usedDays = Set(days.map { $0.dayOfWeek })
        if let firstUnusedDay = weekDays.first(where: { !usedDays.contains($0) }) {
            days.append(WorkoutDay(dayOfWeek: firstUnusedDay))
        } else {
            // If all days are used, just add a generic day
            days.append(WorkoutDay(dayOfWeek: "Day \(days.count + 1)"))
        }
    }
    
    private func saveSplit() {
        guard !splitName.isEmpty else { return }
        
        // Filter out rest days (days with no exercises) but keep the structure
        // Actually, we want to keep all 7 days, so we'll save all days
        let daysToSave = allDays
        
        if let existingSplit = split {
            var updated = existingSplit
            updated.name = splitName
            updated.summary = summary
            updated.days = daysToSave
            splitStore.updateSplit(updated)
        } else {
            let newSplit = WorkoutSplit(name: splitName, days: daysToSave, summary: summary)
            splitStore.addSplit(newSplit)
        }
        
        isPresented = false
    }
}

struct WorkoutDayCard: View {
    @State var day: WorkoutDay
    @Binding var days: [WorkoutDay]
    @State private var showDayPicker = false
    @State private var showExerciseEditor = false
    @State private var editingExercise: Exercise? = nil
    @State private var newExerciseId: UUID? = nil
    
    let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Day name is fixed - can't change it since we need all 7 days
                Text(day.dayOfWeek)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Show "Rest Day" indicator if no exercises
                if day.exercises.isEmpty {
                    Text("Rest Day")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // Exercises List
            if day.exercises.isEmpty {
                Text("Rest Day - Tap + to add exercises")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                ForEach(day.exercises) { exercise in
                    ExerciseRow(exercise: exercise, day: $day)
                }
            }
            
            // Add Exercise Button
            Button(action: {
                let newExercise = Exercise(name: "New Exercise")
                if let index = days.firstIndex(where: { $0.id == day.id }) {
                    days[index].exercises.append(newExercise)
                    newExerciseId = newExercise.id
                    editingExercise = newExercise
                    showExerciseEditor = true
                }
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercise")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.green)
                .padding(.top, 8)
            }
            .sheet(isPresented: $showExerciseEditor) {
                if let exerciseId = newExerciseId ?? editingExercise?.id,
                   let dayIndex = days.firstIndex(where: { $0.id == day.id }),
                   let exerciseIndex = days[dayIndex].exercises.firstIndex(where: { $0.id == exerciseId }) {
                    ExerciseEditor(exercise: Binding(
                        get: { days[dayIndex].exercises[exerciseIndex] },
                        set: { days[dayIndex].exercises[exerciseIndex] = $0 }
                    ), day: Binding(
                        get: { days[dayIndex] },
                        set: { days[dayIndex] = $0 }
                    ))
                } else if let exercise = editingExercise,
                          let dayIndex = days.firstIndex(where: { $0.id == day.id }),
                          let exerciseIndex = days[dayIndex].exercises.firstIndex(where: { $0.id == exercise.id }) {
                    ExerciseEditor(exercise: Binding(
                        get: { days[dayIndex].exercises[exerciseIndex] },
                        set: { days[dayIndex].exercises[exerciseIndex] = $0 }
                    ), day: Binding(
                        get: { days[dayIndex] },
                        set: { days[dayIndex] = $0 }
                    ))
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct ExerciseRow: View {
    @State var exercise: Exercise
    @Binding var day: WorkoutDay
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text("\(exercise.sets) sets × \(exercise.reps) reps")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            Menu {
                Button("Edit") {
                    showExerciseEditor = true
                }
                
                Button("Delete", role: .destructive) {
                    day.exercises.removeAll { $0.id == exercise.id }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .cornerRadius(8)
        .sheet(isPresented: $showExerciseEditor) {
            ExerciseEditor(exercise: $exercise, day: $day)
        }
    }
    
    @State private var showExerciseEditor = false
}

struct ExerciseEditor: View {
    @Binding var exercise: Exercise
    @Binding var day: WorkoutDay
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var sets: String = ""
    @State private var reps: String = ""
    
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
                
                Form {
                    Section(header: Text("Exercise Name").foregroundStyle(.white.opacity(0.8))) {
                        TextField("e.g., Bench Press", text: $name)
                            .listRowBackground(Color.white.opacity(0.1))
                            .foregroundStyle(.white)
                    }
                    
                    Section(header: Text("Sets & Reps").foregroundStyle(.white.opacity(0.8))) {
                        HStack {
                            Text("Sets")
                            Spacer()
                            TextField("", text: $sets)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        .listRowBackground(Color.white.opacity(0.1))
                        .foregroundStyle(.white)
                        
                        HStack {
                            Text("Reps")
                            Spacer()
                            TextField("", text: $reps)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        .listRowBackground(Color.white.opacity(0.1))
                        .foregroundStyle(.white)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        exercise.name = name
                        exercise.sets = Int(sets) ?? 3
                        exercise.reps = Int(reps) ?? 10
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                name = exercise.name
                sets = "\(exercise.sets)"
                reps = "\(exercise.reps)"
            }
        }
    }
}

// Start Workout Sheet
struct GymWorkoutSelectionSheet: View {
    let gymId: UUID
    @Binding var isPresented: Bool
    @StateObject private var splitStore = WorkoutSplitStore.shared
    @StateObject private var sessionStore = WorkoutSessionStore.shared
    @StateObject private var location = LocationManager.shared
    
    var gym: Gym? {
        location.gyms.first(where: { $0.id == gymId })
    }
    
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
                
                ScrollView {
                    VStack(spacing: 20) {
                        if let gym = gym {
                            VStack(spacing: 8) {
                                Text("🏋️ You're at \(gym.name)!")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text("Select your workout to start tracking time")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.vertical, 20)
                        }
                        
                        if splitStore.splits.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "dumbbell")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.white.opacity(0.3))
                                
                                Text("No Workout Splits")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text("You can still start tracking time without selecting a workout")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                
                                Button(action: {
                                    // Start workout without selecting a split
                                    location.startWorkout(at: gymId)
                                    isPresented = false
                                }) {
                                    Text("Start Tracking Time")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(16)
                                        .background(
                                            LinearGradient(
                                                colors: [Color.green, Color.mint],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(16)
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(40)
                        } else {
                            ForEach(splitStore.splits) { split in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(split.name)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white)
                                    
                                    ForEach(split.days) { day in
                                        Button(action: {
                                            // Start workout session
                                            sessionStore.startSession(
                                                splitId: split.id,
                                                splitName: split.name,
                                                dayId: day.id,
                                                dayName: day.dayOfWeek,
                                                exercises: day.exercises
                                            )
                                            // Start gym workout timer
                                            location.startWorkout(at: gymId, splitId: split.id, dayId: day.id)
                                            isPresented = false
                                        }) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(day.dayOfWeek)
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundStyle(.white)
                                                    
                                                    Text("\(day.exercises.count) exercises")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(.white.opacity(0.7))
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: "play.circle.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundStyle(.green)
                                            }
                                            .padding(16)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(.white.opacity(0.1))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                                    )
                                            )
                                        }
                                    }
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                            
                            // Option to start tracking without selecting a workout
                            Button(action: {
                                location.startWorkout(at: gymId)
                                isPresented = false
                            }) {
                                HStack {
                                    Text("Just Track Time (No Workout)")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                    
                                    Spacer()
                                    
                                    Image(systemName: "clock.fill")
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        location.cancelWorkout(at: gymId)
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

struct StartWorkoutSheet: View {
    @Binding var isPresented: Bool
    @StateObject private var splitStore = WorkoutSplitStore.shared
    @StateObject private var sessionStore = WorkoutSessionStore.shared
    
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
                
                ScrollView {
                    VStack(spacing: 20) {
                        if splitStore.splits.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "dumbbell")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.white.opacity(0.3))
                                
                                Text("No Workout Splits")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text("Create a workout split first to start a workout")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(40)
                        } else {
                            ForEach(splitStore.splits) { split in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(split.name)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white)
                                    
                                    ForEach(split.days) { day in
                                        Button(action: {
                                            sessionStore.startSession(
                                                splitId: split.id,
                                                splitName: split.name,
                                                dayId: day.id,
                                                dayName: day.dayOfWeek,
                                                exercises: day.exercises
                                            )
                                            isPresented = false
                                        }) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(day.dayOfWeek)
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundStyle(.white)
                                                    
                                                    Text("\(day.exercises.count) exercises")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(.white.opacity(0.7))
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: "play.circle.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundStyle(.green)
                                            }
                                            .padding(16)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(.white.opacity(0.1))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                                    )
                                            )
                                        }
                                    }
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

// Workout Session View
struct WorkoutSessionView: View {
    @StateObject private var sessionStore = WorkoutSessionStore.shared
    @State private var timer: Timer?
    @State private var elapsedTime: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss
    
    private var session: WorkoutSession? {
        sessionStore.activeSession
    }
    
    var body: some View {
        Group {
            if let session = session {
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
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            VStack(spacing: 12) {
                                Text(session.splitName)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text(session.dayName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.7))
                                
                                // Progress Bar
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.white.opacity(0.2))
                                            .frame(height: 12)
                                        
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.green, Color.mint],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geometry.size.width * session.completionPercentage, height: 12)
                                    }
                                }
                                .frame(height: 12)
                                
                                HStack {
                                    Text("\(Int(session.completionPercentage * 100))% Complete")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock.fill")
                                        Text(formatDuration(elapsedTime))
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            
                            // Exercises List
                            VStack(spacing: 16) {
                                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                                    if let progress = session.exerciseProgress.first(where: { $0.exerciseId == exercise.id }) {
                                        ExerciseSessionCard(
                                            exercise: exercise,
                                            progress: progress,
                                            sessionId: session.id,
                                            sessionStore: sessionStore
                                        )
                                    }
                                }
                            }
                            
                            // End Workout Button
                            Button(action: {
                                sessionStore.endSession(session.id)
                                dismiss()
                            }) {
                                Text("End Workout")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(16)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.red, Color.orange],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(16)
                            }
                        }
                        .padding(20)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Workout")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .onAppear {
                    elapsedTime = session.duration
                    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        if let activeSession = sessionStore.activeSession {
                            elapsedTime = activeSession.duration
                        }
                    }
                }
                .onDisappear {
                    timer?.invalidate()
                }
            } else {
                Text("No active workout")
                    .foregroundStyle(.white)
            }
        }
    }
}

struct ExerciseSessionCard: View {
    let exercise: Exercise
    let progress: ExerciseProgress
    let sessionId: UUID
    @ObservedObject var sessionStore: WorkoutSessionStore
    
    private var currentProgress: ExerciseProgress? {
        sessionStore.activeSession?.exerciseProgress.first { $0.exerciseId == exercise.id }
    }
    
    private var isCompleted: Bool {
        currentProgress?.isCompleted ?? progress.isCompleted
    }
    
    private var completedSets: [CompletedSet] {
        currentProgress?.completedSets ?? progress.completedSets
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: {
                    sessionStore.toggleExerciseCompletion(exerciseId: exercise.id)
                }) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isCompleted ? .green : .white.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text("\(exercise.sets) sets × \(exercise.reps) reps")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                }
            }
            
            // Sets Progress
            if !isCompleted {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(1...exercise.sets, id: \.self) { setNumber in
                        let setCompleted = completedSets.contains { $0.setNumber == setNumber }
                        Button(action: {
                            sessionStore.completeSet(
                                exerciseId: exercise.id,
                                setNumber: setNumber,
                                repsCompleted: exercise.reps
                            )
                        }) {
                            HStack {
                                Image(systemName: setCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(setCompleted ? .green : .white.opacity(0.5))
                                
                                Text("Set \(setNumber)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Text("\(exercise.reps) reps")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(setCompleted ? .green.opacity(0.2) : .white.opacity(0.05))
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isCompleted ? .green.opacity(0.1) : .white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isCompleted ? .green.opacity(0.5) : .white.opacity(0.2), lineWidth: isCompleted ? 2 : 1)
                )
        )
    }
}

func formatDuration(_ duration: TimeInterval) -> String {
    let hours = Int(duration) / 3600
    let minutes = (Int(duration) % 3600) / 60
    let seconds = Int(duration) % 60
    
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}

