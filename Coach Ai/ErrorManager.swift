import SwiftUI
import Foundation

/// Centralized error management for user-facing error notifications
final class ErrorManager: ObservableObject {
    static let shared = ErrorManager()
    
    @Published var currentError: AppError? = nil
    @Published var showError: Bool = false
    
    private init() {}
    
    /// Show an error to the user
    func showError(_ error: AppError) {
        DispatchQueue.main.async { [weak self] in
            self?.currentError = error
            self?.showError = true
        }
    }
    
    /// Show a simple error message
    func showErrorMessage(_ message: String, title: String = "Error") {
        showError(AppError(title: title, message: message))
    }
    
    /// Dismiss the current error
    func dismissError() {
        DispatchQueue.main.async { [weak self] in
            self?.showError = false
            // Clear error after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.currentError = nil
            }
        }
    }
}

/// Represents an app error with title and message
struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isRetryable: Bool
    let retryAction: (() -> Void)?
    
    init(title: String, message: String, isRetryable: Bool = false, retryAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.isRetryable = isRetryable
        self.retryAction = retryAction
    }
}

/// Error view modifier to show errors globally
struct ErrorAlertModifier: ViewModifier {
    @StateObject private var errorManager = ErrorManager.shared
    
    func body(content: Content) -> some View {
        content
            .alert(errorManager.currentError?.title ?? "Error", isPresented: $errorManager.showError) {
                if let error = errorManager.currentError {
                    if error.isRetryable, let retryAction = error.retryAction {
                        Button("Retry", role: .none) {
                            retryAction()
                        }
                    }
                    Button("OK", role: .cancel) {
                        errorManager.dismissError()
                    }
                }
            } message: {
                if let error = errorManager.currentError {
                    Text(error.message)
                }
            }
    }
}

extension View {
    func errorAlert() -> some View {
        modifier(ErrorAlertModifier())
    }
}

