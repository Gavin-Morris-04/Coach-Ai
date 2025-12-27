import Foundation
import UIKit
import CoreLocation
import HealthKit
import UserNotifications
import EventKit

struct Gym: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double? // in feet (250-1000), optional for backward compatibility
    var totalTime: TimeInterval? // total time spent at gym in seconds, optional for backward compatibility
    
    // Computed properties with defaults
    var effectiveRadius: Double {
        radius ?? 500 // Default 500 feet
    }
    
    // Convert feet to meters for CoreLocation (which uses meters)
    var radiusInMeters: Double {
        effectiveRadius * 0.3048 // 1 foot = 0.3048 meters
    }
    
    var effectiveTotalTime: TimeInterval {
        totalTime ?? 0
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D, radius: Double = 500, totalTime: TimeInterval = 0) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.radius = radius
        self.totalTime = totalTime
    }
    
    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, radius: Double = 500, totalTime: TimeInterval = 0) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.totalTime = totalTime
    }
    
    // Migrate old gyms to have radius and totalTime (convert meters to feet if needed)
    mutating func migrateIfNeeded() {
        if radius == nil {
            radius = 500 // Default 500 feet
        } else if radius! < 100 {
            // If radius is less than 100, assume it's in meters and convert to feet
            radius = radius! * 3.28084
        }
        if totalTime == nil {
            totalTime = 0
        }
    }
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()

    @Published var lastKnownLocation: CLLocation?
    @Published var gyms: [Gym] = [] { didSet { persistGyms(); syncGymsToFirebase() } }
    
    // Active workout sessions: gymId -> startTime
    @Published var activeWorkouts: [UUID: Date] = [:]
    
    // Pending gym workout - triggers workout selection sheet
    @Published var pendingGymWorkout: UUID? = nil
    
    private var isSyncingGyms = false
    
    // Legacy support - returns first gym or nil
    var gymCoordinate: CLLocationCoordinate2D? {
        gyms.first?.coordinate
    }

    private let gymsKey = "gyms.list.v3"
    private let gymKey = "gym.coordinate.v1" // Legacy
    private let workoutsKey = "active.workouts.v1"

    var authorizationStatusText: String? {
        switch manager.authorizationStatus {
        case .notDetermined: return "Location permission: Not determined"
        case .restricted: return "Location permission: Restricted"
        case .denied: return "Location permission: Denied"
        case .authorizedAlways: return "Location permission: Always"
        case .authorizedWhenInUse: return "Location permission: When in use"
        @unknown default: return nil
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Start with empty gyms - only load after Firebase authentication
        gyms = []
        Task {
            await loadGymsFromFirebase()
        }
        loadActiveWorkouts()
        
        // Start a timer to periodically update total time for active workouts
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateActiveWorkoutTimes()
        }
    }
    
    private func updateActiveWorkoutTimes() {
        // This is called every minute to keep the UI updated
        // Actual time tracking happens when exiting the region
        // We just need to persist the gyms to save any updates
        persistGyms()
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func addGym(name: String, coordinate: CLLocationCoordinate2D, radius: Double = 150) {
        let gym = Gym(name: name, coordinate: coordinate, radius: radius)
        gyms.append(gym)
        startMonitoringGymRegions()
    }
    
    func removeGym(_ gym: Gym) {
        gyms.removeAll { $0.id == gym.id }
        startMonitoringGymRegions()
    }
    
    func updateGym(_ gym: Gym, name: String? = nil, coordinate: CLLocationCoordinate2D? = nil, radius: Double? = nil) {
        guard let index = gyms.firstIndex(where: { $0.id == gym.id }) else { return }
        if let name = name {
            gyms[index].name = name
        }
        if let coordinate = coordinate {
            gyms[index].latitude = coordinate.latitude
            gyms[index].longitude = coordinate.longitude
        }
        if let radius = radius {
            gyms[index].radius = radius
        }
        startMonitoringGymRegions()
    }
    
    // Legacy support
    func setGymCoordinate(_ coord: CLLocationCoordinate2D) {
        if gyms.isEmpty {
            addGym(name: "My Gym", coordinate: coord)
        } else {
            gyms[0].latitude = coord.latitude
            gyms[0].longitude = coord.longitude
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            self.manager.startUpdatingLocation()
            startMonitoringGymRegions()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            Task { @MainActor in
                ErrorManager.shared.showErrorMessage(
                    "Location access is required for gym tracking. Please enable location permissions in Settings > Privacy & Security > Location Services.",
                    title: "Location Access Required"
                )
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let gym = gyms.first(where: { $0.id.uuidString == region.identifier }) else { return }
        
        // Check if already in a workout at this gym
        guard activeWorkouts[gym.id] == nil else { return }
        
        // Send notification asking if they want to start a workout
        Task {
            await NotificationsManager.shared.scheduleGymEntryNotification(
                gymName: gym.name,
                gymId: gym.id.uuidString
            )
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let gym = gyms.first(where: { $0.id.uuidString == region.identifier }),
              let startTime = activeWorkouts[gym.id] else { return }
        
        // Calculate time spent
        let timeSpent = Date().timeIntervalSince(startTime)
        
        // Update gym's total time
        if let index = gyms.firstIndex(where: { $0.id == gym.id }) {
            let currentTotal = gyms[index].effectiveTotalTime
            gyms[index].totalTime = currentTotal + timeSpent
        }
        
        // Stop the workout
        activeWorkouts.removeValue(forKey: gym.id)
        persistActiveWorkouts()
        
        // Format time for message
        let minutes = Int(timeSpent / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        var timeString = ""
        if hours > 0 {
            timeString = "\(hours)h \(remainingMinutes)m"
        } else {
            timeString = "\(minutes)m"
        }
        
        // Send exit notification
        Task {
            await NotificationsManager.shared.scheduleCoachImmediate(
                body: "Workout timer stopped at \(gym.name)! You spent \(timeString) there. Hope you killed it today! 💪"
            )
        }
    }
    
    func startWorkout(at gymId: UUID, splitId: UUID? = nil, dayId: UUID? = nil) {
        guard let gym = gyms.first(where: { $0.id == gymId }) else { return }
        activeWorkouts[gymId] = Date()
        persistActiveWorkouts()
        
        // Clear pending workout
        pendingGymWorkout = nil
        
        // Add calendar event for workout
        var eventTitle = "You worked out at \(gym.name)"
        if let splitId = splitId, let split = WorkoutSplitStore.shared.splits.first(where: { $0.id == splitId }),
           let dayId = dayId, let day = split.days.first(where: { $0.id == dayId }) {
            eventTitle = "You worked out at \(gym.name) - \(split.name) - \(day.dayOfWeek)"
        }
        
        Task {
            await CalendarManager.shared.addEvent(
                title: eventTitle,
                date: Date()
            )
        }
    }
    
    func cancelWorkout(at gymId: UUID) {
        activeWorkouts.removeValue(forKey: gymId)
        persistActiveWorkouts()
    }
    
    private func persistActiveWorkouts() {
        let dict = activeWorkouts.mapValues { $0.timeIntervalSince1970 }
        var stringDict: [String: TimeInterval] = [:]
        for (key, value) in dict {
            stringDict[key.uuidString] = value
        }
        UserDefaults.standard.set(stringDict, forKey: workoutsKey)
    }
    
    private func loadActiveWorkouts() {
        guard let dict = UserDefaults.standard.dictionary(forKey: workoutsKey) as? [String: TimeInterval] else { return }
        var workouts: [UUID: Date] = [:]
        for (key, value) in dict {
            if let uuid = UUID(uuidString: key) {
                workouts[uuid] = Date(timeIntervalSince1970: value)
            }
        }
        activeWorkouts = workouts
    }

    private func startMonitoringGymRegions() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        // Stop monitoring old regions
        manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
        // Start monitoring all gyms with their custom radius (convert feet to meters for CoreLocation)
        for gym in gyms {
            let region = CLCircularRegion(center: gym.coordinate, radius: gym.radiusInMeters, identifier: gym.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func persistGyms() {
        if let data = try? JSONEncoder().encode(gyms) {
            UserDefaults.standard.set(data, forKey: gymsKey)
        }
    }
    
    private func syncGymsToFirebase() {
        guard !isSyncingGyms, FirebaseService.shared.isAuthenticated else { return }
        isSyncingGyms = true
        Task {
            do {
                try await FirebaseService.shared.syncGyms(gyms)
                await MainActor.run {
                    isSyncingGyms = false
                }
            } catch {
                print("Error syncing gyms to Firebase: \(error)")
                await MainActor.run {
                    isSyncingGyms = false
                    ErrorManager.shared.showErrorMessage(
                        "Failed to sync gym data to cloud. Your changes are saved locally and will sync when connection is restored.",
                        title: "Sync Error"
                    )
                }
            }
        }
    }
    
    func loadGymsFromFirebase() async {
        guard FirebaseService.shared.isAuthenticated else {
            await MainActor.run {
                self.gyms = []
            }
            return
        }
        do {
            let firebaseGyms = try await FirebaseService.shared.loadGyms()
            await MainActor.run {
                if !firebaseGyms.isEmpty {
                    // Merge Firebase gyms with local gyms to preserve maximum totalTime
                    // This ensures time accumulates correctly across multiple visits
                    var mergedGyms: [Gym] = []
                    
                    // Start with Firebase gyms as base
                    for firebaseGym in firebaseGyms {
                        // Check if we have a local version of this gym
                        if let localGym = self.gyms.first(where: { $0.id == firebaseGym.id }) {
                            // Merge: use the maximum totalTime to ensure we never lose accumulated time
                            var mergedGym = firebaseGym
                            let localTime = localGym.effectiveTotalTime
                            let firebaseTime = firebaseGym.effectiveTotalTime
                            mergedGym.totalTime = max(localTime, firebaseTime)
                            mergedGyms.append(mergedGym)
                        } else {
                            // New gym from Firebase
                            mergedGyms.append(firebaseGym)
                        }
                    }
                    
                    // Add any local gyms that aren't in Firebase (shouldn't happen, but safety)
                    for localGym in self.gyms {
                        if !mergedGyms.contains(where: { $0.id == localGym.id }) {
                            mergedGyms.append(localGym)
                        }
                    }
                    
                    self.gyms = mergedGyms
                    self.startMonitoringGymRegions()
                    
                    // Sync back to Firebase with merged data to ensure consistency
                    self.syncGymsToFirebase()
                } else {
                    // If Firebase is empty, keep local gyms (they'll sync on next change)
                    // Only clear if we have no local gyms either
                    if self.gyms.isEmpty {
                        self.gyms = []
                    }
                }
            }
        } catch {
            print("Error loading gyms from Firebase: \(error)")
            await MainActor.run {
                ErrorManager.shared.showErrorMessage(
                    "Failed to load gym data from cloud. Using local data. Changes will sync when connection is restored.",
                    title: "Connection Error"
                )
            }
        }
    }

    private func loadGyms() {
        // Try loading new format first
        if let data = UserDefaults.standard.data(forKey: gymsKey),
           var decoded = try? JSONDecoder().decode([Gym].self, from: data) {
            // Migrate old gyms
            for i in 0..<decoded.count {
                decoded[i].migrateIfNeeded()
            }
            gyms = decoded
            startMonitoringGymRegions()
            return
        }
        
        // Fallback to legacy format
        if let dict = UserDefaults.standard.dictionary(forKey: gymKey) as? [String: Double],
           let lat = dict["lat"], let lon = dict["lon"] {
            let gym = Gym(name: "My Gym", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), radius: 150, totalTime: 0)
            gyms = [gym]
            startMonitoringGymRegions()
        }
    }
}

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()

    @Published var todaySteps: Int = 0
    @Published var todayActiveEnergy: Double = 0
    @Published var activeHeartRate: Double = 0 // Current/active heart rate (bpm)
    @Published var averageHeartRate: Double = 0 // Average heart rate for today (bpm)
    @Published var height: Double = 0 // in meters
    @Published var weight: Double = 0 // in kilograms
    @Published var biologicalSex: HKBiologicalSex = .notSet

    func ensureAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let toRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        ]
        do {
            try await healthStore.requestAuthorization(toShare: [], read: toRead)
            await refreshToday()
            await refreshProfile()
        } catch {
            await MainActor.run {
                ErrorManager.shared.showErrorMessage(
                    "Failed to request HealthKit permissions. Please enable Health access in Settings > Privacy & Security > Health.",
                    title: "Health Data Access"
                )
            }
        }
    }

    @MainActor
    func refreshToday() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodaySteps() }
            group.addTask { await self.fetchTodayActiveEnergy() }
            group.addTask { await self.fetchHeartRate() }
        }
    }
    
    @MainActor
    func refreshProfile() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchHeight() }
            group.addTask { await self.fetchWeight() }
            group.addTask { await self.fetchBiologicalSex() }
        }
    }

    private func fetchTodaySteps() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
            let value = stats?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
            Task { @MainActor [weak self] in
                self?.todaySteps = Int(value)
            }
        }
        healthStore.execute(query)
    }

    private func fetchTodayActiveEnergy() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
            let value = stats?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
            Task { @MainActor [weak self] in
                self?.todayActiveEnergy = value
            }
        }
        healthStore.execute(query)
    }
    
    private func fetchHeartRate() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
        
        // Fetch most recent heart rate (active)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            if let sample = samples?.first as? HKQuantitySample {
                let value = sample.quantity.doubleValue(for: heartRateUnit)
                Task { @MainActor [weak self] in
                    self?.activeHeartRate = value
                }
            }
        }
        healthStore.execute(query)
        
        // Fetch average heart rate for today
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let avgQuery = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
            let value = stats?.averageQuantity()?.doubleValue(for: heartRateUnit) ?? 0
            Task { @MainActor [weak self] in
                self?.averageHeartRate = value
            }
        }
        healthStore.execute(avgQuery)
    }
    
    private func fetchHeight() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .height) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            if let sample = samples?.first as? HKQuantitySample {
                let value = sample.quantity.doubleValue(for: HKUnit.meter())
                Task { @MainActor [weak self] in
                    self?.height = value
                }
            }
        }
        healthStore.execute(query)
    }
    
    private func fetchWeight() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            if let sample = samples?.first as? HKQuantitySample {
                let value = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                Task { @MainActor [weak self] in
                    self?.weight = value
                }
            }
        }
        healthStore.execute(query)
    }
    
    private func fetchBiologicalSex() async {
        do {
            let sex = try healthStore.biologicalSex()
            Task { @MainActor [weak self] in
                self?.biologicalSex = sex.biologicalSex
            }
        } catch {
            // no-op
        }
    }
}

