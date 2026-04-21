/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 */

import SwiftUI
import Defaults
import WebKit

struct NotchAIAssistantView: View {
    @ObservedObject var manager = AIAssistantManager.shared
    @ObservedObject var intelligenceDropManager = IntelligenceDropManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.enableAIAssistantFeature) var enableAIAssistantFeature
    @Default(.selectedAIProvider) var selectedAIProvider
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool
    @State private var refreshID = 0
    
    // Scroll suppression (like Terminal)
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    
    var body: some View {
        VStack(spacing: 0) {
            if enableAIAssistantFeature {
                if intelligenceDropManager.hasActiveDrop {
                    NotchIntelligenceDropView()
                } else {
                    // Header (Mimicking Terminal)
                    HStack(spacing: 8) {
                    Image(systemName: selectedAIProvider.iconName)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))

                    Text("AI Assistant")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    // Model Picker in Header
                    Menu {
                        ForEach(AIModelProvider.allCases, id: \.self) { provider in
                            Button {
                                selectedAIProvider = provider
                            } label: {
                                HStack {
                                    Text(provider.displayName)
                                    if selectedAIProvider == provider {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(selectedAIProvider.displayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)

                    Spacer()

                    // Clear/Refresh button
                    Button {
                        if selectedAIProvider == .chatGPTWeb {
                            manager.refresh()
                        } else if selectedAIProvider == .perplexityWeb {
                            manager.refreshPerplexity()
                        } else {
                            manager.clearChat()
                        }
                    } label: {
                        Image(systemName: (selectedAIProvider == .chatGPTWeb || selectedAIProvider == .perplexityWeb) ? "arrow.clockwise" : "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help((selectedAIProvider == .chatGPTWeb || selectedAIProvider == .perplexityWeb) ? "Refresh" : "Clear chat")
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal, 8)

                if selectedAIProvider == .chatGPTWeb {
                    // ChatGPT Web View
                    ChatGPTWebView()
                        .id(refreshID)
                        .onHover { hovering in
                            updateSuppression(for: hovering)
                        }
                } else if selectedAIProvider == .perplexityWeb {
                    // Perplexity Web View
                    PerplexityWebView()
                        .id(refreshID)
                        .onHover { hovering in
                            updateSuppression(for: hovering)
                        }
                } else {
                    // Native Chat Content
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(manager.chatMessages) { message in
                                    ChatMessageView(message: message)
                                        .id(message.id)
                                }
                                
                                if manager.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.mini)
                                        Text("AI is thinking...")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.leading, 4)
                                    .id("loading")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                        }
                        .onHover { hovering in
                            updateSuppression(for: hovering)
                        }
                        .onChange(of: manager.chatMessages.count) { _, _ in
                            withAnimation {
                                proxy.scrollTo(manager.chatMessages.last?.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: manager.isLoading) { _, loading in
                            if loading {
                                withAnimation {
                                    proxy.scrollTo("loading", anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Input Area (Native Only)
                    VStack(spacing: 0) {
                        Divider()
                            .padding(.horizontal, 8)
                        
                        HStack(spacing: 8) {
                            TextField("Ask anything...", text: $inputText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .focused($isFocused)
                                .onSubmit {
                                    sendMessage()
                                }
                            
                            Button(action: sendMessage) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.03))
                    }
                }
            }
        } else {
            // Disabled state
                VStack(spacing: 8) {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("AI Assistant is disabled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Enable it in Settings → AI Assistant")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if enableAIAssistantFeature && selectedAIProvider != .chatGPTWeb && selectedAIProvider != .perplexityWeb {
                isFocused = true
            }
        }
    }
    
    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        manager.sendMessage(inputText)
        inputText = ""
    }
}

// MARK: - ChatGPT Web View Integration

struct ChatGPTWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        return AIAssistantManager.shared.webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Perplexity Web View Integration

struct PerplexityWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        return AIAssistantManager.shared.perplexityWebView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isFromUser { Spacer() }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isFromUser ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(.white)
            }
            
            if !message.isFromUser { Spacer() }
        }
    }
}
