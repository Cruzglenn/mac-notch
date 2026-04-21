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

import SwiftUI
import SwiftTerm
import Defaults

// MARK: - NSViewRepresentable wrapper for SwiftTerm

/// Bridges SwiftTerm's `LocalProcessTerminalView` (NSView) into SwiftUI.
///
/// Returns `TerminalSession.containerView` (a stable NSView) so that
/// SwiftUI's view lifecycle never tears down the actual terminal.  The
/// real `LocalProcessTerminalView` lives as a subview of that container
/// and survives notch close/open and tab-switch cycles.
struct TerminalNSViewRepresentable: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    @ObservedObject var terminalManager = TerminalManager.shared

    func makeNSView(context: Context) -> NSView {
        context.coordinator.terminalManager = terminalManager
        context.coordinator.session = session
        terminalManager.ensureTerminalView(for: session, delegate: context.coordinator)
        if !session.isProcessRunning {
            terminalManager.startShellProcess(for: session)
        }
        return session.containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.session = session
        // Re-mount terminal if it was restarted (generation bumped).
        terminalManager.ensureTerminalView(for: session, delegate: context.coordinator)
        if !session.isProcessRunning {
            terminalManager.startShellProcess(for: session)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminalManager: TerminalManager?
        var session: TerminalSession?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal resized — no action needed; SwiftTerm handles reflow.
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                guard let session = session else { return }
                terminalManager?.updateTitle(for: session, title: title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Could be used for breadcrumbs in the future.
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                guard let session = session else { return }
                terminalManager?.processDidTerminate(for: session, exitCode: exitCode)
            }
        }
    }
}

// MARK: - Notch Tab View

/// Guake-style dropdown terminal tab for the notch.
/// Dynamically sizes up to half the screen height; content scrolls when the
/// terminal buffer exceeds the visible area (handled internally by SwiftTerm).
struct NotchTerminalView: View {
    @ObservedObject var terminalManager = TerminalManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.enableTerminalFeature) var enableTerminalFeature
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    var body: some View {
        VStack(spacing: 0) {
            if enableTerminalFeature {
                // Terminal header bar / Tab bar
                HStack(spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(terminalManager.sessions) { session in
                                let isActive = session.id == terminalManager.activeSessionId
                                Button {
                                    terminalManager.activeSessionId = session.id
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "apple.terminal")
                                            .font(.system(size: 10))
                                        Text(session.terminalTitle)
                                            .font(.system(size: 11, weight: isActive ? .medium : .regular))
                                            .lineLimit(1)
                                        
                                        // Close button
                                        if terminalManager.sessions.count > 1 {
                                            Button {
                                                terminalManager.closeSession(id: session.id)
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 9))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.leading, 2)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isActive ? Color.secondary.opacity(0.2) : Color.clear)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(isActive ? .primary : .secondary)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    // Add new tab button
                    Button {
                        terminalManager.addNewSession()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("New Tab (⌘T)")
                    .keyboardShortcut("t", modifiers: .command)

                    // Restart button
                    Button {
                        terminalManager.restartShell()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Restart shell")
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal, 8)

                // Terminal content
                if let activeSession = terminalManager.activeSession {
                    TerminalNSViewRepresentable(session: activeSession)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .padding(.top, 4)
                        .onHover { hovering in
                            updateSuppression(for: hovering)
                        }
                        // Force SwiftUI to update the representable when the active tab changes
                        .id(activeSession.id)
                } else {
                    Spacer()
                }
            } else {
                // Feature disabled placeholder
                VStack(spacing: 8) {
                    Image(systemName: "apple.terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("Terminal is disabled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Enable it in Settings → Terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear {
            updateSuppression(for: false)
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}
