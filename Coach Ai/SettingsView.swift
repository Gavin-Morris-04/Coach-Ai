import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var showSignOutAlert = false
    
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
                        // User Info Section
                        if let user = firebase.currentUser {
                            VStack(spacing: 16) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.white.opacity(0.7))
                                
                                Text(user.name)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                if let email = Auth.auth().currentUser?.email {
                                    Text(email)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(.white.opacity(0.05))
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }
                        
                        // Profile Details
                        if let user = firebase.currentUser {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Profile Information")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                
                                if let height = user.height {
                                    ProfileInfoRow(
                                        icon: "ruler",
                                        title: "Height",
                                        value: formatHeight(height)
                                    )
                                }
                                
                                if let weight = user.weight {
                                    ProfileInfoRow(
                                        icon: "scalemass",
                                        title: "Weight",
                                        value: formatWeight(weight)
                                    )
                                }
                                
                                if let gender = user.gender {
                                    ProfileInfoRow(
                                        icon: "person.fill",
                                        title: "Gender",
                                        value: gender.capitalized
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Sign Out Button
                        Button(action: {
                            showSignOutAlert = true
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Sign Out")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(.white.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Are you sure you want to sign out? All your data will remain saved.")
            }
        }
    }
    
    private func formatHeight(_ meters: Double) -> String {
        let totalInches = Int(meters / 0.0254)
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)' \(inches)\""
    }
    
    private func formatWeight(_ kg: Double) -> String {
        let pounds = kg * 2.20462
        return String(format: "%.1f lbs", pounds)
    }
    
    private func signOut() {
        do {
            try firebase.signOut()
        } catch {
            print("Error signing out: \(error)")
        }
    }
}

struct ProfileInfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(.white.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}

