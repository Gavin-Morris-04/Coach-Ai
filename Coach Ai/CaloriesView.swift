import SwiftUI

struct CalorieEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var date: Date
    
    init(id: UUID = UUID(), name: String, calories: Int, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fiber: Double = 0, date: Date = Date()) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.date = date
    }
}

struct NutritionGoals: Codable {
    var calories: Int = 2000
    var protein: Double = 150 // grams
    var carbs: Double = 250 // grams
    var fat: Double = 65 // grams
    var fiber: Double = 30 // grams
}

final class CaloriesStore: ObservableObject {
    static let shared = CaloriesStore()
    @Published var entries: [CalorieEntry] = [] { didSet { persist(); syncToFirebase() } }
    @Published var goals = NutritionGoals() { didSet { persistGoals(); syncToFirebase() } }
    private let storageKey = "calorie.entries.v2"
    private let goalsKey = "nutrition.goals.v1"
    private var isSyncing = false

    init() {
        // Only load from local storage if user is authenticated
        if FirebaseService.shared.isAuthenticated {
            load()
            loadGoals()
        }
        Task {
            await loadFromFirebase()
        }
    }
    
    private func syncToFirebase() {
        guard !isSyncing, FirebaseService.shared.isAuthenticated else { return }
        isSyncing = true
        Task {
            do {
                try await FirebaseService.shared.syncCalories(self)
                await MainActor.run {
                    isSyncing = false
                }
            } catch {
                print("Error syncing calories to Firebase: \(error)")
                await MainActor.run {
                    isSyncing = false
                    ErrorManager.shared.showErrorMessage(
                        "Failed to sync nutrition data to cloud. Your changes are saved locally and will sync when connection is restored.",
                        title: "Sync Error"
                    )
                }
            }
        }
    }
    
    func loadFromFirebase() async {
        guard FirebaseService.shared.isAuthenticated else {
            await MainActor.run {
                self.entries = []
                self.goals = NutritionGoals()
            }
            return
        }
        do {
            let (firebaseGoals, firebaseEntries) = try await FirebaseService.shared.loadCalories()
            await MainActor.run {
                // Always use Firebase data if available
                self.entries = firebaseEntries
                if firebaseGoals.calories > 0 {
                    self.goals = firebaseGoals
                }
            }
        } catch {
            print("Error loading calories from Firebase: \(error)")
        }
    }

    var todayTotal: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.date >= startOfDay }.reduce(0) { $0 + $1.calories }
    }
    
    var todayProtein: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.date >= startOfDay }.reduce(0) { $0 + $1.protein }
    }
    
    var todayCarbs: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.date >= startOfDay }.reduce(0) { $0 + $1.carbs }
    }
    
    var todayFat: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.date >= startOfDay }.reduce(0) { $0 + $1.fat }
    }
    
    var todayFiber: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.date >= startOfDay }.reduce(0) { $0 + $1.fiber }
    }
    
    var todayEntries: [CalorieEntry] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.date >= startOfDay }
    }

    func add(name: String, calories: Int, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fiber: Double = 0) {
        let entry = CalorieEntry(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, date: Date())
        entries.insert(entry, at: 0)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func persistGoals() {
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CalorieEntry].self, from: data) else { return }
        entries = decoded
    }
    
    private func loadGoals() {
        guard let data = UserDefaults.standard.data(forKey: goalsKey),
              let decoded = try? JSONDecoder().decode(NutritionGoals.self, from: data) else { return }
        goals = decoded
    }
}

struct CaloriesView: View {
    @StateObject private var store = CaloriesStore.shared
    @State private var showAddSheet = false

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
                    // Nutrition Summary Card
                    NutritionSummaryCard(store: store)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    
                    // Entries List
                    ScrollView {
                        VStack(spacing: 12) {
                            if store.todayEntries.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "fork.knife")
                                        .font(.system(size: 60))
                                        .foregroundStyle(.white.opacity(0.3))
                                    Text("No entries today")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text("Start tracking your nutrition!")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .padding(.top, 60)
                            } else {
                                ForEach(store.todayEntries) { entry in
                                    DetailedCalorieEntryRow(entry: entry, store: store)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 100)
                    }
                }
                
                // Add Entry Button (Fixed at bottom)
                VStack {
                    Spacer()
                    Button(action: {
                        showAddSheet = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Food")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
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
            .sheet(isPresented: $showAddSheet) {
                AddFoodDetailSheet(store: store, isPresented: $showAddSheet)
            }
        }
    }
}

