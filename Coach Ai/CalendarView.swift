import SwiftUI
import EventKit

final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    private let eventStore = EKEventStore()
    @Published var isAuthorized: Bool = false
    @Published var userEvents: [FirebaseService.CalendarEvent] = [] {
        didSet {
            syncToFirebase()
        }
    }
    private var isSyncing = false

    init() {
        Task {
            await loadFromFirebase()
        }
    }

    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run { self.isAuthorized = granted }
        } catch {
            await MainActor.run { self.isAuthorized = false }
        }
    }

    func addEvent(title: String, date: Date) async -> Bool {
        guard isAuthorized else { return false }
        
        // Add to device calendar
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.startDate = date
        event.endDate = date.addingTimeInterval(60 * 60)
        
        do {
            try eventStore.save(event, span: .thisEvent)
            
            // Also save to Firebase
            await MainActor.run {
                let firebaseEvent = FirebaseService.CalendarEvent(title: title, date: date)
                self.userEvents.append(firebaseEvent)
            }
            
            return true
        } catch {
            await MainActor.run {
                ErrorManager.shared.showErrorMessage(
                    "Failed to add event to calendar. Please check your calendar permissions in Settings.",
                    title: "Calendar Error"
                )
            }
            return false
        }
    }
    
    func getEvents(for date: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        return eventStore.events(matching: predicate)
    }
    
    func getUserEvents(for date: Date) -> [FirebaseService.CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return userEvents.filter { event in
            event.date >= startOfDay && event.date < endOfDay
        }
    }
    
    private func syncToFirebase() {
        guard !isSyncing, FirebaseService.shared.isAuthenticated else { return }
        isSyncing = true
        Task {
            do {
                try await FirebaseService.shared.syncCalendarEvents(userEvents)
                await MainActor.run {
                    isSyncing = false
                }
            } catch {
                print("Error syncing calendar events to Firebase: \(error)")
                await MainActor.run {
                    isSyncing = false
                    ErrorManager.shared.showErrorMessage(
                        "Failed to sync calendar events to cloud. Your changes are saved locally and will sync when connection is restored.",
                        title: "Sync Error"
                    )
                }
            }
        }
    }
    
    func loadFromFirebase() async {
        guard FirebaseService.shared.isAuthenticated else {
            await MainActor.run {
                self.userEvents = []
            }
            return
        }
        do {
            let firebaseEvents = try await FirebaseService.shared.loadCalendarEvents()
            await MainActor.run {
                self.userEvents = firebaseEvents
            }
        } catch {
            print("Error loading calendar events from Firebase: \(error)")
        }
    }
}

struct CalendarView: View {
    @StateObject private var cal = CalendarManager.shared
    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var addResult: String = ""
    @State private var showSuccess: Bool = false

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
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Schedule Workout")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Plan your fitness events")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Event Form Card
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Event Title")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                
                                TextField("e.g., Morning Run", text: $title)
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
                                Text("Date & Time")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                
                                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .colorScheme(.dark)
                                    .accentColor(.white)
                            }
                            
                            if !addResult.isEmpty {
                                HStack {
                                    Image(systemName: showSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(showSuccess ? .green : .red)
                                    Text(addResult)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(showSuccess ? .green : .red)
                                }
                                .padding(12)
                                .background(
                                    (showSuccess ? Color.green : Color.red).opacity(0.2)
                                )
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                Task {
                                    let ok = await cal.addEvent(title: title, date: date)
                                    await MainActor.run {
                                        showSuccess = ok
                                        addResult = ok ? "Event added successfully!" : "Failed to add event. Check calendar permissions."
                                        if ok {
                                            title = ""
                                            date = Date()
                                        }
                                    }
                                    if ok {
                                        await NotificationsManager.shared.scheduleCoachReminder(
                                            body: "Event: \(title)",
                                            at: date.addingTimeInterval(-900)
                                        )
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Add to Calendar")
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
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                            
                            if !cal.isAuthorized {
                                VStack(spacing: 8) {
                                    Text("Calendar access required")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                    
                                    Button("Grant Access") {
                                        Task {
                                            await cal.requestAccess()
                                        }
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.blue)
                                }
                                .padding(12)
                                .background(.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .padding(20)
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
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await cal.requestAccess() }
        }
    }
}

#Preview {
    CalendarView()
}


