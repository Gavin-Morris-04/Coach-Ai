import SwiftUI

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var done: Bool
    var dueDate: Date?
    var createdAt: Date
    
    init(id: UUID = UUID(), title: String, done: Bool = false, dueDate: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.done = done
        self.dueDate = dueDate
        self.createdAt = createdAt
    }
    
    var isOverdue: Bool {
        guard let due = dueDate, !done else { return false }
        return due < Date()
    }
    
    var isDueSoon: Bool {
        guard let due = dueDate, !done else { return false }
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0
        return daysUntil >= 0 && daysUntil <= 2
    }
}

final class TodoStore: ObservableObject {
    static let shared = TodoStore()
    @Published var items: [TodoItem] = [] { didSet { persist(); syncToFirebase() } }

    private let storageKey = "todo.items.v2"
    private var isSyncing = false

    init() {
        // Only load from local storage if user is authenticated
        // This prevents loading old data from previous users
        if FirebaseService.shared.isAuthenticated {
            load()
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
                try await FirebaseService.shared.syncTodos(items)
                await MainActor.run {
                    isSyncing = false
                }
            } catch {
                print("Error syncing todos to Firebase: \(error)")
                await MainActor.run {
                    isSyncing = false
                    ErrorManager.shared.showErrorMessage(
                        "Failed to sync tasks to cloud. Your changes are saved locally and will sync when connection is restored.",
                        title: "Sync Error"
                    )
                }
            }
        }
    }
    
    func loadFromFirebase() async {
        guard FirebaseService.shared.isAuthenticated else {
            // Clear local data if not authenticated
            await MainActor.run {
                self.items = []
            }
            return
        }
        do {
            let firebaseTodos = try await FirebaseService.shared.loadTodos()
            await MainActor.run {
                // Always use Firebase data if available, otherwise keep local
                if !firebaseTodos.isEmpty {
                    self.items = firebaseTodos
                } else {
                    // If Firebase is empty, clear local data too (new user)
                    self.items = []
                }
            }
        } catch {
            print("Error loading todos from Firebase: \(error)")
        }
    }

    func add(_ title: String, dueDate: Date? = nil) {
        let new = TodoItem(title: title, done: false, dueDate: dueDate)
        items.insert(new, at: 0)
    }

    func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].done.toggle()
    }
    
    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
    }
    
    var activeItems: [TodoItem] {
        items.filter { !$0.done }.sorted { item1, item2 in
            // Sort by due date, overdue first, then due soon, then no date
            if item1.isOverdue && !item2.isOverdue { return true }
            if !item1.isOverdue && item2.isOverdue { return false }
            if item1.isDueSoon && !item2.isDueSoon { return true }
            if !item1.isDueSoon && item2.isDueSoon { return false }
            if let due1 = item1.dueDate, let due2 = item2.dueDate {
                return due1 < due2
            }
            if item1.dueDate != nil && item2.dueDate == nil { return true }
            if item1.dueDate == nil && item2.dueDate != nil { return false }
            return item1.createdAt > item2.createdAt
        }
    }
    
    var completedItems: [TodoItem] {
        items.filter { $0.done }.sorted { $0.createdAt > $1.createdAt }
    }
    
    var todayItems: [TodoItem] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return activeItems.filter { item in
            guard let due = item.dueDate else { return false }
            return due >= today && due < tomorrow
        }
    }
    
    var completionPercentage: Double {
        guard !items.isEmpty else { return 0 }
        let completed = items.filter { $0.done }.count
        return Double(completed) / Double(items.count)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        items = decoded
    }
}

