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
import Defaults

private func applyModelSelectionCornerMask(_ view: NSView, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = NSColor.clear.cgColor
    if #available(macOS 13.0, *) {
        view.layer?.cornerCurve = .continuous
    }
}

// MARK: - Model Selection Panel
class ModelSelectionPanel: NSPanel {
    
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        
        setupWindow()
        setupContentView()
    }
    
    override var canBecomeKey: Bool {
        return true  // Can receive focus for interaction
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // Handle ESC key globally for the panel
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            close()
        } else {
            super.keyDown(with: event)
        }
    }
    
    private func setupWindow() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true  // Enable dragging
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        
        styleMask.insert(.fullSizeContentView)
        
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary
        ]
        
        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
        
        acceptsMouseMovedEvents = true
    }
    
    private func setupContentView() {
        let contentView = ModelSelectionView()
        let hostingView = NSHostingView(rootView: contentView)
        applyModelSelectionCornerMask(hostingView, radius: 16)
        self.contentView = hostingView
        
        // Set size for model selection panel
        let preferredSize = CGSize(width: 450, height: 600)
        hostingView.setFrameSize(preferredSize)
        setContentSize(preferredSize)
    }
    
    func positionInCenter() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        
        // Position in the center of the screen
        let xPosition = (screenFrame.width - panelFrame.width) / 2 + screenFrame.minX
        let yPosition = (screenFrame.height - panelFrame.height) / 2 + screenFrame.minY
        
        setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
    }
    
    deinit {
        ScreenCaptureVisibilityManager.shared.unregister(self)
    }
}

// MARK: - Model Selection View
struct ModelSelectionView: View {
    @State private var selectedProvider: AIModelProvider = Defaults[.selectedAIProvider]
    @State private var selectedModel: AIModel? = Defaults[.selectedAIModel]
    @State private var enableThinking: Bool = Defaults[.enableThinkingMode]
    
    // API Keys
    @State private var geminiApiKey: String = Defaults[.geminiApiKey]
    @State private var openaiApiKey: String = Defaults[.openaiApiKey]
    @State private var claudeApiKey: String = Defaults[.claudeApiKey]
    @State private var localEndpoint: String = Defaults[.localModelEndpoint]
    @State private var localModelName: String = Defaults[.localModelName]
    
