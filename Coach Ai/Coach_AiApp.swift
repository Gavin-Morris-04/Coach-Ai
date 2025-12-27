//
//  Coach_AiApp.swift
//  Coach Ai
//
//  Created by Gavin Morris on 11/5/25.
//

import SwiftUI
import FirebaseCore

@main
struct Coach_AiApp: App {
    @StateObject private var firebase = FirebaseService.shared
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            if firebase.isAuthenticated {
                ContentView()
            } else {
                SignInView()
            }
        }
    }
}