struct TodoListView: View {
    @StateObject private var store = TodoStore.shared
    @State private var newTitle: String = ""
    @State private var showAddSheet = false
    @State private var selectedDueDate: Date? = nil
    @State private var showCompleted = false

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
                    // Completion Progress Card (Video Game Style)
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mission Progress")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("\(Int(store.completionPercentage * 100))% Complete")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            ZStack {
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: 8)
                                    .frame(width: 80, height: 80)
                                
                                Circle()
                                    .trim(from: 0, to: store.completionPercentage)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.green, Color.mint],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                    )
                                    .frame(width: 80, height: 80)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: store.completionPercentage)
                                
                                Text("\(Int(store.completionPercentage * 100))%")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        
                        // Progress Bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.1))
                                    .frame(height: 12)
                                
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.green, Color.mint],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * store.completionPercentage, height: 12)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: store.completionPercentage)
                            }
                        }
                        .frame(height: 12)
                    }
                    .padding(20)
                    .background(
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.mint.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Task List
                    ScrollView {
                        VStack(spacing: 20) {
                            // Active Tasks Section
                            if !store.activeItems.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Active Tasks")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text("\(store.activeItems.count)")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    .padding(.horizontal, 20)
                                    
                                    ForEach(store.activeItems) { item in
                                        TaskRow(item: item, store: store)
                                    }
                                }
                            }
                            
                            // Completed Tasks Section
                            if !store.completedItems.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Button(action: {
                                        withAnimation {
                                            showCompleted.toggle()
                                        }
                                    }) {
                                        HStack {
                                            Text("Completed")
                                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text("\(store.completedItems.count)")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.6))
                                            Image(systemName: showCompleted ? "chevron.up" : "chevron.down")
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                    
                                    if showCompleted {
                                        ForEach(store.completedItems) { item in
                                            TaskRow(item: item, store: store)
                                        }
                                    }
                                }
                            }
                            
                            if store.items.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "checklist")
                                        .font(.system(size: 60))
                                        .foregroundStyle(.white.opacity(0.3))
                                    Text("No tasks yet")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text("Add your first task below!")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .padding(.top, 60)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 100)
                    }
                }
                
                // Add Task Button (Fixed at bottom)
                VStack {
                    Spacer()
                    Button(action: {
                        showAddSheet = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Task")
                        }
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
                AddTaskSheet(store: store, isPresented: $showAddSheet)
            }
        }
    }
}

struct AddTaskSheet: View {
    @ObservedObject var store: TodoStore
    @Binding var isPresented: Bool
    var initialDate: Date? = nil
    @State private var title: String = ""
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date
    
    init(store: TodoStore, isPresented: Binding<Bool>, initialDate: Date? = nil) {
        self.store = store
        self._isPresented = isPresented
        self.initialDate = initialDate
        self._dueDate = State(initialValue: initialDate ?? Date())
        self._hasDueDate = State(initialValue: initialDate != nil)
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
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Task Title")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        TextField("Enter task...", text: $title)
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
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Set Due Date", isOn: $hasDueDate)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        if hasDueDate {
                            DatePicker("Done by", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .colorScheme(.dark)
                                .accentColor(.white)
                        }
                    }
                    .padding(16)
                    .background(.white.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    
                    Spacer()
                    
                    Button(action: {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.add(trimmed, dueDate: hasDueDate ? dueDate : nil)
                        isPresented = false
                    }) {
                        Text("Add Task")
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("New Task")
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

struct TaskRow: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    store.toggle(item)
                }
            }) {
                ZStack {
                    Circle()
                        .fill(item.done ? Color.green : Color.white.opacity(0.1))
                        .frame(width: 28, height: 28)
                    
                    if item.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 16, weight: item.done ? .medium : .semibold))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? .white.opacity(0.5) : .white)
                
                if let due = item.dueDate, !item.done {
                    HStack(spacing: 4) {
                        Image(systemName: item.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(item.isOverdue ? .red : (item.isDueSoon ? .orange : .white.opacity(0.6)))
                        
                        Text(formatDueDate(due))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(item.isOverdue ? .red : (item.isDueSoon ? .orange : .white.opacity(0.6)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    store.delete(item)
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    item.isOverdue && !item.done ? Color.red.opacity(0.2) : Color.white.opacity(0.1),
                    item.isOverdue && !item.done ? Color.red.opacity(0.1) : Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    item.isOverdue && !item.done ? Color.red.opacity(0.5) : .white.opacity(0.2),
                    lineWidth: item.isOverdue && !item.done ? 2 : 1
                )
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation {
                    if let index = store.items.firstIndex(of: item) {
                        store.items.remove(at: index)
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Due today at \(date.formatted(date: .omitted, time: .shortened))"
        } else if calendar.isDateInTomorrow(date) {
            return "Due tomorrow at \(date.formatted(date: .omitted, time: .shortened))"
        } else if date < now {
            let daysAgo = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            return "Overdue by \(daysAgo) day\(daysAgo == 1 ? "" : "s")"
        } else {
            let daysUntil = calendar.dateComponents([.day], from: now, to: date).day ?? 0
            if daysUntil <= 7 {
                return "Due in \(daysUntil) day\(daysUntil == 1 ? "" : "s")"
            } else {
                return "Due \(date.formatted(date: .abbreviated, time: .shortened))"
            }
        }
    }
}

#Preview {
    TodoListView()
}
