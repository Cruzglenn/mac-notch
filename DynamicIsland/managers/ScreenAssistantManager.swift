/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import SwiftUI
import AVFoundation
import Defaults
import Foundation

// Chat message model
struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let content: String
    let isFromUser: Bool
    let timestamp: Date
    let attachedFiles: [ScreenAssistantFile]?
    var provider: AIModelProvider? = nil // Which provider generated this message
    
    init(content: String, isFromUser: Bool, attachedFiles: [ScreenAssistantFile]? = nil, provider: AIModelProvider? = nil) {
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = Date()
        self.attachedFiles = attachedFiles
        self.provider = provider
    }
}

// Screen Assistant item data structure
struct ScreenAssistantFile: Identifiable, Codable {
    var id = UUID()
    let name: String
    let type: FileType
    let timestamp: Date
    let fileURL: String? // For local files
    let audioFileName: String? // For audio recordings
    
    enum FileType: String, CaseIterable, Codable {
        case document = "document"
        case image = "image"
        case audio = "audio"
        case video = "video"
        case other = "other"
        
        var iconName: String {
            switch self {
            case .document: return "doc.text"
            case .image: return "photo"
            case .audio: return "waveform"
            case .video: return "video"
            case .other: return "doc"
            }
        }
        
        var displayName: String {
            switch self {
            case .document: return "Document"
            case .image: return "Image"
            case .audio: return "Audio"
            case .video: return "Video"
            case .other: return "File"
            }
        }
    }
    
    init(fileURL: URL) {
        // Defensive initialization with nil coalescing
        self.name = fileURL.lastPathComponent.isEmpty ? "Unknown File" : fileURL.lastPathComponent
        self.fileURL = fileURL.absoluteString
        self.audioFileName = nil
        self.timestamp = Date()
        
        // Safe file extension extraction
        let fileExtension = fileURL.pathExtension.lowercased()
        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic":
            self.type = .image
        case "mp3", "wav", "m4a", "aac", "flac":
            self.type = .audio
        case "mp4", "mov", "avi", "mkv":
            self.type = .video
        case "txt", "md", "pdf", "doc", "docx", "rtf":
            self.type = .document
        default:
            self.type = .other
        }
        
        print("✅ ScreenAssistantFile: Created file entry - name: \(self.name), type: \(self.type), url: \(self.fileURL ?? "nil")")
    }
    
    init(audioFileName: String, name: String) {
        self.name = name
        self.type = .audio
        self.fileURL = nil
        self.audioFileName = audioFileName
        self.timestamp = Date()
    }
}

@MainActor
class ScreenAssistantManager: NSObject, ObservableObject {
    static let shared = ScreenAssistantManager()
    
    @Published var attachedFiles: [ScreenAssistantFile] = []
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var chatMessages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var loadingStatus: String = "AI is thinking..."
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var activeRequest: URLSessionTask?
    
    // Panel management
    private var chatMessagesPanel: ChatMessagesPanel?
    private var chatInputPanel: ChatInputPanel?
    
    // Skill context to be injected into the next LLM call
    private var systemContext: String = ""
    
