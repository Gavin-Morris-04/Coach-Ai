import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import HealthKit

final class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    
    struct User: Codable {
        let uid: String
        var name: String
        var height: Double? // in meters
        var weight: Double? // in kg
        var gender: String? // "male", "female", "other"
        var createdAt: Date
        var updatedAt: Date
        
        init(uid: String, name: String, height: Double? = nil, weight: Double? = nil, gender: String? = nil) {
            self.uid = uid
            self.name = name
            self.height = height
            self.weight = weight
            self.gender = gender
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
    
    init() {
        // Check if user is already authenticated
        if let authUser = Auth.auth().currentUser {
            self.currentUser = User(uid: authUser.uid, name: authUser.displayName ?? "User")
            self.isAuthenticated = true
            Task {
                await loadUserData()
            }
        }
    }
    
    // MARK: - Authentication
    
    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        let user = User(uid: result.user.uid, name: "User")
        self.currentUser = user
        self.isAuthenticated = true
        try await saveUserData(user)
    }
    
    func signInWithEmail(_ email: String, password: String) async throws {
        // Clear local data before signing in to prevent data leakage
        clearLocalData()
        
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        // Load user data from Firestore
        await loadUserData()
        // If user data doesn't exist, create a basic user record
        await MainActor.run {
            if self.currentUser == nil {
                let user = User(uid: result.user.uid, name: result.user.displayName ?? "User")
                self.currentUser = user
                self.isAuthenticated = true
            } else {
                self.isAuthenticated = true
            }
        }
        // Save user data if it was just created
        if let user = currentUser, user.name == "User" {
            try await saveUserData(user)
        }
        
        // Reload all data from Firebase for this user
        await reloadAllUserData()
    }
    
    private func reloadAllUserData() async {
        // Trigger reload of all stores
        Task {
            await TodoStore.shared.loadFromFirebase()
        }
        Task {
            await CaloriesStore.shared.loadFromFirebase()
        }
        Task {
            await FitnessGoalsStore.shared.loadFromFirebase()
        }
        Task {
            await WorkoutSplitStore.shared.loadFromFirebase()
        }
        Task {
            await LocationManager.shared.loadGymsFromFirebase()
        }
        Task {
            await CalendarManager.shared.loadFromFirebase()
        }
        Task {
            await WorkoutSessionStore.shared.loadFromFirebase()
        }
    }
    
    func signUpWithEmail(_ email: String, password: String, name: String) async throws {
        // Clear local data before signing up
        clearLocalData()
        
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = name
        try await changeRequest.commitChanges()
        
        let user = User(uid: result.user.uid, name: name)
        self.currentUser = user
        self.isAuthenticated = true
        try await saveUserData(user)
        
        // Reload all data from Firebase for this user (will be empty for new user)
        await reloadAllUserData()
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        self.currentUser = nil
        self.isAuthenticated = false
        
        // Clear all local UserDefaults data
        clearLocalData()
    }
    
    private func clearLocalData() {
        // Clear all app-specific UserDefaults keys
        let keys = [
            "todo.items.v2",
            "calorie.entries.v2",
            "nutrition.goals.v1",
            "fitness.goals.v2",
            "workout.splits.v1",
            "workout.sessions.v1",
            "gyms.list.v3",
            "active.workouts.v1",
            "user.height",
            "user.weight",
            "user.gender",
            "user.name"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    // MARK: - User Data
    
    func updateUserProfile(name: String, height: Double?, weight: Double?, gender: String?) async throws {
        guard var user = currentUser else { return }
        user.name = name
        user.height = height
        user.weight = weight
        user.gender = gender
        user.updatedAt = Date()
        
        self.currentUser = user
        try await saveUserData(user)
    }
    
    private func saveUserData(_ user: User) async throws {
        let encoder = Firestore.Encoder()
        encoder.dateEncodingStrategy = .timestamp
        guard let userData = try? encoder.encode(user) else { return }
        try await db.collection("users").document(user.uid).setData(userData, merge: true)
    }
    
    private func loadUserData() async {
        guard let authUser = Auth.auth().currentUser else { return }
        
        do {
            let document = try await db.collection("users").document(authUser.uid).getDocument()
            if let data = document.data() {
                let decoder = Firestore.Decoder()
                decoder.dateDecodingStrategy = .timestamp
                if let user = try? decoder.decode(User.self, from: data) {
                    await MainActor.run {
                        self.currentUser = user
                    }
                }
            }
        } catch {
            print("Error loading user data: \(error)")
        }
    }
    
    // MARK: - Data Sync
    
    func syncTodos(_ todos: [TodoItem]) async throws {
        guard let uid = currentUser?.uid else { return }
        let encoder = Firestore.Encoder()
        encoder.dateEncodingStrategy = .timestamp
        let todosData = try todos.map { try encoder.encode($0) }
        try await db.collection("users").document(uid).collection("todos").document("list").setData([
            "items": todosData,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }
    
    func loadTodos() async throws -> [TodoItem] {
        guard let uid = currentUser?.uid else { return [] }
        let document = try await db.collection("users").document(uid).collection("todos").document("list").getDocument()
        
        guard let data = document.data(),
              let itemsData = data["items"] as? [[String: Any]] else { return [] }
        
        let decoder = Firestore.Decoder()
        decoder.dateDecodingStrategy = .timestamp
        return try itemsData.compactMap { itemData in
            try decoder.decode(TodoItem.self, from: itemData)
        }
    }
    
    func syncCalories(_ calories: CaloriesStore) async throws {
        guard let uid = currentUser?.uid else { return }
        let encoder = Firestore.Encoder()
        encoder.dateEncodingStrategy = .timestamp
        let data: [String: Any] = [
            "goals": try encoder.encode(calories.goals),
            "entries": try calories.entries.map { try encoder.encode($0) },
            "updatedAt": Timestamp(date: Date())
        ]
        try await db.collection("users").document(uid).collection("nutrition").document("data").setData(data, merge: true)
    }
    
    func loadCalories() async throws -> (goals: NutritionGoals, entries: [CalorieEntry]) {
        guard let uid = currentUser?.uid else {
            return (NutritionGoals(), [])
        }
        
        let document = try await db.collection("users").document(uid).collection("nutrition").document("data").getDocument()
        guard let data = document.data() else {
            return (NutritionGoals(), [])
        }
        
        let decoder = Firestore.Decoder()
        decoder.dateDecodingStrategy = .timestamp
        
        var goals = NutritionGoals()
        if let goalsData = data["goals"] as? [String: Any] {
            goals = try decoder.decode(NutritionGoals.self, from: goalsData)
        }
        
        var entries: [CalorieEntry] = []
        if let entriesData = data["entries"] as? [[String: Any]] {
            entries = try entriesData.compactMap { try decoder.decode(CalorieEntry.self, from: $0) }
        }
        
        return (goals, entries)
    }
    
    func syncFitnessGoals(_ goals: FitnessGoals) async throws {
        guard let uid = currentUser?.uid else { return }
        let encoder = Firestore.Encoder()
        encoder.dateEncodingStrategy = .timestamp
        let data = try encoder.encode(goals)
        try await db.collection("users").document(uid).collection("fitness").document("goals").setData(data, merge: true)
    }
    
    func loadFitnessGoals() async throws -> FitnessGoals? {
        guard let uid = currentUser?.uid else { return nil }
        let document = try await db.collection("users").document(uid).collection("fitness").document("goals").getDocument()
        guard let data = document.data() else { return nil }
        let decoder = Firestore.Decoder()
        decoder.dateDecodingStrategy = .timestamp
        return try decoder.decode(FitnessGoals.self, from: data)
    }
    
    func syncWorkoutSplits(_ splits: [WorkoutSplit]) async throws {
        guard let uid = currentUser?.uid else { return }
        let encoder = Firestore.Encoder()
        encoder.dateEncodingStrategy = .timestamp
        let splitsData = try splits.map { try encoder.encode($0) }
        try await db.collection("users").document(uid).collection("fitness").document("splits").setData([
            "splits": splitsData,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }
    
    func loadWorkoutSplits() async throws -> [WorkoutSplit] {
        guard let uid = currentUser?.uid else { return [] }
        let document = try await db.collection("users").document(uid).collection("fitness").document("splits").getDocument()
        guard let data = document.data(),
              let splitsData = data["splits"] as? [[String: Any]] else { return [] }
        let decoder = Firestore.Decoder()
        decoder.dateDecodingStrategy = .timestamp
        return try splitsData.compactMap { try decoder.decode(WorkoutSplit.self, from: $0) }
    }
    
    func syncGyms(_ gyms: [Gym]) async throws {
        guard let uid = currentUser?.uid else { return }
        let encoder = Firestore.Encoder()
        encoder.dateEncodingStrategy = .timestamp
        let gymsData = try gyms.map { try encoder.encode($0) }
        try await db.collection("users").document(uid).collection("locations").document("gyms").setData([
            "gyms": gymsData,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }
    
    func loadGyms() async throws -> [Gym] {
        guard let uid = currentUser?.uid else { return [] }
        let document = try await db.collection("users").document(uid).collection("locations").document("gyms").getDocument()
        guard let data = document.data(),
              let gymsData = data["gyms"] as? [[String: Any]] else { return [] }
        let decoder = Firestore.Decoder()
        decoder.dateDecodingStrategy = .timestamp
        return try gymsData.compactMap { try decoder.decode(Gym.self, from: $0) }
    }
    
    // MARK: - Calendar Events Sync
    
    struct CalendarEvent: Codable, Identifiable {
        let id: String
        var title: String
        var date: Date
        var createdAt: Date
        
        init(id: String = UUID().uuidString, title: String, date: Date, createdAt: Date = Date()) {
            self.id = id
            self.title = title
            self.date = date
            self.createdAt = createdAt
        }
    }
    
    func syncCalendarEvents(_ events: [CalendarEvent]) async throws {
        guard let uid = currentUser?.uid else { return }
        let encoder = Firestore.Encoder()
        encoder.dateEncodingStrategy = .timestamp
        let eventsData = try events.map { try encoder.encode($0) }
        try await db.collection("users").document(uid).collection("calendar").document("events").setData([
            "events": eventsData,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }
    
    func loadCalendarEvents() async throws -> [CalendarEvent] {
        guard let uid = currentUser?.uid else { return [] }
        let document = try await db.collection("users").document(uid).collection("calendar").document("events").getDocument()
        guard let data = document.data(),
              let eventsData = data["events"] as? [[String: Any]] else { return [] }
        let decoder = Firestore.Decoder()
        decoder.dateDecodingStrategy = .timestamp
        return try eventsData.compactMap { try decoder.decode(CalendarEvent.self, from: $0) }
    }
    
    // MARK: - Workout Sessions Sync
    
    func syncWorkoutSessions(_ sessions: [WorkoutSession]) async throws {
        guard let uid = currentUser?.uid else { return }
        let encoder = Firestore.Encoder()
        encoder.dateEncodingStrategy = .timestamp
        let sessionsData = try sessions.map { try encoder.encode($0) }
        try await db.collection("users").document(uid).collection("fitness").document("sessions").setData([
            "sessions": sessionsData,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }
    
    func loadWorkoutSessions() async throws -> [WorkoutSession] {
        guard let uid = currentUser?.uid else { return [] }
        let document = try await db.collection("users").document(uid).collection("fitness").document("sessions").getDocument()
        guard let data = document.data(),
              let sessionsData = data["sessions"] as? [[String: Any]] else { return [] }
        let decoder = Firestore.Decoder()
        decoder.dateDecodingStrategy = .timestamp
        return try sessionsData.compactMap { try decoder.decode(WorkoutSession.self, from: $0) }
    }
}