    @State private var showingApiKeyAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Model Selection")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Choose your preferred AI model and configuration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: closePanel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Provider Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Provider")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            ForEach(AIModelProvider.allCases) { provider in
                                ProviderCard(
                                    provider: provider,
                                    isSelected: selectedProvider == provider,
                                    onSelect: { selectedProvider = provider }
                                )
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Model Selection
                    if !selectedProvider.supportedModels.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(selectedProvider == .local ? "Local Model Configuration" : "\(selectedProvider.displayName) Models")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 8) {
                                ForEach(selectedProvider.supportedModels) { model in
                                    ModelRow(
                                        model: model,
                                        isSelected: selectedModel?.id == model.id,
                                        onSelect: { selectedModel = model }
                                    )
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Thinking Mode Toggle
                    if selectedModel?.supportsThinking == true {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reasoning Mode")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Enable Thinking Mode")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Text("Shows the model's reasoning process before the final answer")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $enableThinking)
                                    .toggleStyle(SwitchToggleStyle())
                            }
                            .padding(16)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    
                    Divider()
                    
                    // API Configuration
                    VStack(alignment: .leading, spacing: 12) {
                        Text("API Configuration")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        ApiConfigurationSection(
                            provider: selectedProvider,
                            geminiApiKey: $geminiApiKey,
                            openaiApiKey: $openaiApiKey,
                            claudeApiKey: $claudeApiKey,
                            localEndpoint: $localEndpoint,
                            localModelName: $localModelName
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            
            Divider()
            
            // Footer with Save/Cancel buttons
            HStack {
                Button("Cancel") {
                    closePanel()
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button("Save Configuration") {
                    saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConfigurationValid)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(ModelSelectionVisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            loadCurrentConfiguration()
        }
    }
    
    private var isConfigurationValid: Bool {
        switch selectedProvider {
        case .gemini:
            return !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openai:
            return !openaiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .claude:
            return !claudeApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .local:
            return !localEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
                   !localModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .appleIntelligence, .chatGPTWeb, .perplexityWeb:
            return true // No API key needed
        }
    }
    
    private func loadCurrentConfiguration() {
        selectedProvider = Defaults[.selectedAIProvider]
        
        // Default based on provider if no model is selected
        if let current = Defaults[.selectedAIModel] {
            selectedModel = current
        } else {
            switch selectedProvider {
            case .chatGPTWeb:
                selectedModel = AIModel(id: "chatgpt-web", name: "ChatGPT Web Browser", supportsThinking: false)
            case .perplexityWeb:
                selectedModel = AIModel(id: "perplexity-web", name: "Perplexity Web Browser", supportsThinking: false)
            case .gemini:
                selectedModel = AIModel(id: "gemini-2.5-flash", name: "Gemini-2.5-flash", supportsThinking: true)
            default:
                selectedModel = selectedProvider.supportedModels.first
            }
        }
        
        enableThinking = Defaults[.enableThinkingMode]
        
        geminiApiKey = Defaults[.geminiApiKey]
        openaiApiKey = Defaults[.openaiApiKey]
        claudeApiKey = Defaults[.claudeApiKey]
        localEndpoint = Defaults[.localModelEndpoint]
        localModelName = Defaults[.localModelName]
    }
    
    private func saveConfiguration() {
        Defaults[.selectedAIProvider] = selectedProvider
        Defaults[.selectedAIModel] = selectedModel
        Defaults[.enableThinkingMode] = enableThinking
        
        Defaults[.geminiApiKey] = geminiApiKey
        Defaults[.openaiApiKey] = openaiApiKey
        Defaults[.claudeApiKey] = claudeApiKey
        Defaults[.localModelEndpoint] = localEndpoint
        Defaults[.localModelName] = localModelName
        
        closePanel()
        
        // Notify that configuration changed
        NotificationCenter.default.post(name: .aiModelConfigurationChanged, object: nil)
    }
    
    private func closePanel() {
        if let window = NSApp.windows.first(where: { $0 is ModelSelectionPanel }) {
            window.close()
        }
    }
}

// MARK: - Provider Card
struct ProviderCard: View {
    let provider: AIModelProvider
    let isSelected: Bool
    let onSelect: () -> Void
    
    /// Whether this provider is currently available for use
    private var isAvailable: Bool {
        switch provider {
        case .appleIntelligence:
            return AppleIntelligenceProvider.shared.isAvailable
        default:
            return true
        }
    }
    
    /// The reason this provider is unavailable (for tooltip/display)
    private var unavailabilityReason: String {
        switch provider {
        case .appleIntelligence:
            return AppleIntelligenceProvider.shared.unavailabilityReason
        default:
            return ""
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : (isAvailable ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)))
                    .frame(width: 50, height: 50)
                
                Image(systemName: iconForProvider(provider))
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : (isAvailable ? .primary : .secondary))
            }
            
            // Name and description
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(provider.displayName)
                        .font(.headline)
                        .foregroundColor(isAvailable ? .primary : .secondary)
                    
                    if !provider.requiresApiKey {
                        Image(systemName: "lock.open.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                
                if !isAvailable {
                    Text("Not available")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    Text(provider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.1) : (isAvailable ? Color.gray.opacity(0.05) : Color.gray.opacity(0.02)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
        .opacity(isAvailable ? 1.0 : 0.6)
        .onTapGesture {
            if isAvailable {
                onSelect()
            }
        }
        .help(isAvailable ? provider.description : unavailabilityReason)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private func iconForProvider(_ provider: AIModelProvider) -> String {
        switch provider {
        case .gemini: return "sparkles"
        case .openai: return "brain.head.profile"
        case .claude: return "doc.text"
        case .local: return "server.rack"
        case .appleIntelligence: return "apple.intelligence"
        case .chatGPTWeb: return "safari"
        case .perplexityWeb: return "magnifyingglass"
        }
    }
}

// MARK: - Model Row
struct ModelRow: View {
    let model: AIModel
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.body)
                    .foregroundColor(.primary)
                
                if model.supportsThinking {
                    Text("Supports reasoning mode")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            } else {
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .onTapGesture {
            onSelect()
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - API Configuration Section
struct ApiConfigurationSection: View {
    let provider: AIModelProvider
    @Binding var geminiApiKey: String
    @Binding var openaiApiKey: String
    @Binding var claudeApiKey: String
    @Binding var localEndpoint: String
    @Binding var localModelName: String
    
    var body: some View {
        VStack(spacing: 12) {
            switch provider {
            case .gemini:
                ApiKeyField(
                    title: "Gemini API Key",
                    placeholder: "Enter your Gemini API key",
                    value: $geminiApiKey,
                    helpText: "Get your API key from Google AI Studio"
                )
                
            case .openai:
                ApiKeyField(
                    title: "OpenAI API Key",
                    placeholder: "Enter your OpenAI API key",
                    value: $openaiApiKey,
                    helpText: "Get your API key from OpenAI Platform"
                )
                
            case .claude:
                ApiKeyField(
                    title: "Claude API Key",
                    placeholder: "Enter your Claude API key",
                    value: $claudeApiKey,
                    helpText: "Get your API key from Anthropic Console"
                )
                
            case .local:
                VStack(spacing: 12) {
                    ApiKeyField(
                        title: "Local Endpoint",
                        placeholder: "http://localhost:1234/v1",
                        value: $localEndpoint,
                        helpText: "LM Studio or Ollama compatible endpoint (OpenAI format)",
                        isSecure: false
                    )
                    
                    ApiKeyField(
                        title: "Model Identifier",
                        placeholder: "gemma-4-e4b-instruct",
                        value: $localModelName,
                        helpText: "Enter the model name exactly as it appears in your local server",
                        isSecure: false
                    )
                    
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Find the model identifier in LM Studio's loaded model name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
            case .appleIntelligence:
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No API Key Required")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Apple Intelligence runs entirely on-device. Your data stays private and never leaves your Mac.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !AppleIntelligenceProvider.shared.isAvailable {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(AppleIntelligenceProvider.shared.unavailabilityReason)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Apple Intelligence is text-only. For image or file analysis, use Gemini or another multimodal provider.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
            case .chatGPTWeb:
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "safari.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No API Key Required")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("ChatGPT Web runs directly in your notch via a built-in browser. Just log in once on the website to start chatting for free.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            case .perplexityWeb:
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No API Key Required")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Perplexity Web runs directly in your notch. Just log in to your account (or Pro) to start researching.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - API Key Field
struct ApiKeyField: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    let helpText: String
    var isSecure: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            if isSecure {
                SecureField(placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
            }
            
            Text(helpText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Visual Effect View
struct ModelSelectionVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Notification Extension
extension Notification.Name {
    static let aiModelConfigurationChanged = Notification.Name("aiModelConfigurationChanged")
}