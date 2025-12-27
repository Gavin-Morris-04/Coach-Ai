import SwiftUI
import HealthKit

struct ProfileEditorSheet: View {
    @ObservedObject var health: HealthKitManager
    @Binding var isPresented: Bool
    
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 10
    @State private var weightPounds: Double = 150
    @State private var selectedGender: HKBiologicalSex = .notSet
    
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
                        // Height
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Height")
                                .font(.system(size: 18, weight: .semibold))
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
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Weight
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Weight")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            HStack {
                                TextField("Weight in pounds", value: $weightPounds, format: .number)
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
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        // Gender
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gender")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            Picker("Gender", selection: $selectedGender) {
                                Text("Not Set").tag(HKBiologicalSex.notSet)
                                Text("Male").tag(HKBiologicalSex.male)
                                Text("Female").tag(HKBiologicalSex.female)
                                Text("Other").tag(HKBiologicalSex.other)
                            }
                            .pickerStyle(.segmented)
                            .padding(12)
                            .background(.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        Button(action: {
                            // Save to UserDefaults (HealthKit is read-only)
                            let totalInches = Double(heightFeet * 12 + heightInches)
                            let heightInMeters = totalInches * 0.0254
                            let weightInKg = weightPounds * 0.453592
                            
                            UserDefaults.standard.set(heightInMeters, forKey: "user.height")
                            UserDefaults.standard.set(weightInKg, forKey: "user.weight")
                            UserDefaults.standard.set(selectedGender.rawValue, forKey: "user.gender")
                            
                            isPresented = false
                        }) {
                            Text("Save")
                                .font(.system(size: 18, weight: .semibold))
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
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                // Load current values
                if health.height > 0 {
                    let totalInches = health.height * 39.3701
                    heightFeet = Int(totalInches / 12)
                    heightInches = Int(totalInches.truncatingRemainder(dividingBy: 12))
                }
                if health.weight > 0 {
                    weightPounds = health.weight * 2.20462
                }
                selectedGender = health.biologicalSex
            }
        }
    }
}

