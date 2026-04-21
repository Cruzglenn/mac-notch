/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 * Adapted from SwiftTerm (https://github.com/migueldeicaza/SwiftTerm)
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

import Foundation
import SwiftUI
import SwiftTerm
import Defaults

// MARK: - Stable Container

final class StableTerminalContainerView: NSView {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let size = bounds.size
        guard size.width >= 10, size.height >= 10 else { return }
        for child in subviews {
            child.frame = bounds
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        for child in subviews {
            child.needsDisplay = true
        }
    }
}

// MARK: - Terminal Session

@MainActor
class TerminalSession: Identifiable, ObservableObject {
    let id = UUID()
    @Published var isProcessRunning: Bool = false
    @Published var terminalTitle: String = "Terminal"
    
    let containerView: StableTerminalContainerView = {
        let v = StableTerminalContainerView(frame: .zero)
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        return v
    }()
    
    var terminalView: LocalProcessTerminalView?
}

// MARK: - Terminal Manager

@MainActor
class TerminalManager: ObservableObject {
    static let shared = TerminalManager()

    @Published var sessions: [TerminalSession] = []
    @Published var activeSessionId: UUID?

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionId }
    }

    // Backward compatibility helpers
    var isProcessRunning: Bool { activeSession?.isProcessRunning ?? false }
    var terminalTitle: String { activeSession?.terminalTitle ?? "Terminal" }
    var containerView: StableTerminalContainerView { activeSession!.containerView }
    var terminalView: LocalProcessTerminalView? { activeSession?.terminalView }

    private init() {
        addNewSession()
    }

    func addNewSession() {
        let session = TerminalSession()
        sessions.append(session)
        activeSessionId = session.id
    }

    func closeSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].terminalView?.terminate()
        sessions.remove(at: index)
        
        if sessions.isEmpty {
            addNewSession()
        } else if activeSessionId == id {
            let newIndex = max(0, index - 1)
            activeSessionId = sessions[newIndex].id
        }
    }

    func ensureTerminalView(for session: TerminalSession, delegate: LocalProcessTerminalViewDelegate) {
        let containerView = session.containerView
        let terminalView = session.terminalView
        
        if let existing = terminalView, existing.superview === containerView {
            existing.processDelegate = delegate
            existing.needsDisplay = true
            return
        }

        let initialFrame = containerView.bounds.size.width >= 10
            ? containerView.bounds
            : CGRect(x: 0, y: 0, width: 400, height: 300)

        let view = LocalProcessTerminalView(frame: initialFrame)
        view.autoresizingMask = [.width, .height]

        applyAllSettings(to: view)

        view.processDelegate = delegate

        containerView.subviews.forEach { $0.removeFromSuperview() }
        containerView.addSubview(view)
        session.terminalView = view

        let containerSize = containerView.bounds.size
        if containerSize.width >= 10, containerSize.height >= 10 {
            view.frame = containerView.bounds
        }
    }

    func startShellProcess(for session: TerminalSession) {
        guard let view = session.terminalView, !session.isProcessRunning else { return }
        
        let shell = Defaults[.terminalShellPath]
        let execName = "-" + (shell as NSString).lastPathComponent

        view.startProcess(
            executable: shell,
            args: [],
            environment: buildEnvironment(),
            execName: execName,
            currentDirectory: NSHomeDirectory()
        )
        
        // Defer the state change to the next run loop to avoid SwiftUI's 
        // "Publishing changes from within view updates is not allowed" warning.
        Task { @MainActor in
            session.isProcessRunning = true
        }
    }

    func processDidTerminate(for session: TerminalSession, exitCode: Int32?) {
        session.isProcessRunning = false
    }

    func restartShell(for session: TerminalSession) {
        session.terminalView?.terminate()
        session.terminalView?.removeFromSuperview()
        session.terminalView = nil
        session.isProcessRunning = false
        session.terminalTitle = "Terminal"
    }
    
    // Convenience for active session
    func restartShell() {
        guard let activeSession = activeSession else { return }
        restartShell(for: activeSession)
    }

    func updateTitle(for session: TerminalSession, title: String) {
        session.terminalTitle = title
    }

    private func resolveFont(family: String, size: CGFloat) -> NSFont {
        if !family.isEmpty, let custom = NSFont(name: family, size: size) {
            return custom
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func applyAllSettings(to view: LocalProcessTerminalView) {
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        let fontFamily = Defaults[.terminalFontFamily]
        view.font = resolveFont(family: fontFamily, size: fontSize)
        view.layer?.opacity = Float(Defaults[.terminalOpacity])
        view.nativeBackgroundColor = NSColor(Defaults[.terminalBackgroundColor])
        view.nativeForegroundColor = NSColor(Defaults[.terminalForegroundColor])
        view.caretColor = NSColor(Defaults[.terminalCursorColor])

        let cursorStyle = TerminalCursorStyleOption(rawValue: Defaults[.terminalCursorStyle])
            ?? .blinkBlock
        view.getTerminal().options.cursorStyle = cursorStyle.swiftTermStyle

        let scrollback = Defaults[.terminalScrollbackLines]
        view.getTerminal().buffer.changeHistorySize(scrollback)
        view.getTerminal().options.scrollback = scrollback

        view.optionAsMetaKey = Defaults[.terminalOptionAsMeta]
        view.allowMouseReporting = Defaults[.terminalMouseReporting]
        view.useBrightColors = Defaults[.terminalBoldAsBright]
    }

    func applyFontSize(_ size: Double) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            let fontFamily = Defaults[.terminalFontFamily]
            view.font = resolveFont(family: fontFamily, size: CGFloat(size))
        }
    }

    func applyFontFamily(_ family: String) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            let fontSize = CGFloat(Defaults[.terminalFontSize])
            view.font = resolveFont(family: family, size: fontSize)
        }
    }

    func applyOpacity(_ opacity: Double) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.layer?.opacity = Float(opacity)
        }
    }

    func applyCursorStyle(_ style: TerminalCursorStyleOption) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.getTerminal().options.cursorStyle = style.swiftTermStyle
            view.setNeedsDisplay(view.bounds)
        }
    }

    func applyScrollback(_ lines: Int) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.getTerminal().buffer.changeHistorySize(lines)
            view.getTerminal().options.scrollback = lines
        }
    }

    func applyOptionAsMeta(_ enabled: Bool) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.optionAsMetaKey = enabled
        }
    }

    func applyMouseReporting(_ enabled: Bool) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.allowMouseReporting = enabled
        }
    }

    func applyBoldAsBright(_ enabled: Bool) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.useBrightColors = enabled
        }
    }

    func applyBackgroundColor(_ color: SwiftUI.Color) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.nativeBackgroundColor = NSColor(color)
        }
    }

    func applyForegroundColor(_ color: SwiftUI.Color) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.nativeForegroundColor = NSColor(color)
        }
    }

    func applyCursorColor(_ color: SwiftUI.Color) {
        for session in sessions {
            guard let view = session.terminalView else { continue }
            view.caretColor = NSColor(color)
        }
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env.removeValue(forKey: "TERM_PROGRAM")
        return env.map { "\($0.key)=\($0.value)" }
    }
}

enum TerminalCursorStyleOption: String, CaseIterable, Defaults.Serializable {
    case blinkBlock = "blinkBlock"
    case steadyBlock = "steadyBlock"
    case blinkUnderline = "blinkUnderline"
    case steadyUnderline = "steadyUnderline"
    case blinkBar = "blinkBar"
    case steadyBar = "steadyBar"

    var swiftTermStyle: CursorStyle {
        switch self {
        case .blinkBlock: return .blinkBlock
        case .steadyBlock: return .steadyBlock
        case .blinkUnderline: return .blinkUnderline
        case .steadyUnderline: return .steadyUnderline
        case .blinkBar: return .blinkBar
        case .steadyBar: return .steadyBar
        }
    }

    var displayName: String {
        switch self {
        case .blinkBlock: return "Block (blinking)"
        case .steadyBlock: return "Block (steady)"
        case .blinkUnderline: return "Underline (blinking)"
        case .steadyUnderline: return "Underline (steady)"
        case .blinkBar: return "Bar (blinking)"
        case .steadyBar: return "Bar (steady)"
        }
    }
}