struct NutritionSummaryCard: View {
    @ObservedObject var store: CaloriesStore
    
    var body: some View {
        VStack(spacing: 20) {
            // Calories
            VStack(spacing: 8) {
                HStack {
                    Text("Calories")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("\(store.todayTotal) / \(store.goals.calories)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.1))
                            .frame(height: 16)
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: min(geometry.size.width * CGFloat(store.todayTotal) / CGFloat(store.goals.calories), geometry.size.width), height: 16)
                    }
                }
                .frame(height: 16)
            }
            
            // Macronutrients
            VStack(spacing: 12) {
                NutrientRow(
                    name: "Protein",
                    current: store.todayProtein,
                    goal: store.goals.protein,
                    unit: "g",
                    color: .blue
                )
                NutrientRow(
                    name: "Carbs",
                    current: store.todayCarbs,
                    goal: store.goals.carbs,
                    unit: "g",
                    color: .green
                )
                NutrientRow(
                    name: "Fat",
                    current: store.todayFat,
                    goal: store.goals.fat,
                    unit: "g",
                    color: .yellow
                )
                NutrientRow(
                    name: "Fiber",
                    current: store.todayFiber,
                    goal: store.goals.fiber,
                    unit: "g",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.2), Color.pink.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}

struct NutrientRow: View {
    let name: String
    let current: Double
    let goal: Double
    let unit: String
    let color: Color
    
    var percentage: Double {
        guard goal > 0 else { return 0 }
        return min(current / goal, 1.0)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(Int(current)) / \(Int(goal)) \(unit)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.1))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

struct DetailedCalorieEntryRow: View {
    let entry: CalorieEntry
    @ObservedObject var store: CaloriesStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text(entry.date, style: .time)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                Spacer()
                
                Text("\(entry.calories) kcal")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            if entry.protein > 0 || entry.carbs > 0 || entry.fat > 0 {
                HStack(spacing: 16) {
                    if entry.protein > 0 {
                        Label("\(Int(entry.protein))g", systemImage: "p.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                    if entry.carbs > 0 {
                        Label("\(Int(entry.carbs))g", systemImage: "c.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                    if entry.fat > 0 {
                        Label("\(Int(entry.fat))g", systemImage: "f.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                    }
                    if entry.fiber > 0 {
                        Label("\(Int(entry.fiber))g", systemImage: "leaf.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.purple)
                    }
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation {
                    if let index = store.entries.firstIndex(of: entry) {
                        store.entries.remove(at: index)
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct AddFoodDetailSheet: View {
    @ObservedObject var store: CaloriesStore
    @Binding var isPresented: Bool
    @State private var name: String = ""
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
    @State private var fiberText: String = ""
    @State private var showSimpleMode = true
    
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
                        // Mode Toggle
                        Picker("Mode", selection: $showSimpleMode) {
                            Text("Simple").tag(true)
                            Text("Detailed").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Food Name
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Food Name")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            TextField("Enter food name...", text: $name)
                                .textFieldStyle(.plain)
                                .padding(16)
                                .background(.white.opacity(0.1))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 20)
                        
                        // Calories (always shown)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Calories")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            TextField("kcal", text: $caloriesText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.plain)
                                .padding(16)
                                .background(.white.opacity(0.1))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 20)
                        
                        // Detailed Nutrients (if detailed mode)
                        if !showSimpleMode {
                            VStack(spacing: 20) {
                                NutrientInputField(title: "Protein (g)", text: $proteinText, color: .blue)
                                NutrientInputField(title: "Carbs (g)", text: $carbsText, color: .green)
                                NutrientInputField(title: "Fat (g)", text: $fatText, color: .yellow)
                                NutrientInputField(title: "Fiber (g)", text: $fiberText, color: .purple)
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            let cals = Int(caloriesText) ?? 0
                            let protein = Double(proteinText) ?? 0
                            let carbs = Double(carbsText) ?? 0
                            let fat = Double(fatText) ?? 0
                            let fiber = Double(fiberText) ?? 0
                            
                            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cals > 0 else { return }
                            store.add(name: name, calories: cals, protein: protein, carbs: carbs, fat: fat, fiber: fiber)
                            isPresented = false
                        }) {
                            Text("Add Food")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.orange, Color.pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Int(caloriesText) == nil || Int(caloriesText) == 0)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

struct NutrientInputField: View {
    let title: String
    @Binding var text: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(16)
                .background(.white.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.5), lineWidth: 1)
                )
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    CaloriesView()
}