    // Directory for storing audio recordings
    nonisolated static let audioDataDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioDir = documentsPath.appendingPathComponent("ScreenAssistantAudio")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        
        return audioDir
    }()
    
    // Directory for storing screenshots
    nonisolated static let screenshotDataDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let screenshotDir = documentsPath.appendingPathComponent("ScreenAssistantScreenshots")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
        
        return screenshotDir
    }()
    
    private override init() {
        super.init()
        loadFilesFromDefaults()
    }
    
    deinit {
        // Can't call stopRecording() or closePanels() from deinit if they are @MainActor
        // But we can stop the recorder if it exists
        audioRecorder?.stop()
    }
    
    // MARK: - Panel Management
    
    func showPanels() {
        // Close existing panels first
        closePanels()
        
        // Create and show chat messages panel (left side)
        chatMessagesPanel = ChatMessagesPanel()
        chatMessagesPanel?.positionOnLeftSide()
        chatMessagesPanel?.makeKeyAndOrderFront(nil)
        
        // Create and show input panel (center)
        chatInputPanel = ChatInputPanel()
        chatInputPanel?.positionInCenter()
        chatInputPanel?.makeKeyAndOrderFront(nil)
        
        // Focus on input panel for immediate typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.chatInputPanel?.makeKey()
        }
    }
    
    func closePanels() {
        chatMessagesPanel?.close()
        chatInputPanel?.close()
        chatMessagesPanel = nil
        chatInputPanel = nil
    }
    
    func arePanelsVisible() -> Bool {
        return chatMessagesPanel?.isVisible == true || chatInputPanel?.isVisible == true
    }
    
    // MARK: - File Management
    
    func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else {
            print("⚠️ ScreenAssistant: No URLs provided to addFiles")
            return
        }
        
        print("📁 ScreenAssistant: Adding \(urls.count) files")
        
        let newFiles = urls.compactMap { url -> ScreenAssistantFile? in
            autoreleasepool {
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
                return ScreenAssistantFile(fileURL: url)
            }
        }
        
        guard !newFiles.isEmpty else { return }
        
        // Update immediately (we are on @MainActor)
        self.attachedFiles.append(contentsOf: newFiles)
        print("📁 ScreenAssistant: Total attached files: \(self.attachedFiles.count)")
        self.saveFilesToDefaults()
    }
    
    func removeFile(_ file: ScreenAssistantFile) {
        attachedFiles.removeAll { $0.id == file.id }
        
        // Clean up audio file if it exists
        if let audioFileName = file.audioFileName {
            let audioURL = ScreenAssistantManager.audioDataDirectory.appendingPathComponent(audioFileName)
            try? FileManager.default.removeItem(at: audioURL)
        }
        
        saveFilesToDefaults()
    }
    
    func clearAllFiles() {
        // Clean up all audio files
        for file in attachedFiles {
            if let audioFileName = file.audioFileName {
                let audioURL = ScreenAssistantManager.audioDataDirectory.appendingPathComponent(audioFileName)
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        
        attachedFiles.removeAll()
        saveFilesToDefaults()
    }
    
    // MARK: - Audio Recording
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let audioURL = ScreenAssistantManager.audioDataDirectory.appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            isRecording = true
            recordingDuration = 0
            
            // Start timer for recording duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateRecordingDuration()
                }
            }
            
            print("Started recording: \(fileName)")
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        
        print("Stopped recording")
    }
    
    private func updateRecordingDuration() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recordingDuration = recorder.currentTime
    }
    
    // MARK: - Persistence
    
    private func saveFilesToDefaults() {
        do {
            let encoded = try JSONEncoder().encode(attachedFiles)
            UserDefaults.standard.set(encoded, forKey: "ScreenAssistantFiles")
            print("✅ ScreenAssistant: Saved \(attachedFiles.count) files to UserDefaults")
        } catch {
            print("❌ ScreenAssistant: Failed to save files to UserDefaults - \(error)")
            // Don't throw - this is a non-critical operation
        }
    }
    
    private func loadFilesFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: "ScreenAssistantFiles"),
              let decoded = try? JSONDecoder().decode([ScreenAssistantFile].self, from: data) else {
            return
        }
        
        attachedFiles = decoded
    }
    
    // MARK: - Chat Management
    
    func sendMessage(_ message: String) {
        print("📤 ScreenAssistant: Sending message - '\(message)'")
        print("📁 ScreenAssistant: Attached files count: \(attachedFiles.count)")
        
        // --- Skill Routing ---
        let currentAttachment = attachedFiles.first
        let attachmentType = currentAttachment?.fileURL.flatMap { URL(string: $0)?.pathExtension.lowercased() }
        let skill = SkillRouter.detect(from: message, hasAttachment: !attachedFiles.isEmpty, attachmentType: attachmentType)
        
        print("🧠 ScreenAssistant: Detected skill - \(skill)")
        
        // Clear previous system context
        self.systemContext = ""
        self.loadingStatus = "AI is thinking..."
        
        // Handle skills
        Task {
            switch skill {
            case .none:
                break
                
            case .fileOperations:
                self.loadingStatus = "Scanning files..."
                let result = await FileSkillHandler.handle(message: message)
                injectSystemContext("[SKILL: file_operations]\n\(result)")
                
            case .codeExecution:
                injectSystemContext("[SKILL: code_execution]")
                
            case .imageScreenAnalysis:
                injectSystemContext("[SKILL: image_screen_analysis]")
                
            case .pdfAnalysis:
                self.loadingStatus = "Reading PDF..."
                let pdfText = PDFSkillHandler.extractText(from: currentAttachment)
                injectSystemContext("[SKILL: pdf_analysis]\n[PDF CONTENT]\n\(pdfText)")
                
            case .vendorTax:
                self.loadingStatus = "Analyzing invoice..."
                let pdfText = PDFSkillHandler.extractText(from: currentAttachment)
                let context = VendorTaxSkillHandler.buildContext(from: pdfText)
                injectSystemContext(context)
            }
            
            // --- Complexity Routing ---
            // Route to providers based on task complexity
            let complexity = ComplexityRouter.classify(
                message: message, 
                hasAttachment: !attachedFiles.isEmpty, 
                skill: skill
            )
            
            print("⚖️ ScreenAssistant: Complexity - \(complexity)")
            
            // Use the user's selected provider for everything to ensure consistency
            let routingProvider = Defaults[.selectedAIProvider]
            
            // Proceed to finalize send after skill pre-processing
            self.finalizeSendMessage(message, overrideProvider: routingProvider)
        }
    }
    
    private func injectSystemContext(_ context: String) {
        self.systemContext = context
        print("💉 ScreenAssistant: Injected system context: \(context.prefix(100))...")
    }
    
    private func finalizeSendMessage(_ message: String, overrideProvider: AIModelProvider? = nil) {
        // Add user message to chat
        let userMessage = ChatMessage(content: message, isFromUser: true, attachedFiles: attachedFiles.isEmpty ? nil : attachedFiles)
        chatMessages.append(userMessage)
        
        // Print attached files details
        for (index, file) in attachedFiles.enumerated() {
            print("📎 ScreenAssistant: File \(index + 1): \(file.name) (\(file.type.displayName))")
        }
        
        // Clear input and files after sending
        let currentFiles = attachedFiles
        clearAllFiles()
        
        // Determine the provider to use
        // Priority: 1. override (routing logic) 2. user selection
        let provider = overrideProvider ?? Defaults[.selectedAIProvider]
        
        // Incorporate system context into the message sent to AI
        let messageWithContext: String
        if !systemContext.isEmpty {
            messageWithContext = "\(systemContext)\n\nUSER MESSAGE: \(message)"
        } else {
            messageWithContext = message
        }
        
        sendToAI(message: messageWithContext, files: currentFiles, provider: provider)
    }
    
    private func sendToAI(message: String, files: [ScreenAssistantFile], provider: AIModelProvider) {
        print("🚀 ScreenAssistant: Making API request to \(provider.displayName)")
        isLoading = true
        
        switch provider {
        case .gemini:
            sendToGeminiAPI(message: message, files: files)
        case .openai:
            sendToOpenAIAPI(message: message, files: files)
        case .claude:
            sendToClaudeAPI(message: message, files: files)
        case .local:
            sendToLocalAPI(message: message, files: files)
        case .appleIntelligence:
            sendToAppleIntelligence(message: message, files: files)
        case .chatGPTWeb:
            print("🌐 ScreenAssistant: chatGPTWeb is browser-based, no API call needed.")
            isLoading = false
        case .perplexityWeb:
            print("🌐 ScreenAssistant: perplexityWeb is browser-based, no API call needed.")
            isLoading = false
        }
    }
    
    private func sendToGeminiAPI(message: String, files: [ScreenAssistantFile]) {
        let apiKey = Defaults[.geminiApiKey]
        guard !apiKey.isEmpty else {
            print("❌ ScreenAssistant: No Gemini API key configured")
            addAssistantMessage("Error: No Gemini API key configured. Please set your API key in model settings.")
            isLoading = false
            return
        }
        
        // Get selected model or default to gemini-2.5-flash
        let selectedModel = Defaults[.selectedAIModel] ?? AIModel(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", supportsThinking: true)
        let modelId = selectedModel.id
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):generateContent?key=\(apiKey)") else {
            print("❌ ScreenAssistant: Invalid Gemini API URL")
            addAssistantMessage("Error: Invalid API URL")
            isLoading = false
            return
        }
        
        performAPIRequest(url: url, requestBody: buildGeminiRequestBody(message: message, files: files), provider: .gemini)
    }
    
    private func sendToOpenAIAPI(message: String, files: [ScreenAssistantFile]) {
        let apiKey = Defaults[.openaiApiKey]
        guard !apiKey.isEmpty else {
            print("❌ ScreenAssistant: No OpenAI API key configured")
            addAssistantMessage("Error: No OpenAI API key configured. Please set your API key in model settings.")
            isLoading = false
            return
        }
        
        // Get selected model or default to gpt-4o
        let selectedModel = Defaults[.selectedAIModel] ?? AIModel(id: "gpt-4o", name: "GPT-4o", supportsThinking: false)
        let modelId = selectedModel.id
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            print("❌ ScreenAssistant: Invalid OpenAI API URL")
            addAssistantMessage("Error: Invalid API URL")
            isLoading = false
            return
        }
        
        performOpenAIRequest(url: url, requestBody: buildOpenAIRequestBody(message: message, files: files, model: modelId), apiKey: apiKey)
    }
    
    private func sendToClaudeAPI(message: String, files: [ScreenAssistantFile]) {
        let apiKey = Defaults[.claudeApiKey]
        guard !apiKey.isEmpty else {
            print("❌ ScreenAssistant: No Claude API key configured")
            addAssistantMessage("Error: No Claude API key configured. Please set your API key in model settings.")
            isLoading = false
            return
        }
        
        // Get selected model or default to claude-3-5-sonnet
        let selectedModel = Defaults[.selectedAIModel] ?? AIModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", supportsThinking: false)
        let modelId = selectedModel.id
        
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            print("❌ ScreenAssistant: Invalid Claude API URL")
            addAssistantMessage("Error: Invalid API URL")
            isLoading = false
            return
        }
        
        performClaudeRequest(url: url, requestBody: buildClaudeRequestBody(message: message, files: files, model: modelId), apiKey: apiKey)
    }
    
    private func sendToLocalAPI(message: String, files: [ScreenAssistantFile]) {
        let endpoint = Defaults[.localModelEndpoint]
        guard !endpoint.isEmpty else {
            print("❌ ScreenAssistant: No local endpoint configured")
            addAssistantMessage("Error: No local endpoint configured. Please set your endpoint in model settings.")
            isLoading = false
            return
        }
        
        // Build the URL: append /chat/completions if not already present
        let baseURL = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        let apiURL: String
        if baseURL.hasSuffix("/chat/completions") {
            apiURL = baseURL
        } else {
            apiURL = "\(baseURL)/chat/completions"
        }
        
        guard let url = URL(string: apiURL) else {
            print("❌ ScreenAssistant: Invalid local API URL: \(apiURL)")
            addAssistantMessage("Error: Invalid local API URL")
            isLoading = false
            return
        }
        
        print("🔗 ScreenAssistant: Local model URL = \(apiURL)")
        
        let requestBody = buildLocalModelRequestBody(message: message, files: files)
        performLocalStreamingRequest(url: url, requestBody: requestBody)
    }
    
    private func sendToAppleIntelligence(message: String, files: [ScreenAssistantFile]) {
        let systemPrompt = SystemPromptManager.shared.resolveSystemPrompt()
        let contextualMessage = buildContextualMessage(message: message, files: files)
        
        let provider = AppleIntelligenceProvider.shared
        guard provider.isAvailable else {
            let reason = provider.unavailabilityReason
            print("❌ ScreenAssistant: Apple Intelligence unavailable - \(reason)")
            addAssistantMessage("⚠️ **Apple Intelligence Unavailable**\n\n\(reason)")
            isLoading = false
            return
        }
        
        // Use the conversation history for context
        let history = Array(chatMessages.dropLast()) // Exclude the message we just added
        
        Task { @MainActor in
            do {
                let response = try await provider.sendMessage(
                    message: contextualMessage,
                    conversationHistory: history,
                    systemPrompt: systemPrompt
                )
                self.addAssistantMessage(response, provider: .appleIntelligence)
            } catch {
                print("❌ ScreenAssistant: Apple Intelligence error - \(error)")
                self.addAssistantMessage("❌ **Apple Intelligence Error**\n\n\(error.localizedDescription)", provider: .appleIntelligence)
            }
            self.isLoading = false
        }
    }
    
    // MARK: - API Request Builders
    
    private func buildGeminiRequestBody(message: String, files: [ScreenAssistantFile]) -> [String: Any] {
        var contents: [[String: Any]] = []
        
        // Add previous conversation messages (last 10 for context)
        let recentMessages = Array(chatMessages.suffix(10))
        for chatMessage in recentMessages {
            if chatMessage.id != chatMessages.last?.id { // Don't include the message we just added
                let role = chatMessage.isFromUser ? "user" : "model"
                contents.append([
                    "role": role,
                    "parts": [["text": chatMessage.content]]
                ])
            }
        }
        
        // Build current message parts
        var parts: [[String: Any]] = []
        
        // Add text part (already contains systemContext if any)
        parts.append(["text": message])
        
        // Add file content
        for file in files {
            if let filePart = createGeminiFilePart(for: file) {
                parts.append(filePart)
            }
        }
        
        // Add current message
        contents.append([
            "role": "user",
            "parts": parts
        ])

        var requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "topP": 0.8,
                "topK": 40,
                "maxOutputTokens": 2048,
                "stopSequences": []
            ],
            "safetySettings": [
                [
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_HATE_SPEECH", 
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ]
            ]
        ]

        // Use system instruction only for the global system prompt
        let systemPrompt = SystemPromptManager.shared.resolveSystemPrompt()
        if !systemPrompt.isEmpty {
            requestBody["system_instruction"] = [
                "parts": [["text": systemPrompt]]
            ]
        }
        
        // Add thinking configuration if enabled and model supports it
        let selectedModel = Defaults[.selectedAIModel]
        if selectedModel?.supportsThinking == true && Defaults[.enableThinkingMode] {
            var genConfig = requestBody["generationConfig"] as? [String: Any] ?? [:]
            genConfig["thinkingConfig"] = [
                "thinkingBudget": 0
            ]
            requestBody["generationConfig"] = genConfig
        }
        
        return requestBody
    }
    
    private func buildOpenAIRequestBody(message: String, files: [ScreenAssistantFile], model: String) -> [String: Any] {
        var messages: [[String: Any]] = []
        
        // Add global system prompt
        let systemPrompt = SystemPromptManager.shared.resolveSystemPrompt()
        if !systemPrompt.isEmpty {
            messages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }
        
        // Add conversation history
        let recentMessages = Array(chatMessages.suffix(10))
        for chatMessage in recentMessages {
            if chatMessage.id != chatMessages.last?.id {
                let role = chatMessage.isFromUser ? "user" : "assistant"
                messages.append([
                    "role": role,
                    "content": chatMessage.content
                ])
            }
        }
        
        // Add current message (already contains systemContext if any)
        messages.append([
            "role": "user",
            "content": message
        ])
        
        return [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 2048
        ]
    }
    
    private func buildClaudeRequestBody(message: String, files: [ScreenAssistantFile], model: String) -> [String: Any] {
        var messages: [[String: Any]] = []
        
        // Add conversation history
        let recentMessages = Array(chatMessages.suffix(10))
        for chatMessage in recentMessages {
            if chatMessage.id != chatMessages.last?.id {
                let role = chatMessage.isFromUser ? "user" : "assistant"
                messages.append([
                    "role": role,
                    "content": chatMessage.content
                ])
            }
        }
        
        // Add current message (already contains systemContext if any)
        messages.append([
            "role": "user",
            "content": message
        ])
        
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": messages
        ]
        
        // Global system prompt
        let systemPrompt = SystemPromptManager.shared.resolveSystemPrompt()
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        
        return body
    }
    
    private func buildLocalModelRequestBody(message: String, files: [ScreenAssistantFile]) -> [String: Any] {
        let modelName = Defaults[.localModelName].trimmingCharacters(in: .whitespacesAndNewlines)
        
        var messages: [[String: Any]] = []
        
        // Add global system prompt
        let systemPrompt = SystemPromptManager.shared.resolveSystemPrompt()
        if !systemPrompt.isEmpty {
            messages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }
        
        // Add conversation history
        let recentMessages = Array(chatMessages.suffix(10))
        for chatMessage in recentMessages {
            if chatMessage.id != chatMessages.last?.id {
                let role = chatMessage.isFromUser ? "user" : "assistant"
                messages.append([
                    "role": role,
                    "content": chatMessage.content
                ])
            }
        }
        
        // Build current user message (handling images)
        let imageFiles = files.filter { $0.type == .image }
        
        if !imageFiles.isEmpty {
            var contentParts: [[String: Any]] = []
            for imageFile in imageFiles {
                if let fileURL = imageFile.fileURL,
                   let url = URL(string: fileURL),
                   let imageData = try? Data(contentsOf: url) {
                    let base64String = imageData.base64EncodedString()
                    let pathExtension = url.pathExtension.lowercased()
                    let mimeType = (pathExtension == "png") ? "image/png" : "image/jpeg"
                    contentParts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(mimeType);base64,\(base64String)"]
                    ])
                }
            }
            contentParts.append(["type": "text", "text": message])
            messages.append(["role": "user", "content": contentParts])
        } else {
            messages.append(["role": "user", "content": message])
        }
        
        var body: [String: Any] = [
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 2048,
            "stream": false
        ]
        
        // Robust model identifier handling
        if !modelName.isEmpty && modelName != "..." {
            body["model"] = modelName
        } else {
            // Default identifier that most servers accept if nothing is provided
            body["model"] = "gpt-3.5-turbo" 
        }
        
        return body
    }
    
    private func performLocalStreamingRequest(url: URL, requestBody: [String: Any]) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            request.httpBody = jsonData
        } catch {
            print("❌ ScreenAssistant: Failed to encode local model request - \(error)")
            addAssistantMessage("Error: Failed to encode request")
            isLoading = false
            return
        }
        
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activeRequest = nil
                self.isLoading = false
                
                if let error = error {
                    if (error as NSError).code == NSURLErrorCancelled { return }
                    self.addAssistantMessage("❌ **Connection Error**\n\nCould not connect to the local model server. Make sure LM Studio or Ollama is running at \(url.host ?? "localhost").", provider: .local)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No details"
                    self.addAssistantMessage("❌ **Local Model Error (HTTP \(httpResponse.statusCode))**\n\n\(errorBody)", provider: .local)
                    return
                }
                
                guard let data = data else { return }
                self.parseLocalModelStreamResponse(data: data)
            }
        }
        
        self.activeRequest = task
        task.resume()
    }
    
    // MARK: - API Request Performers
    
    private func performAPIRequest(url: URL, requestBody: [String: Any], provider: AIModelProvider) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            request.httpBody = jsonData
            
            print("📋 ScreenAssistant: Request body size: \(jsonData.count) bytes")
        } catch {
            print("❌ ScreenAssistant: Failed to encode request - \(error)")
            addAssistantMessage("Error: Failed to encode request - \(error.localizedDescription)")
            isLoading = false
            return
        }
        
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentTask = task else { return }
                
                // Ensure this callback belongs to the current in-flight request
                guard self.activeRequest === currentTask else { return }
                
                self.isLoading = false
                self.activeRequest = nil
                
                self.handleResponse(data: data, response: response, error: error, provider: provider)
            }
        }
        
        activeRequest = task
        task?.resume()
    }
    
    private func performOpenAIRequest(url: URL, requestBody: [String: Any], apiKey: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            request.httpBody = jsonData
        } catch {
            print("❌ ScreenAssistant: Failed to encode OpenAI request - \(error)")
            addAssistantMessage("Error: Failed to encode request - \(error.localizedDescription)")
            isLoading = false
            return
        }
        
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentTask = task else { return }
                
                // Ensure this callback belongs to the current in-flight request
                guard self.activeRequest === currentTask else { return }
                
                self.isLoading = false
                self.activeRequest = nil
                
                self.handleResponse(data: data, response: response, error: error, provider: .openai)
            }
        }
        
        activeRequest = task
        task?.resume()
    }
    
    private func performClaudeRequest(url: URL, requestBody: [String: Any], apiKey: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            request.httpBody = jsonData
        } catch {
            print("❌ ScreenAssistant: Failed to encode Claude request - \(error)")
            addAssistantMessage("Error: Failed to encode request - \(error.localizedDescription)")
            isLoading = false
            return
        }
        
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentTask = task else { return }
                
                // Ensure this callback belongs to the current in-flight request
                guard self.activeRequest === currentTask else { return }
                
                self.isLoading = false
                self.activeRequest = nil
                
                self.handleResponse(data: data, response: response, error: error, provider: .claude)
            }
        }
        
        activeRequest = task
        task?.resume()
    }
    
    // MARK: - Response Handlers
    
    private func handleResponse(data: Data?, response: URLResponse?, error: Error?, provider: AIModelProvider) {
        // Check if the request was cancelled (e.g., by resetConversationContext)
        if let error = error as? NSError, error.code == NSURLErrorCancelled {
            print("ℹ️ ScreenAssistant: Request was cancelled")
            return
        }
        
        if let error = error {
            print("❌ ScreenAssistant: Network error - \(error)")
            addAssistantMessage("Error: \(error.localizedDescription)")
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            print("📊 ScreenAssistant: HTTP Status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                handleAPIError(statusCode: httpResponse.statusCode, provider: provider)
                return
            }
        }
        
        guard let data = data else {
            print("❌ ScreenAssistant: No response data")
            addAssistantMessage("Error: No response data")
            return
        }
        
        print("📨 ScreenAssistant: Response data size: \(data.count) bytes")
        
        // Parse response based on provider
        switch provider {
        case .gemini:
            parseGeminiResponse(data: data)
        case .openai:
            parseOpenAIResponse(data: data)
        case .claude:
            parseClaudeResponse(data: data)
        case .local:
            // Local model responses are handled via streaming in performLocalStreamingRequest
            parseLocalModelStreamResponse(data: data)
        case .appleIntelligence:
            // Apple Intelligence responses are handled directly in sendToAppleIntelligence
            break
        case .chatGPTWeb, .perplexityWeb:
            // Web browser handles its own response
            break
        }
    }
    
    private func parseGeminiResponse(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ ScreenAssistant: Successfully parsed Gemini JSON response")
                
                if let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    
                    print("✅ ScreenAssistant: Got Gemini response text: \(text.prefix(100))...")
                    addAssistantMessage(text, provider: .gemini)
                } else {
                    if let error = json["error"] as? [String: Any] {
                        handleAPIError(error: error)
                    } else {
                        print("❌ ScreenAssistant: Unexpected Gemini response format")
                        addAssistantMessage("Error: Unexpected response format from Gemini", provider: .gemini)
                    }
                }
            }
        } catch {
            print("❌ ScreenAssistant: Gemini JSON parsing error - \(error)")
            addAssistantMessage("Error: Failed to parse response - \(error.localizedDescription)")
        }
    }
    
    private func parseOpenAIResponse(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ ScreenAssistant: Successfully parsed OpenAI JSON response")
                
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    print("✅ ScreenAssistant: Got OpenAI response text: \(content.prefix(100))...")
                    addAssistantMessage(content, provider: .openai)
                } else {
                    if let error = json["error"] as? [String: Any] {
                        handleOpenAIError(error: error)
                    } else {
                        print("❌ ScreenAssistant: Unexpected OpenAI response format")
                        addAssistantMessage("Error: Unexpected response format from OpenAI", provider: .openai)
                    }
                }
            }
        } catch {
            print("❌ ScreenAssistant: OpenAI JSON parsing error - \(error)")
            addAssistantMessage("Error: Failed to parse response - \(error.localizedDescription)")
        }
    }
    
    private func parseClaudeResponse(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ ScreenAssistant: Successfully parsed Claude JSON response")
                
                if let content = json["content"] as? [[String: Any]],
                   let firstContent = content.first,
                   let text = firstContent["text"] as? String {
                    
                    print("✅ ScreenAssistant: Got Claude response text: \(text.prefix(100))...")
                    addAssistantMessage(text, provider: .claude)
                } else {
                    if let error = json["error"] as? [String: Any] {
                        handleClaudeError(error: error)
                    } else {
                        print("❌ ScreenAssistant: Unexpected Claude response format")
                        addAssistantMessage("Error: Unexpected response format from Claude", provider: .claude)
                    }
                }
            }
        } catch {
            print("❌ ScreenAssistant: Claude JSON parsing error - \(error)")
            addAssistantMessage("Error: Failed to parse response - \(error.localizedDescription)")
        }
    }
    
    /// Parses an OpenAI-compatible streaming response (SSE format from LM Studio / Ollama OpenAI mode).
    /// Handles both streamed SSE format and non-streamed JSON fallback.
    private func parseLocalModelStreamResponse(data: Data) {
        guard let rawString = String(data: data, encoding: .utf8) else {
            print("❌ ScreenAssistant: Could not decode local model response as UTF-8")
            addAssistantMessage("Error: Could not decode response from local model")
            isLoading = false
            return
        }
        
        print("📨 ScreenAssistant: Local model response (\(data.count) bytes)")
        
        // Check if this is SSE streamed data (lines starting with "data: ")
        if rawString.contains("data: ") {
            var fullContent = ""
            let lines = rawString.components(separatedBy: "\n")
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                guard trimmedLine.hasPrefix("data: ") else { continue }
                
                let jsonString = String(trimmedLine.dropFirst(6)) // Remove "data: " prefix
                
                // Check for stream end signal
                if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                    break
                }
                
                // Parse each SSE chunk
                if let chunkData = jsonString.data(using: .utf8),
                   let chunk = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                   let choices = chunk["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    fullContent += content
                }
            }
            
            if !fullContent.isEmpty {
                print("✅ ScreenAssistant: Got local model streamed response: \(fullContent.prefix(100))...")
                addAssistantMessage(fullContent, provider: .local)
            } else {
                print("❌ ScreenAssistant: Empty streamed response from local model")
                addAssistantMessage("Error: Received empty response from local model", provider: .local)
            }
        } else {
            // Fallback: try parsing as a standard OpenAI non-streamed JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        print("✅ ScreenAssistant: Got local model response: \(content.prefix(100))...")
                        addAssistantMessage(content, provider: .local)
                    } else if let error = json["error"] as? [String: Any],
                              let errorMsg = error["message"] as? String {
                        print("❌ ScreenAssistant: Local model API error: \(errorMsg)")
                        addAssistantMessage("❌ **Local Model Error**\n\n\(errorMsg)", provider: .local)
                    } else {
                        // Last resort: try Ollama's native format for backward compat
                        if let message = json["message"] as? [String: Any],
                           let content = message["content"] as? String {
                            print("✅ ScreenAssistant: Got Ollama-format response: \(content.prefix(100))...")
                            addAssistantMessage(content, provider: .local)
                        } else {
                            print("❌ ScreenAssistant: Unexpected local model response format")
                            addAssistantMessage("Error: Unexpected response format from local model", provider: .local)
                        }
                    }
                }
            } catch {
                print("❌ ScreenAssistant: Local model JSON parsing error - \(error)")
                addAssistantMessage("Error: Failed to parse response - \(error.localizedDescription)")
            }
        }
        
        isLoading = false
    }
    
    private func buildContextualMessage(message: String, files: [ScreenAssistantFile]) -> String {
        var contextualMessage = message
        
        // Add file context with specific instructions for different types
        if !files.isEmpty {
            contextualMessage += "\n\nI have attached the following files for your analysis:"
            
            var hasImages = false
            var hasDocuments = false
            var hasAudio = false
            var hasVideo = false
            
            for file in files {
                contextualMessage += "\n- \(file.name) (\(file.type.displayName))"
                
                switch file.type {
                case .image: hasImages = true
                case .document: hasDocuments = true
                case .audio: hasAudio = true
                case .video: hasVideo = true
                case .other: break
                }
            }
            
            // Add specific instructions based on file types
            contextualMessage += "\n\nPlease analyze these files in the context of my question. Specifically:"
            
            if hasImages {
                contextualMessage += "\n- For images: Describe what you see, identify objects, text, or patterns, and relate them to my question."
            }
            
            if hasDocuments {
                contextualMessage += "\n- For documents: Read and understand the content, extract key information, and provide insights relevant to my question."
            }
            
            if hasAudio {
                contextualMessage += "\n- For audio: Listen to and transcribe the audio content, identify speakers, topics, or sounds as relevant."
            }
            
            if hasVideo {
                contextualMessage += "\n- For video: Analyze both visual and audio content, describe actions, scenes, or dialogue as applicable."
            }
            
            contextualMessage += "\n\nProvide comprehensive insights that combine information from all attached files with your response to my question."
        }
        
        return contextualMessage
    }
    
    private func createGeminiFilePart(for file: ScreenAssistantFile) -> [String: Any]? {
        print("📎 ScreenAssistant: Processing file for Gemini 2.5: \(file.name) (\(file.type.displayName))")
        
        guard let fileURL = file.fileURL, let url = URL(string: fileURL) else {
            print("❌ ScreenAssistant: No valid URL for file \(file.name)")
            return ["text": "File: \(file.name) (no valid URL)"]
        }
        
        switch file.type {
        case .image:
            return createGeminiImagePart(for: url, fileName: file.name)
        case .document:
            return createGeminiDocumentPart(for: url, fileName: file.name)
        case .audio:
            return createGeminiAudioPart(for: url, fileName: file.name)
        case .video:
            return createGeminiVideoPart(for: url, fileName: file.name)
        case .other:
            return createGeminiTextPart(for: url, fileName: file.name)
        }
    }
    
    private func createGeminiImagePart(for url: URL, fileName: String) -> [String: Any]? {
        print("🖼️ ScreenAssistant: Processing image file: \(fileName)")
        
        do {
            let imageData = try Data(contentsOf: url)
            let base64String = imageData.base64EncodedString()
            
            // Determine MIME type
            let mimeType: String
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "jpg", "jpeg":
                mimeType = "image/jpeg"
            case "png":
                mimeType = "image/png"
            case "gif":
                mimeType = "image/gif"
            case "webp":
                mimeType = "image/webp"
            case "heic":
                mimeType = "image/heic"
            default:
                mimeType = "image/jpeg"
            }
            
            print("📎 ScreenAssistant: Image encoded - \(base64String.count) bytes, MIME: \(mimeType)")
            
            return [
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64String
                ]
            ]
        } catch {
            print("❌ ScreenAssistant: Failed to encode image \(fileName): \(error)")
            return ["text": "Image file: \(fileName) (failed to encode: \(error.localizedDescription))"]
        }
    }
    
    private func createGeminiDocumentPart(for url: URL, fileName: String) -> [String: Any]? {
        print("📄 ScreenAssistant: Processing document file: \(fileName)")
        
        let pathExtension = url.pathExtension.lowercased()
        
        if pathExtension == "pdf" {
            // Handle PDF files using base64 encoding for Gemini 2.5
            do {
                let pdfData = try Data(contentsOf: url)
                let base64String = pdfData.base64EncodedString()
                
                print("📎 ScreenAssistant: PDF encoded - \(base64String.count) bytes")
                
                return [
                    "inline_data": [
                        "mime_type": "application/pdf",
                        "data": base64String
                    ]
                ]
            } catch {
                print("❌ ScreenAssistant: Failed to encode PDF \(fileName): \(error)")
                return ["text": "PDF file: \(fileName) (failed to encode: \(error.localizedDescription))"]
            }
        } else {
            // Handle text-based documents
            do {
                let content = try String(contentsOf: url)
                print("📄 ScreenAssistant: Read document content (\(content.count) characters)")
                return ["text": "File content of \(fileName):\n\(content)"]
            } catch {
                print("❌ ScreenAssistant: Failed to read document \(fileName): \(error)")
                return ["text": "Document file: \(fileName) (could not read content: \(error.localizedDescription))"]
            }
        }
    }
    
    private func createGeminiAudioPart(for url: URL, fileName: String) -> [String: Any]? {
        print("🎵 ScreenAssistant: Processing audio file: \(fileName)")
        
        do {
            let audioData = try Data(contentsOf: url)
            let base64String = audioData.base64EncodedString()
            
            // Determine MIME type
            let mimeType: String
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "mp3":
                mimeType = "audio/mpeg"
            case "wav":
                mimeType = "audio/wav"
            case "m4a":
                mimeType = "audio/mp4"
            case "aac":
                mimeType = "audio/aac"
            case "flac":
                mimeType = "audio/flac"
            default:
                mimeType = "audio/mpeg"
            }
            
            print("� ScreenAssistant: Audio encoded - \(base64String.count) bytes, MIME: \(mimeType)")
            
            return [
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64String
                ]
            ]
        } catch {
            print("❌ ScreenAssistant: Failed to encode audio \(fileName): \(error)")
            return ["text": "Audio file: \(fileName) (failed to encode: \(error.localizedDescription))"]
        }
    }
    
    private func createGeminiVideoPart(for url: URL, fileName: String) -> [String: Any]? {
        print("� ScreenAssistant: Processing video file: \(fileName)")
        
        do {
            let videoData = try Data(contentsOf: url)
            let base64String = videoData.base64EncodedString()
            
            // Determine MIME type
            let mimeType: String
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "mp4":
                mimeType = "video/mp4"
            case "mov":
                mimeType = "video/quicktime"
            case "avi":
                mimeType = "video/x-msvideo"
            case "mkv":
                mimeType = "video/x-matroska"
            default:
                mimeType = "video/mp4"
            }
            
            print("📎 ScreenAssistant: Video encoded - \(base64String.count) bytes, MIME: \(mimeType)")
            
            return [
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64String
                ]
            ]
        } catch {
            print("❌ ScreenAssistant: Failed to encode video \(fileName): \(error)")
            return ["text": "Video file: \(fileName) (failed to encode: \(error.localizedDescription))"]
        }
    }
    
    private func createGeminiTextPart(for url: URL, fileName: String) -> [String: Any]? {
        print("📝 ScreenAssistant: Processing text file: \(fileName)")
        
        do {
            let content = try String(contentsOf: url)
            print("📄 ScreenAssistant: Read text content (\(content.count) characters)")
            return ["text": "File content of \(fileName):\n\(content)"]
        } catch {
            print("❌ ScreenAssistant: Failed to read text file \(fileName): \(error)")
            return ["text": "File: \(fileName) (could not read content: \(error.localizedDescription))"]
        }
    }
    
    func clearChat() {
        resetConversationContext()
    }

    func resetConversationContext() {
        // Cancel any in-flight request
        activeRequest?.cancel()
        activeRequest = nil
        
        isLoading = false
        chatMessages.removeAll()
        clearAllFiles()
    }
    
    private func addAssistantMessage(_ content: String, provider: AIModelProvider? = nil) {
        print("💬 ScreenAssistant: Adding assistant message from \(provider?.displayName ?? "unknown"): \(content.prefix(100))...")
        let assistantMessage = ChatMessage(content: content, isFromUser: false, provider: provider)
        chatMessages.append(assistantMessage)
    }
    
    private func handleAPIError(statusCode: Int, provider: AIModelProvider) {
        let userFriendlyMessage: String
        
        switch statusCode {
        case 429:
            userFriendlyMessage = "🚫 **Rate Limited**\n\n\(provider.displayName) is currently rate limiting requests. Please wait a moment and try again."
        case 400:
            userFriendlyMessage = "❌ **Invalid Request**\n\nThere was an issue with your request to \(provider.displayName). Please check your message and attached files."
        case 401:
            userFriendlyMessage = "🔑 **Authentication Error**\n\nYour \(provider.displayName) API key appears to be invalid. Please check your API key in model settings."
        case 403:
            userFriendlyMessage = "🚫 **Access Denied**\n\nYour \(provider.displayName) API key doesn't have permission for this request."
        case 404:
            userFriendlyMessage = "🔍 **Model Not Found**\n\nThe requested model is not available on \(provider.displayName)."
        case 500, 502, 503:
            userFriendlyMessage = "⚠️ **Server Error**\n\n\(provider.displayName) servers are experiencing issues. Please try again in a few minutes."
        default:
            userFriendlyMessage = "❌ **API Error (\(statusCode))**\n\n\(provider.displayName) returned an error. Please try again."
        }
        
        addAssistantMessage(userFriendlyMessage)
    }
    
    private func handleAPIError(error: [String: Any]) {
        guard let code = error["code"] as? Int,
              let message = error["message"] as? String else {
            print("❌ ScreenAssistant: Unknown API Error")
            addAssistantMessage("An unknown error occurred. Please try again.")
            return
        }
        
        print("❌ ScreenAssistant: API Error \(code) - \(message)")
        
        let userFriendlyMessage: String
        
        switch code {
        case 429:
            // Quota exceeded
            if message.contains("quota") || message.contains("exceeded") {
                userFriendlyMessage = "🚫 **API Quota Exceeded**\n\nYou've reached your API usage limit. This usually happens when:\n\n• Too many requests in a short time\n• Daily/monthly quota exceeded\n• Free tier limits reached\n\n**What you can do:**\n• Wait a few minutes and try again\n• Check your API billing\n• Consider upgrading your plan\n\n*The system will work again once the quota resets.*"
            } else {
                userFriendlyMessage = "⏰ **Rate Limited**\n\nToo many requests. Please wait a moment and try again."
            }
            
        case 400:
            userFriendlyMessage = "❌ **Invalid Request**\n\nThere was an issue with your request. Please check your message and attached files."
            
        case 401:
            userFriendlyMessage = "🔑 **Authentication Error**\n\nYour API key appears to be invalid. Please check your API key in settings."
            
        case 403:
            userFriendlyMessage = "🚫 **Access Denied**\n\nYour API key doesn't have permission for this request. Please check your API key settings."
            
        case 404:
            userFriendlyMessage = "🔍 **Model Not Found**\n\nThe requested AI model is not available. Please try again later."
            
        case 500, 502, 503:
            userFriendlyMessage = "⚠️ **Server Error**\n\nThe AI service is experiencing issues. Please try again in a few minutes."
            
        default:
            userFriendlyMessage = "❌ **API Error (\(code))**\n\n\(message.components(separatedBy: ".").first ?? message)"
        }
        
        addAssistantMessage(userFriendlyMessage)
    }
    
    private func handleOpenAIError(error: [String: Any]) {
        if let message = error["message"] as? String {
            let userFriendlyMessage = "❌ **OpenAI Error**\n\n\(message)"
            addAssistantMessage(userFriendlyMessage)
        } else {
            addAssistantMessage("❌ **OpenAI Error**\n\nAn unknown error occurred with OpenAI.")
        }
    }
    
    private func handleClaudeError(error: [String: Any]) {
        if let message = error["message"] as? String {
            let userFriendlyMessage = "❌ **Claude Error**\n\n\(message)"
            addAssistantMessage(userFriendlyMessage)
        } else {
            addAssistantMessage("❌ **Claude Error**\n\nAn unknown error occurred with Claude.")
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension ScreenAssistantManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            
            if flag {
                let fileName = recorder.url.lastPathComponent
                let displayName = "Recording \(DateFormatter.shortTime.string(from: Date()))"
                let audioFile = ScreenAssistantFile(audioFileName: fileName, name: displayName)
                self.attachedFiles.append(audioFile)
                self.saveFilesToDefaults()
                print("Recording saved: \(fileName)")
            } else {
                print("Recording failed")
            }
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            print("Recording encode error: \(error?.localizedDescription ?? "Unknown error")")
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
        }
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
