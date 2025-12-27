import SwiftUI
import EventKit
import MapKit

struct HomeView: View {
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var location = LocationManager.shared
    @StateObject private var coach = CoachBot.shared
    @StateObject private var todos = TodoStore.shared
    @StateObject private var calories = CaloriesStore.shared
    @StateObject private var calendar = CalendarManager.shared
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedDate = Date()
    @State private var showAddEventSheet = false
    @State private var showAddTodoSheet = false
    @State private var showDayDetailSheet = false
    @State private var showSettingsSheet = false
    @State private var selectedTab = 0
    @Binding var activeTab: Int
    
    init(activeTab: Binding<Int> = .constant(0)) {
        _activeTab = activeTab
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome Back, \(firebase.currentUser?.name ?? "User")!")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Let's make today count")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Summary Stats Section (Top)
                    VStack(spacing: 16) {
                        // Steps Summary
                        HStack {
                            Image(systemName: "figure.walk")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Steps")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("\(health.todaySteps)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
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
                        
                        // To-Do List Summary
                        Button(action: {
                            activeTab = 1
                        }) {
                            HStack {
                                Image(systemName: "checklist.checked")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tasks")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                    Text("\(todos.items.filter { $0.done }.count)/\(todos.items.count) completed")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.5))
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
                        
                        // Calories Summary
                        NavigationLink(destination: CaloriesView()) {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Calories")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                    Text("\(calories.todayTotal) kcal")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.5))
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
                    .padding(.horizontal, 20)
                    
                    // Calendar and Upcoming Events Section (Middle)
                    VStack(spacing: 20) {
                        // Calendar Widget
                        CalendarWidget(
                            selectedDate: $selectedDate,
                            showAddEvent: $showAddEventSheet,
                            showAddTodo: $showAddTodoSheet,
                            showDayDetail: $showDayDetailSheet
                        )
                        .padding(.horizontal, 20)
                        
                        // Upcoming Events Section
                        UpcomingEventsSection(todos: todos, calendar: calendar)
                            .padding(.horizontal, 20)
                    }
                    
                    // Coach AI Section (Bottom)
                    Button(action: {
                        activeTab = 2
                    }) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                Text("Your Coach")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                            Text(coach.latestCoachMessage)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(4)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
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
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 30)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSettingsSheet = true
                    }) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showAddEventSheet) {
                AddEventQuickSheet(selectedDate: selectedDate, isPresented: $showAddEventSheet)
            }
            .sheet(isPresented: $showAddTodoSheet) {
                AddTaskSheet(store: todos, isPresented: $showAddTodoSheet, initialDate: selectedDate)
            }
            .sheet(isPresented: $showDayDetailSheet) {
                DayDetailSheet(selectedDate: selectedDate, todos: todos, isPresented: $showDayDetailSheet)
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
            }
            .task {
                await health.ensureAuthorization()
                await NotificationsManager.shared.requestAuthorization()
                location.requestAuthorization()
            }
        }
    }
}

struct CalendarWidget: View {
    @Binding var selectedDate: Date
    @Binding var showAddEvent: Bool
    @Binding var showAddTodo: Bool
    @Binding var showDayDetail: Bool
    @State private var currentMonth = Date()
    
