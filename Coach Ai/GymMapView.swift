import SwiftUI
import MapKit

struct GymMapView: View {
    @StateObject private var location = LocationManager.shared
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    @State private var searchText: String = ""
    @State private var showAddGymSheet = false
    @State private var showEditGymSheet = false
    @State private var gymToEdit: Gym? = nil
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var selectedGym: Gym? = nil
    @State private var tappedCoordinate: CLLocationCoordinate2D? = nil
    @State private var showAddByAddressSheet = false
    @State private var addressText: String = ""
    @State private var isGeocoding = false

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
                    VStack(spacing: 20) {
                        // Search Bar for Finding Gyms
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Find Gyms")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.white.opacity(0.6))
                                
                                TextField("Search for gym locations...", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(.white)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onSubmit {
                                        if !searchText.isEmpty {
                                            searchForGyms()
                                        }
                                    }
                                
                                if !searchText.isEmpty {
                                    Button(action: {
                                        withAnimation {
                                            searchText = ""
                                            searchResults = []
                                            isSearching = false
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                
                                if !searchText.isEmpty {
                                    Button(action: {
                                        searchForGyms()
                                    }) {
                                        if isSearching {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "magnifyingglass.circle.fill")
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                            }
                            .padding(16)
                            .background(.white.opacity(0.1))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Map
                        ZStack(alignment: .bottomTrailing) {
                            MapReader { proxy in
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
                                    
                                    // Show search results
                                    ForEach(searchResults, id: \.self) { item in
                                        Marker(item.name ?? "Gym", coordinate: item.placemark.coordinate)
                                            .tint(.orange)
                                    }
                                    
                                    // Show tapped location
                                    if let tapped = tappedCoordinate {
                                        Marker("New Gym Location", coordinate: tapped)
                                            .tint(.green)
                                    }
                                }
                                .mapStyle(.standard)
                                .mapControls {
                                    MapUserLocationButton()
                                }
                                .onMapCameraChange { context in
                                    currentCenter = context.region.center
                                }
                                .onTapGesture { tapLocation in
                                    if let coordinate = proxy.convert(tapLocation, from: .local) {
                                        tappedCoordinate = coordinate
                                        currentCenter = coordinate
                                        showAddGymSheet = true
                                    }
                                }
                            }
                            .frame(height: 300)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            
                            VStack(spacing: 12) {
                                // Add By Address Button
                                Button(action: {
                                    showAddByAddressSheet = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "mappin.and.ellipse")
                                        Text("Add By Address")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.blue, Color.cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(20)
                                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                                }
                                
                                // Hint text
                                Text("Tap map to add gym")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.3))
                                    .cornerRadius(12)
                            }
                            .padding(16)
                        }
                        .padding(.horizontal, 20)
                        
                        // Search Results (if searching)
                        if !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Search Results")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("\(searchResults.count)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 20)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(searchResults, id: \.self) { item in
                                            SearchResultCard(item: item, location: location, cameraPosition: $cameraPosition)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        // My Saved Gyms
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("My Gyms")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            if location.gyms.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "mappin.circle")
                                        .font(.system(size: 60))
                                        .foregroundStyle(.white.opacity(0.3))
                                    Text("No gyms saved yet")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text("Search for gyms above or add one manually")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(location.gyms) { gym in
                                        GymRow(
                                            gym: gym,
                                            location: location,
                                            selectedGym: $selectedGym,
                                            cameraPosition: $cameraPosition,
                                            onTap: {
                                                gymToEdit = gym
                                                showEditGymSheet = true
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .padding(.top, 10)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddGymSheet) {
                AddGymSheet(
                    location: location,
                    isPresented: $showAddGymSheet,
                    currentCenter: tappedCoordinate ?? currentCenter
                )
            }
            .sheet(isPresented: $showEditGymSheet) {
                if let gym = gymToEdit {
                    EditGymSheet(
                        gym: gym,
                        location: location,
                        isPresented: $showEditGymSheet
                    )
                }
            }
            .sheet(isPresented: $showAddByAddressSheet) {
                AddByAddressSheet(
                    addressText: $addressText,
                    isGeocoding: $isGeocoding,
                    isPresented: $showAddByAddressSheet,
                    onAddressFound: { coordinate in
                        tappedCoordinate = coordinate
                        currentCenter = coordinate
                        let region = MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                        cameraPosition = .region(region)
                        showAddGymSheet = true
                    }
                )
            }
            .task {
                // Request location authorization FIRST - before anything else
                location.requestAuthorization()
                
                // Wait a moment for location to be available
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Set initial map position to user location - this is priority
                if let current = location.lastKnownLocation {
                    let newRegion = MKCoordinateRegion(
                        center: current.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    cameraPosition = .region(newRegion)
                    currentCenter = current.coordinate
                } else {
                    // Keep trying to get user location - don't fall back to gyms yet
                    cameraPosition = .automatic
                }
            }
            .onChange(of: location.lastKnownLocation) { oldValue, newValue in
                // Update map when user location becomes available (only if not already set)
                if let newLocation = newValue {
                    // Only update if we're still on automatic or haven't set a location yet
                    if case .automatic = cameraPosition {
                        let newRegion = MKCoordinateRegion(
                            center: newLocation.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
                        cameraPosition = .region(newRegion)
                        currentCenter = newLocation.coordinate
                    }
                }
            }
            .onChange(of: showAddGymSheet) { oldValue, newValue in
                if !newValue {
                    // Clear tapped coordinate when sheet closes
                    tappedCoordinate = nil
                }
            }
        }
    }
    
    private func searchForGyms() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        let request = MKLocalSearch.Request()
        var query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If user searches "gym near me" or similar, use current location
        if query.lowercased().contains("near me") || query.lowercased().contains("nearby") {
            if let current = location.lastKnownLocation {
                request.region = MKCoordinateRegion(
                    center: current.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
                query = query.replacingOccurrences(of: "near me", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "nearby", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Add "gym" or "fitness" if not present
        if !query.lowercased().contains("gym") && !query.lowercased().contains("fitness") {
            request.naturalLanguageQuery = "\(query) gym"
        } else {
            request.naturalLanguageQuery = query
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                isSearching = false
                if let error = error {
                    print("Search error: \(error.localizedDescription)")
                    return
                }
                
                if let response = response {
                    // Filter to gym/fitness related places
                    let gymResults = response.mapItems.filter { item in
                        let name = (item.name ?? "").lowercased()
                        let categories = [
                            "gym", "fitness", "health club", "workout", "exercise",
                            "crossfit", "yoga", "pilates", "martial arts", "boxing",
                            "training", "strength", "cardio", "wellness", "sports"
                        ]
                        // Check if name contains gym-related keywords
                        return categories.contains { name.contains($0) }
                    }
                    
                    searchResults = Array(gymResults.prefix(10)) // Limit to 10 results
                    
                    // Center map on first result if available
                    if let firstResult = searchResults.first {
                        let region = MKCoordinateRegion(
                            center: firstResult.placemark.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                        cameraPosition = .region(region)
                    }
                }
            }
        }
    }
}

struct SearchResultCard: View {
    let item: MKMapItem
    @ObservedObject var location: LocationManager
    @Binding var cameraPosition: MapCameraPosition
    
    var address: String {
        let placemark = item.placemark
        var components: [String] = []
        if let street = placemark.thoroughfare {
            components.append(street)
        }
        if let city = placemark.locality {
            components.append(city)
        }
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        return components.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Gym")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    if !address.isEmpty {
                        Text(address)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }
                
                Spacer()
            }
            
            HStack(spacing: 8) {
                Button(action: {
                    let newRegion = MKCoordinateRegion(
                        center: item.placemark.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    cameraPosition = .region(newRegion)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "map")
                        Text("Show")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Button(action: {
                    location.addGym(
                        name: item.name ?? "Gym",
                        coordinate: item.placemark.coordinate,
                        radius: 500
                    )
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(.white.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}

struct GymRow: View {
    let gym: Gym
    @ObservedObject var location: LocationManager
    @Binding var selectedGym: Gym?
    @Binding var cameraPosition: MapCameraPosition
    var onTap: () -> Void
    
    var isActiveWorkout: Bool {
        location.activeWorkouts[gym.id] != nil
    }
    
    var currentWorkoutTime: TimeInterval? {
        guard let startTime = location.activeWorkouts[gym.id] else { return nil }
        return Date().timeIntervalSince(startTime)
    }
    
    var totalTimeString: String {
        let baseTime = gym.effectiveTotalTime
        let totalSeconds = baseTime + (currentWorkoutTime ?? 0)
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var body: some View {
        Button(action: {
            onTap()
        }) {
            HStack(spacing: 16) {
                Image(systemName: isActiveWorkout ? "figure.run.circle.fill" : "mappin.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        isActiveWorkout ?
                        LinearGradient(
                            colors: [Color.green, Color.mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [Color.purple, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(gym.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        if isActiveWorkout {
                            Text("• Active")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Text("\(Int(gym.effectiveRadius))ft radius")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                            Text(totalTimeString)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        isActiveWorkout ? Color.green.opacity(0.1) : Color.white.opacity(0.1),
                        isActiveWorkout ? Color.mint.opacity(0.05) : Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActiveWorkout ? Color.green.opacity(0.3) : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AddGymSheet: View {
    @ObservedObject var location: LocationManager
    @Binding var isPresented: Bool
    let currentCenter: CLLocationCoordinate2D
    @State private var gymName: String = ""
    @State private var radius: Double = 500 // in feet
    
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
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gym Name")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            TextField("Enter gym name...", text: $gymName)
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
                            Text("Detection Radius")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            Text("\(Int(radius)) feet")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Slider(value: $radius, in: 250...1000, step: 25)
                                .tint(.purple)
                            
                            HStack {
                                Text("250 ft")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text("1000 ft")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                            Text("The app will detect when you enter this radius around the gym")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Location")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            Map(position: .constant(.region(MKCoordinateRegion(
                                center: currentCenter,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )))) {
                                Marker("Gym Location", coordinate: currentCenter)
                                    .tint(.purple)
                                
                                // Radius circle overlay
                                MapCircle(center: currentCenter, radius: radius * 0.3048) // Convert feet to meters
                                    .foregroundStyle(.purple.opacity(0.2))
                                    .stroke(.purple.opacity(0.6), lineWidth: 2)
                            }
                            .mapStyle(.standard)
                            .frame(height: 200)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            
                            Text(String(format: "%.4f, %.4f", currentCenter.latitude, currentCenter.longitude))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            let name = gymName.trimmingCharacters(in: .whitespacesAndNewlines)
                            location.addGym(name: name.isEmpty ? "My Gym" : name, coordinate: currentCenter, radius: radius)
                            isPresented = false
                        }) {
                            Text("Add Gym")
                                .font(.system(size: 16, weight: .semibold))
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
                        .disabled(gymName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Gym")
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

extension LocationManager {
    fileprivate var gymAnnotationItems: [GymAnnotationItem] {
        gyms.map { GymAnnotationItem(coordinate: $0.coordinate) }
    }
}

struct GymAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct EditGymSheet: View {
    let gym: Gym
    @ObservedObject var location: LocationManager
    @Binding var isPresented: Bool
    @State private var gymName: String
    @State private var radius: Double
    @State private var newCoordinate: CLLocationCoordinate2D
    @State private var cameraPosition: MapCameraPosition
    @State private var showDeleteConfirmation = false
    
    init(gym: Gym, location: LocationManager, isPresented: Binding<Bool>) {
        self.gym = gym
        self.location = location
        _isPresented = isPresented
        _gymName = State(initialValue: gym.name)
        _radius = State(initialValue: gym.effectiveRadius)
        _newCoordinate = State(initialValue: gym.coordinate)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: gym.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
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
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gym Name")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            TextField("Enter gym name...", text: $gymName)
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
                            Text("Detection Radius")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            Text("\(Int(radius)) feet")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Slider(value: $radius, in: 250...1000, step: 25)
                                .tint(.purple)
                            
                            HStack {
                                Text("250 ft")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text("1000 ft")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                            Text("The app will detect when you enter this radius around the gym")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Location")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            Map(position: $cameraPosition) {
                                Marker("Gym Location", coordinate: gym.coordinate)
                                    .tint(.purple)
                                
                                // Radius circle overlay - updates as slider changes
                                MapCircle(center: gym.coordinate, radius: radius * 0.3048) // Convert feet to meters
                                    .foregroundStyle(.purple.opacity(0.2))
                                    .stroke(.purple.opacity(0.6), lineWidth: 2)
                            }
                            .mapStyle(.standard)
                            .onMapCameraChange { context in
                                // Don't update the gym coordinate when camera moves
                                // Only update if user explicitly moves it
                            }
                            .frame(height: 200)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            
                            Text(String(format: "%.4f, %.4f", gym.coordinate.latitude, gym.coordinate.longitude))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                            
                            Text("Gym location is fixed. Use the main map to change location.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        
                        // Stats
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Stats")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Time")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text(formatTime(gym.effectiveTotalTime))
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Radius")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text("\(Int(gym.effectiveRadius))ft")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(16)
                            .background(.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        Spacer()
                        
                        // Save Button
                        Button(action: {
                            location.updateGym(gym, name: gymName, coordinate: newCoordinate, radius: radius)
                            isPresented = false
                        }) {
                            Text("Save Changes")
                                .font(.system(size: 16, weight: .semibold))
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
                        .disabled(gymName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        // Delete Button
                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            Text("Delete Gym")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(.red.opacity(0.3))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.red.opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
            .alert("Delete Gym", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    location.removeGym(gym)
                    isPresented = false
                }
            } message: {
                Text("Are you sure you want to delete \(gym.name)? This action cannot be undone.")
            }
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval / 3600)
        let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct AddByAddressSheet: View {
    @Binding var addressText: String
    @Binding var isGeocoding: Bool
    @Binding var isPresented: Bool
    let onAddressFound: (CLLocationCoordinate2D) -> Void
    @State private var errorMessage: String? = nil
    
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
                        Text("Enter Address")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        TextField("e.g., 123 Main St, City, State", text: $addressText)
                            .textFieldStyle(.plain)
                            .padding(16)
                            .background(.white.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                            .onSubmit {
                                geocodeAddress()
                            }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        geocodeAddress()
                    }) {
                        Group {
                            if isGeocoding {
                                HStack {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Searching...")
                                }
                            } else {
                                Text("Find Address")
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .disabled(addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeocoding)
                }
                .padding(20)
            }
            .navigationTitle("Add By Address")
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
    
    private func geocodeAddress() {
        guard !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isGeocoding = true
        errorMessage = nil
        
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(addressText) { placemarks, error in
            DispatchQueue.main.async {
                isGeocoding = false
                
                if let error = error {
                    errorMessage = "Could not find address: \(error.localizedDescription)"
                    return
                }
                
                guard let placemark = placemarks?.first,
                      let coordinate = placemark.location?.coordinate else {
                    errorMessage = "Could not find location for this address"
                    return
                }
                
                onAddressFound(coordinate)
                isPresented = false
                addressText = ""
            }
        }
    }
}

#Preview {
    GymMapView()
}
