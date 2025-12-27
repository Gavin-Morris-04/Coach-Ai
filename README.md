
### Why MVVM?
- Predictable state updates
- Testable business logic
- Reactive UI using Combine
- Clear boundaries between UI and data systems

---

## 🧩 Technology Stack

### Frontend
- **SwiftUI**
- **Swift 5+**
- Combine (reactive state management)

### Backend & Cloud
- **Firebase Authentication**
- **Firebase Firestore**
- **Groq API** (LLM inference)

### Native iOS Frameworks
- HealthKit
- CoreLocation
- EventKit
- UserNotifications
- MapKit

### Data Persistence
- UserDefaults (local caching)
- Firestore (cloud sync)
- HealthKit (secure health storage)

---

## 🔄 Data Synchronization Strategy

Coach AI uses a **dual-layer persistence model**:

### Local Layer
- Immediate writes to `UserDefaults`
- Enables offline access
- Fast UI responsiveness

### Cloud Layer
- Background sync to Firestore
- Cross-device consistency
- Secure user isolation

### Conflict Resolution
- Firebase data takes priority on load
- Local changes always persisted first
- Gym time tracking resolves by taking the maximum accumulated time
- Workout splits merged by ID to avoid duplication

---

## 🔐 Security & Privacy

- Firebase Authentication handles password hashing and session management
- Firestore security rules enforce strict user data isolation
- HealthKit data **never leaves the device**
- Location data used only for gym detection
- All network traffic encrypted (HTTPS)
- Sensitive keys excluded from version control

---

## ⚠️ Error Handling

- Centralized error manager for:
  - Firebase sync failures
  - HealthKit permission issues
  - Location permission errors
  - Calendar access issues
  - API rate limits and network errors
- Non-blocking user alerts with recovery guidance
- Automatic retry logic for recoverable failures

---

## 📁 Project Structure

CoachAI/
├── CoachAIApp.swift
├── ContentView.swift
├── HomeView.swift
├── CoachView.swift
├── FitnessView.swift
├── CaloriesView.swift
├── TodoListView.swift
├── CalendarView.swift
├── GymMapView.swift
├── SignInView.swift
├── SettingsView.swift
├── Services/
│ ├── FirebaseService.swift
│ ├── GroqService.swift
│ └── ErrorManager.swift
├── Managers/
│ ├── HealthKitManager.swift
│ ├── LocationManager.swift
│ └── CalendarManager.swift
├── Models/
├── Stores/
└── Assets.xcassets/


---

## 🧪 Testing Considerations

- Unit testing for:
  - Data stores
  - AI response parsing
  - Sync conflict resolution
- Integration testing for:
  - Firebase sync
  - HealthKit queries
  - Geofencing workflows
- UI testing for:
  - Navigation
  - Error handling
  - Persistence across launches

---

## 🛠️ Setup Instructions

### Prerequisites
- macOS
- Xcode 15+
- iOS 17+ device or simulator
- Firebase project
- Groq API key

### Setup
1. Clone the repository
2. Open the `.xcodeproj` in Xcode
3. Configure Firebase (`GoogleService-Info.plist`)
4. Add Groq API key to local config (not committed)
5. Enable HealthKit, Location, and Calendar permissions
6. Build and run

---

## 🔮 Future Improvements

- Advanced analytics and progress visualization
- Voice-based AI interaction
- Meal planning and barcode scanning
- Social features and challenges
- Offline-first sync UI indicators
- Accessibility enhancements

---

## 📌 Why This Project Matters

Coach AI demonstrates:
- Real-world AI integration (not just demos)
- System-level thinking and architecture
- Secure, scalable cloud-backed mobile development
- Applied machine learning in consumer software
- Strong understanding of native iOS frameworks

This project was built to reflect **production-quality engineering decisions** and to serve as a foundation for continued expansion.

---

## 👤 Author

**Gavin Morris**  
Computer Science (Software Engineering)  
Louisiana State University  

🔗 Portfolio: https://gavinmorrisportfolio.com  
🔗 LinkedIn: https://www.linkedin.com/in/gmorr32  

---
