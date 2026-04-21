/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 */

import SwiftUI
import Defaults
import WebKit

struct NotchMessengerView: View {
    @Default(.enableMessengerFeature) var enableMessengerFeature
    @Default(.messengerStickyMode) var messengerStickyMode
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var messengerManager = MessengerManager.shared
    
    // Scroll suppression
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    
    var body: some View {
        VStack(spacing: 0) {
            if enableMessengerFeature {
                // Header
                HStack(spacing: 8) {
                    Image("Messenger")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)

                    Text("Messenger")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer()

                    // Refresh button
                    Button {
                        messengerManager.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal, 8)

                // Messenger Web View
                SharedMessengerWebView()
            } else {
                Text("Messenger is disabled in settings")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

// MARK: - Messenger Web View Integration

struct SharedMessengerWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        return MessengerManager.shared.webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

