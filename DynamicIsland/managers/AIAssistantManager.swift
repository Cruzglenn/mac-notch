/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 */

import Foundation
import Combine
import SwiftUI
import Defaults
import WebKit

@MainActor
class AIAssistantManager: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = AIAssistantManager()
    
    @Published var chatMessages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var lastResponse: String = ""
    
    // Shared WebViews to prevent reloading
    @Published var webView: WKWebView
    @Published var perplexityWebView: WKWebView
    private static let processPool = WKProcessPool()
    
    private var cancellables = Set<AnyCancellable>()
    private let screenAssistant = ScreenAssistantManager.shared
    
    private override init() {
        // Setup WebViews
        let config = WKWebViewConfiguration()
        config.processPool = Self.processPool
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.perplexityWebView = WKWebView(frame: .zero, configuration: config)
        
        super.init()
        
        self.webView.navigationDelegate = self
        self.webView.setValue(false, forKey: "drawsBackground")
        
        self.perplexityWebView.navigationDelegate = self
        self.perplexityWebView.setValue(false, forKey: "drawsBackground")
        
        loadChatGPT()
        loadPerplexity()

        // Sync with ScreenAssistantManager's messages
        screenAssistant.$chatMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                self?.chatMessages = messages
                if let last = messages.last, !last.isFromUser {
                    self?.lastResponse = last.content
                }
            }
            .store(in: &cancellables)
            
        screenAssistant.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
    }
    
    func loadChatGPT() {
        if let url = URL(string: "https://chatgpt.com") {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func loadPerplexity() {
        if let url = URL(string: "https://www.perplexity.ai/") {
            let request = URLRequest(url: url)
            perplexityWebView.load(request)
        }
    }
    
    func refresh() {
        webView.reload()
    }
    
    func refreshPerplexity() {
        perplexityWebView.reload()
    }
    
    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        screenAssistant.sendMessage(text)
    }
    
    func clearChat() {
        screenAssistant.clearChat()
        lastResponse = ""
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Inject CSS for clean look
        let css = """
        /* Hide Sidebar and Navigation */
        [data-testid="sidebar"], nav, .gizmo-sidebar-toggle { display: none !important; }
        
        /* Hide Header/Top Bar */
        header, .sticky.top-0, .top-0.sticky { display: none !important; }
        
        /* Hide 'Get Plus' or other promo buttons */
        .bg-token-surface-primary.border-token-border-light { display: none !important; }
        
        /* Hide Footer / Terms / Feedback buttons */
        .text-token-text-tertiary.text-xs, .relative.px-2.py-2.text-center { display: none !important; }
        
        /* Hide History/New Chat buttons that float */
        button.fixed.bottom-3, button.fixed.top-3 { display: none !important; }
        
        /* Adjust Main Content Area to fill the space */
        main { padding-top: 0 !important; margin-left: 0 !important; width: 100% !important; height: 100% !important; }
        .max-w-3xl, .max-w-2xl, .xl\\:max-w-\\[48rem\\], .lg\\:max-w-\\[40rem\\] { 
            max-width: 100% !important; 
            padding-left: 12px !important; 
            padding-right: 12px !important; 
        }
        
        /* Force dark mode background to match notch */
        body, html, main, .bg-token-main-surface-primary { 
            background-color: black !important; 
            color: white !important; 
            zoom: 0.85 !important;
        }
        
        /* Make the bottom input bar more integrated */
        .composer-parent { 
            background-color: black !important; 
            border-top: none !important;
        }
        
        /* Hide the ChatGPT 'mistakes' disclaimer at the bottom to save vertical space */
        .pt-2.text-center.text-xs { display: none !important; }
        
        /* Further optimize space */
        .react-scroll-to-bottom--css-jltsh-1n7m0yu { background-color: black !important; }
        [data-testid="composer-root"] { background-color: black !important; border: 1px solid #222 !important; }
        """
        
        let js = "var style = document.createElement('style'); style.innerHTML = '\(css.replacingOccurrences(of: "\n", with: " "))'; document.head.appendChild(style);"
        webView.evaluateJavaScript(js)
    }
}
