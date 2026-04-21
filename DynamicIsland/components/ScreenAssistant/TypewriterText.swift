import SwiftUI

struct TypewriterText: View {
    let text: String
    
    @State private var displayedText: String = ""
    @State private var currentTask: Task<Void, Never>? = nil
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(displayedText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                animateText(to: text)
            }
            .onChange(of: text) { _, newValue in
                animateText(to: newValue)
            }
            .onDisappear {
                currentTask?.cancel()
            }
    }
    
    private func animateText(to targetText: String) {
        // If it's a connection error or short text, show instantly
        if targetText.contains("**Connection Error**") || targetText.count < 50 {
            displayedText = targetText
            return
        }
        
        // If we are resetting or new text is shorter, reset display
        if targetText.count < displayedText.count {
            displayedText = ""
        }
        
        currentTask?.cancel()
        currentTask = Task {
            // Catch up instantly to everything except the last few characters
            let catchUpPoint = max(0, targetText.count - 20)
            if displayedText.count < catchUpPoint {
                let initialText = String(targetText.prefix(catchUpPoint))
                await MainActor.run {
                    displayedText = initialText
                }
            }
            
            // Type the rest character by character
            while displayedText.count < targetText.count && !Task.isCancelled {
                let nextIndex = targetText.index(targetText.startIndex, offsetBy: displayedText.count)
                let char = targetText[nextIndex]
                
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.05)) {
                        displayedText.append(char)
                    }
                }
                
                // Super fast delay for smooth streaming feel
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }
}
