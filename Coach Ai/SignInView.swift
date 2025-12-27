import SwiftUI
import HealthKit
import FirebaseAuth

struct SignInView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var isSignUp = false
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var name: String = ""
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 10
    @State private var weightPounds: Double = 150
    @State private var selectedGender: String = "Not Set"
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    
    let genderOptions = ["Not Set", "Male", "Female", "Other"]
    
    var body: some View {
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
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text(isSignUp ? "Create Account" : "Welcome Back")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text(isSignUp ? "Sign up to get started" : "Sign in to continue")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // Email Input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Email")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(.plain)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
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
                    
                    // Password Input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Password")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        SecureField("Enter your password", text: $password)
                            .textFieldStyle(.plain)
                            .textContentType(.none)
                            .autocorrectionDisabled()
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
                    
                    // Confirm Password (only for sign up)
                    if isSignUp {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Confirm Password")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            SecureField("Confirm your password", text: $confirmPassword)
                                .textFieldStyle(.plain)
                                .textContentType(.none)
                                .autocorrectionDisabled()
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
                    }
                    
                    // Profile Fields (only for sign up)
                    if isSignUp {
                        // Name Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Name")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            TextField("Enter your name", text: $name)
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
                        
                        // Height Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Height")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            HStack(spacing: 16) {
                                VStack(alignment: .leading) {
                                    Text("Feet")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.7))
                                    Picker("Feet", selection: $heightFeet) {
                                        ForEach(3...8, id: \.self) { feet in
                                            Text("\(feet)").tag(feet)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(.white.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("Inches")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.7))
                                    Picker("Inches", selection: $heightInches) {
                                        ForEach(0..<12, id: \.self) { inches in
                                            Text("\(inches)").tag(inches)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(.white.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Weight Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Weight (lbs)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            HStack {
                                TextField("Weight", value: $weightPounds, format: .number)
                                    .textFieldStyle(.plain)
                                    .keyboardType(.decimalPad)
                                    .padding(16)
                                    .background(.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .foregroundStyle(.white)
                                
                                Text("lbs")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Gender Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gender")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            Picker("Gender", selection: $selectedGender) {
                                ForEach(genderOptions, id: \.self) { gender in
                                    Text(gender).tag(gender)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(12)
                            .background(.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Sign In/Up Button
                    Button(action: {
                        if isSignUp {
                            signUp()
                        } else {
                            signIn()
                        }
                    }) {
                        HStack {
                            if isSigningIn {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isSignUp ? "Sign Up" : "Sign In")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
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
                    .disabled(isSigningIn)
                    .padding(.horizontal, 20)
                    
                    // Toggle Sign In/Sign Up
                    Button(action: {
                        withAnimation {
                            isSignUp.toggle()
                            errorMessage = nil
                            password = ""
                            confirmPassword = ""
                        }
                    }) {
                        HStack {
                            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(isSignUp ? "Sign In" : "Sign Up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    private var isValidInput: Bool {
        if email.isEmpty || password.isEmpty {
            return false
        }
        if isSignUp {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            if password != confirmPassword {
                return false
            }
            if password.count < 6 {
                return false
            }
        }
        return true
    }
    
    private func signIn() {
        // Validate input and show specific error messages
        if email.isEmpty {
            errorMessage = "Please enter your email address."
            return
        }
        if password.isEmpty {
            errorMessage = "Please enter your password."
            return
        }
        
        isSigningIn = true
        errorMessage = nil
        
        Task {
            do {
                try await firebase.signInWithEmail(email, password: password)
                
                // Load user profile data if available
                if let user = firebase.currentUser {
                    await MainActor.run {
                        if let height = user.height {
                            HealthKitManager.shared.height = height
                        }
                        if let weight = user.weight {
                            HealthKitManager.shared.weight = weight
                        }
                        if let gender = user.gender {
                            switch gender.lowercased() {
                            case "male":
                                HealthKitManager.shared.biologicalSex = .male
                            case "female":
                                HealthKitManager.shared.biologicalSex = .female
                            default:
                                HealthKitManager.shared.biologicalSex = .other
                            }
                        }
                    }
                }
                
                await MainActor.run {
                    isSigningIn = false
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    let nsError = error as NSError
                    if nsError.domain == "FIRAuthErrorDomain" {
                        switch nsError.code {
                        case 17007: // Email already in use
                            errorMessage = "This email is already registered. Please sign in instead."
                        case 17008: // Invalid email
                            errorMessage = "Please enter a valid email address."
                        case 17026: // Weak password
                            errorMessage = "Password should be at least 6 characters long."
                        default:
                            errorMessage = "Sign in failed: \(error.localizedDescription)"
                        }
                    } else {
                        errorMessage = "Sign in failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func signUp() {
        // Validate input and show specific error messages
        if email.isEmpty {
            errorMessage = "Please enter your email address."
            return
        }
        if password.isEmpty {
            errorMessage = "Please enter a password."
            return
        }
        if isSignUp {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Please enter your name."
                return
            }
            if password != confirmPassword {
                errorMessage = "Passwords do not match."
                return
            }
            if password.count < 6 {
                errorMessage = "Password must be at least 6 characters long."
                return
            }
        }
        
        isSigningIn = true
        errorMessage = nil
        
        Task {
            do {
                // Convert height to meters
                let totalInches = Double(heightFeet * 12 + heightInches)
                let heightInMeters = totalInches * 0.0254
                
                // Convert weight to kg
                let weightInKg = weightPounds * 0.453592
                
                // Convert gender string
                let genderString: String?
                switch selectedGender {
                case "Male": genderString = "male"
                case "Female": genderString = "female"
                case "Other": genderString = "other"
                default: genderString = nil
                }
                
                // Sign up with email and password
                print("Attempting to sign up with email: \(email)")
                try await firebase.signUpWithEmail(
                    email,
                    password: password,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                print("Sign up successful!")
                
                // Update user profile with additional info
                try await firebase.updateUserProfile(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    height: heightInMeters,
                    weight: weightInKg,
                    gender: genderString
                )
                
                // Save to UserDefaults for local access
                UserDefaults.standard.set(heightInMeters, forKey: "user.height")
                UserDefaults.standard.set(weightInKg, forKey: "user.weight")
                UserDefaults.standard.set(genderString ?? "", forKey: "user.gender")
                UserDefaults.standard.set(name, forKey: "user.name")
                
                // Update HealthKitManager with user profile
                await MainActor.run {
                    HealthKitManager.shared.height = heightInMeters
                    HealthKitManager.shared.weight = weightInKg
                    if let gender = genderString {
                        switch gender.lowercased() {
                        case "male":
                            HealthKitManager.shared.biologicalSex = .male
                        case "female":
                            HealthKitManager.shared.biologicalSex = .female
                        default:
                            HealthKitManager.shared.biologicalSex = .other
                        }
                    }
                }
                
                await MainActor.run {
                    isSigningIn = false
                }
            } catch {
                print("Sign up error: \(error)")
                await MainActor.run {
                    isSigningIn = false
                    let nsError = error as NSError
                    print("Error domain: \(nsError.domain), code: \(nsError.code)")
                    // Check for Firebase Auth errors
                    if nsError.domain == "FIRAuthErrorDomain" {
                        switch nsError.code {
                        case 17007: // Email already in use
                            errorMessage = "This email is already registered. Please sign in instead or use a different email address."
                        case 17008: // Invalid email
                            errorMessage = "Please enter a valid email address."
                        case 17026: // Weak password
                            errorMessage = "Password should be at least 6 characters long."
                        default:
                            errorMessage = "Sign up failed: \(error.localizedDescription)"
                        }
                    } else {
                        errorMessage = "Sign up failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