    var body: some View {
        VStack(spacing: 16) {
            // Month Header
            HStack {
                Button(action: {
                    withAnimation {
                        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 8)
            
            // Calendar Grid
            let days = generateDaysForMonth(currentMonth)
            let columns = Array(repeating: GridItem(.flexible()), count: 7)
            
            LazyVGrid(columns: columns, spacing: 8) {
                // Day headers
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                // Calendar days
                ForEach(days, id: \.self) { date in
                    CalendarDayView(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        isToday: Calendar.current.isDateInToday(date),
                        hasEvent: hasEventOnDate(date),
                        hasTodo: hasTodoOnDate(date)
                    ) {
                        withAnimation {
                            selectedDate = date
                            showDayDetail = true
                        }
                    }
                }
            }
            
            // Quick Actions
            HStack(spacing: 12) {
                Button(action: {
                    showAddEvent = true
                }) {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text("Add Event")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.white.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Button(action: {
                    showAddTodo = true
                }) {
                    HStack {
                        Image(systemName: "checklist")
                        Text("Add Todo")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.white.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
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
    
    private func generateDaysForMonth(_ month: Date) -> [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let daysToSubtract = (firstWeekday - calendar.firstWeekday + 7) % 7
        
        var days: [Date] = []
        var currentDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDay) ?? firstDay
        
        for _ in 0..<42 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return days
    }
    
    private func hasEventOnDate(_ date: Date) -> Bool {
        // Check if there are calendar events (simplified - you'd check actual calendar)
        return false
    }
    
    private func hasTodoOnDate(_ date: Date) -> Bool {
        return TodoStore.shared.items.contains { item in
            guard let due = item.dueDate else { return false }
            return Calendar.current.isDate(due, inSameDayAs: date)
        }
    }
}

struct CalendarDayView: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasEvent: Bool
    let hasTodo: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? .white :
                        isToday ? .blue :
                        .white.opacity(0.8)
                    )
                
                if hasTodo {
                    Circle()
                        .fill(.green)
                        .frame(width: 4, height: 4)
                } else if hasEvent {
                    Circle()
                        .fill(.blue)
                        .frame(width: 4, height: 4)
                } else {
                    Spacer()
                        .frame(height: 4)
                }
            }
            .frame(width: 40, height: 40)
            .background(
                Group {
                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else if isToday {
                        Circle()
                            .stroke(.blue, lineWidth: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

struct QuickTaskCard: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    store.toggle(item)
                }) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.done ? .green : .white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            
            if let due = item.dueDate {
                Text(due.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(12)
        .frame(width: 140)
        .background(.white.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}

struct AddEventQuickSheet: View {
    let selectedDate: Date
    @Binding var isPresented: Bool
    @State private var title: String = ""
    @StateObject private var calendar = CalendarManager.shared
    
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
                        Text("Event Title")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        TextField("Enter event...", text: $title)
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
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date & Time")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        Text(selectedDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            let ok = await calendar.addEvent(title: title, date: selectedDate)
                            if ok {
                                isPresented = false
                            }
                        }
                    }) {
                        Text("Add Event")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
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
            .navigationTitle("New Event")
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

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    let gradient: [Color]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: gradient.map { $0.opacity(0.3) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}

struct DayDetailSheet: View {
    let selectedDate: Date
    @ObservedObject var todos: TodoStore
    @StateObject private var calendar = CalendarManager.shared
    @Binding var isPresented: Bool
    @State private var showAddEvent = false
    @State private var showAddTodo = false
    
    var dayTodos: [TodoItem] {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        return todos.items.filter { item in
            guard let due = item.dueDate else { return false }
            return due >= startOfDay && due < endOfDay
        }
    }
    
    var dayEvents: [EKEvent] {
        calendar.getEvents(for: selectedDate)
    }
    
    var dayUserEvents: [FirebaseService.CalendarEvent] {
        calendar.getUserEvents(for: selectedDate)
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
                        // Date Header
                        VStack(spacing: 8) {
                            Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(selectedDate.formatted(.dateTime.month(.wide).day().year()))
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.top, 20)
                        
                        // Events Section
                        if !dayEvents.isEmpty || !dayUserEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Events")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                
                                // Device calendar events
                                ForEach(dayEvents, id: \.eventIdentifier) { event in
                                    EventRow(event: event)
                                        .padding(.horizontal, 20)
                                }
                                
                                // User-specific events from Firebase
                                ForEach(dayUserEvents) { event in
                                    UserEventRow(event: event)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        // Todos Section
                        if !dayTodos.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Tasks")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                
                                ForEach(dayTodos) { item in
                                    TaskRow(item: item, store: todos)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        // Empty State
                        if dayTodos.isEmpty && dayEvents.isEmpty && dayUserEvents.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.white.opacity(0.3))
                                Text("No events or tasks scheduled")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.top, 40)
                        }
                        
                        // Add Event and Task Buttons
                        HStack(spacing: 16) {
                            Button(action: {
                                showAddEvent = true
                            }) {
                                HStack {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Add Event")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                            }
                            
                            Button(action: {
                                showAddTodo = true
                            }) {
                                HStack {
                                    Image(systemName: "checklist")
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
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Day Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
            .sheet(isPresented: $showAddEvent) {
                AddEventQuickSheet(selectedDate: selectedDate, isPresented: $showAddEvent)
            }
            .sheet(isPresented: $showAddTodo) {
                AddTaskSheet(store: todos, isPresented: $showAddTodo, initialDate: selectedDate)
            }
            .task {
                await calendar.requestAccess()
            }
        }
    }
}

struct UserEventRow: View {
    let event: FirebaseService.CalendarEvent
    
    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(event.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct EventRow: View {
    let event: EKEvent
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                
                HStack(spacing: 8) {
                    if event.isAllDay {
                        Text("All Day")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        if !event.isAllDay && event.endDate != event.startDate {
                            Text("–")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                            
                            Text(event.endDate.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.2),
                    Color.purple.opacity(0.2)
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
    }
}

struct UpcomingEventsSection: View {
    @ObservedObject var todos: TodoStore
    @ObservedObject var calendar: CalendarManager
    
    var upcomingTodos: [TodoItem] {
        let now = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        return todos.activeItems.filter { item in
            guard let due = item.dueDate else { return false }
            return due > now && due <= nextWeek
        }.sorted { ($0.dueDate ?? Date.distantFuture) < ($1.dueDate ?? Date.distantFuture) }
        .prefix(5)
        .map { $0 }
    }
    
    var body: some View {
        if !upcomingTodos.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Upcoming Events")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                
                VStack(spacing: 12) {
                    ForEach(upcomingTodos) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                
                                if let due = item.dueDate {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.6))
                                        Text(due.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if item.isDueSoon {
                                Text("Soon")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.orange.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(16)
                        .background(.white.opacity(0.1))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}

struct HomeMapView: View {
    @StateObject private var location = LocationManager.shared
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        Map(position: $cameraPosition) {
            // User location marker
            if let userLocation = location.lastKnownLocation {
                Annotation("Your Location", coordinate: userLocation.coordinate) {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 20, height: 20)
                        Circle()
                            .fill(.blue.opacity(0.3))
                            .frame(width: 30, height: 30)
                    }
                }
            }
            
            // Show saved gyms
            ForEach(location.gyms) { gym in
                Marker(gym.name, coordinate: gym.coordinate)
                    .tint(.purple)
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapUserLocationButton()
        }
        .onAppear {
            // Initialize map to user's location
            if let userLocation = location.lastKnownLocation {
                let region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                cameraPosition = .region(region)
            } else {
                location.requestAuthorization()
            }
        }
        .task {
            // Wait for location update
            if location.lastKnownLocation == nil {
                location.requestAuthorization()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                if let userLocation = location.lastKnownLocation {
                    let region = MKCoordinateRegion(
                        center: userLocation.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    cameraPosition = .region(region)
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
