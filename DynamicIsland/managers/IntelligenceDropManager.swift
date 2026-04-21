import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class IntelligenceDropManager: ObservableObject {
    static let shared = IntelligenceDropManager()
    
    enum DropState {
        case dropped
        case reading
        case summary
    }
    
    @Published var currentState: DropState = .dropped
    @Published var droppedFileName: String = "Waiting for file..."
    @Published var droppedFileType: String = ""
    @Published var contentHeight: CGFloat = 320
    @Published var summaryText: String = ""
    @Published var hasActiveDrop: Bool = false
    
    private var droppedFileURL: URL? = nil
    private var cancellables = Set<AnyCancellable>()
    
    func handleDrop(providers: [NSItemProvider]) async {
        for provider in providers {
            if let url = await provider.loadFileURL(typeIdentifier: UTType.fileURL.identifier) {
                processDroppedFile(url: url)
                // Don't start reading automatically so the user can preview the file first
                return
            }
        }
    }
    
    private func processDroppedFile(url: URL) {
        droppedFileURL = url
        droppedFileName = url.lastPathComponent
        droppedFileType = url.pathExtension.uppercased()
        currentState = .dropped
        hasActiveDrop = true
    }
    
    func startReading(customPrompt: String? = nil) {
        currentState = .reading
        
        guard let url = droppedFileURL else {
            self.summaryText = "No file found."
            self.currentState = .summary
            return
        }
        
        let screenManager = ScreenAssistantManager.shared
        
        // Only reset chat and add file if this is the initial read (no custom prompt)
        if customPrompt == nil {
            screenManager.clearChat()
            screenManager.addFiles([url])
            self.summaryText = ""
        }
        
        // Track the start time for the reading animation
        let startTime = Date()
        
        // Clear previous subscriptions
        cancellables.removeAll()
        
        // Listen for AI responses
        screenManager.$chatMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let self = self else { return }
                
                // Look for the latest message from the assistant
                if let lastMessage = messages.last(where: { !$0.isFromUser }) {
                    // Update summary directly with the latest content stream
                    if !lastMessage.content.isEmpty {
                        print("📥 Notch: Received AI text update (\(lastMessage.content.count) chars)")
                        self.summaryText = lastMessage.content
                        
                        // If we are currently in reading state, transition to summary immediately to show the text
                        if self.currentState == .reading {
                            withAnimation(.spring()) {
                                self.currentState = .summary
                            }
                        }
                    }
                    
                    // Stay updated if it finishes loading
                    if !screenManager.isLoading && !lastMessage.content.isEmpty && self.currentState != .summary {
                        withAnimation(.spring()) {
                            self.currentState = .summary
                        }
                    }
                }
            }
            .store(in: &cancellables)
            
        // Fallback for when loading state changes to false and we have no response
        screenManager.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                guard let self = self else { return }
                
                if !isLoading && self.currentState == .reading {
                    // Check if we got an error or no text
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    let delay = max(0, 1.2 - elapsedTime)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if self.summaryText.isEmpty {
                            self.summaryText = "No response received. Please check your AI model configuration."
                        }
                        withAnimation(.spring) {
                            self.currentState = .summary
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        // Send a message to start analysis
        let message = customPrompt ?? "Analyze this document and summarize the key findings."
        screenManager.sendMessage(message)
    }
    
    func reset() {
        currentState = .dropped
        droppedFileName = "Waiting for file..."
        droppedFileType = ""
        summaryText = ""
        droppedFileURL = nil
        hasActiveDrop = false
        cancellables.removeAll()
        ScreenAssistantManager.shared.clearChat()
    }
}