final class NotificationsManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            center.delegate = self
        } catch {
            // no-op
        }
    }

    func scheduleCoachImmediate(body: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Coach"
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }
    
    func scheduleGymEntryNotification(gymName: String, gymId: String) async {
        let content = UNMutableNotificationContent()
        content.title = "🏋️ You're at \(gymName)!"
        content.body = "Are you starting a workout?"
        content.sound = .default
        content.categoryIdentifier = "GYM_ENTRY"
        content.userInfo = ["gymId": gymId]
        
        // Add action buttons
        let startAction = UNNotificationAction(
            identifier: "START_WORKOUT",
            title: "Yes, Start Workout",
            options: []
        )
        let cancelAction = UNNotificationAction(
            identifier: "CANCEL_WORKOUT",
            title: "Not Now",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "GYM_ENTRY",
            actions: [startAction, cancelAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        
        // Delay notification by 1 minute (60 seconds) - user requested within 1 minute
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let request = UNNotificationRequest(identifier: "gym_entry_\(gymId)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func scheduleCoachReminder(body: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Coach Reminder"
        content.body = body
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // Present notifications while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    
    // Handle notification actions
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == "GYM_ENTRY" {
            guard let gymIdString = response.notification.request.content.userInfo["gymId"] as? String,
                  let gymId = UUID(uuidString: gymIdString) else {
                completionHandler()
                return
            }
            
            if response.actionIdentifier == "START_WORKOUT" {
                // Set pending workout to trigger workout selection sheet
                LocationManager.shared.pendingGymWorkout = gymId
            } else if response.actionIdentifier == "CANCEL_WORKOUT" {
                LocationManager.shared.cancelWorkout(at: gymId)
            }
        }
        completionHandler()
    }
}


