//
//  ContentView.swift
//  Coach Ai
//
//  Created by Gavin Morris on 11/5/25.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                HomeView(activeTab: $selectedTab)
                    .tag(0)
                    .tabItem {
                        Label("Home", systemImage: selectedTab == 0 ? "house.fill" : "house")
                    }
                
                TodoListView()
                    .tag(1)
                    .tabItem {
                        Label("Tasks", systemImage: selectedTab == 1 ? "checklist.checked" : "checklist")
                    }
                
                CoachView()
                    .tag(2)
                    .tabItem {
                        Label("Coach", systemImage: selectedTab == 2 ? "brain.head.profile.fill" : "brain.head.profile")
                    }
                
                CaloriesView()
                    .tag(3)
                    .tabItem {
                        Label("Nutrition", systemImage: selectedTab == 3 ? "flame.fill" : "flame")
                    }
                
                FitnessView()
                    .tag(4)
                    .tabItem {
                        Label("Fitness", systemImage: selectedTab == 4 ? "figure.strengthtraining.traditional" : "figure.strengthtraining.traditional")
                    }
            }
            .tint(.white)
        }
        .errorAlert() // Show global error alerts
    }
}

#Preview {
    ContentView()
}
