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
import Combine

// MARK: - System Prompt Manager

/// Manages system prompts for AI sessions, including a global default
/// and per-app overrides based on the frontmost macOS application.
class SystemPromptManager: ObservableObject {
    static let shared = SystemPromptManager()
    
    /// The label describing the currently active system prompt source
    @Published var activeSystemPromptLabel: String = "None"
    
    /// The bundle identifier of the currently detected frontmost app
    @Published var frontmostAppBundleID: String = ""
    
    /// The name of the currently detected frontmost app
    @Published var frontmostAppName: String = ""
    
    private var workspaceObserver: AnyCancellable?
    
    private init() {
        // Observe frontmost app changes
        startObservingFrontmostApp()
        // Resolve initial state
        _ = resolveSystemPrompt()
    }
    
    deinit {
        workspaceObserver?.cancel()
    }
    
    // MARK: - Frontmost App Observation
    
    private func startObservingFrontmostApp() {
        // Use NSWorkspace notification to detect frontmost app changes
        workspaceObserver = NotificationCenter.default.publisher(
            for: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let self = self else { return }
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.frontmostAppBundleID = app.bundleIdentifier ?? ""
                self.frontmostAppName = app.localizedName ?? ""
                _ = self.resolveSystemPrompt()
            }
        }
        
        // Set initial state
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            frontmostAppBundleID = frontmost.bundleIdentifier ?? ""
            frontmostAppName = frontmost.localizedName ?? ""
        }
    }
    
    // MARK: - Prompt Resolution
    
    /// Resolves the effective system prompt based on the frontmost application.
    /// Checks for per-app override first, then falls back to global prompt.
    /// - Returns: The resolved system prompt string (empty string if none configured)
    @discardableResult
    func resolveSystemPrompt() -> String {
        let enablePerApp = Defaults[.enablePerAppSystemPrompts]
        let globalPrompt = Defaults[.globalSystemPrompt]
        
        // Check for per-app override
        if enablePerApp {
            let bundleID: String
            if !frontmostAppBundleID.isEmpty {
                bundleID = frontmostAppBundleID
            } else if let frontmost = NSWorkspace.shared.frontmostApplication {
                bundleID = frontmost.bundleIdentifier ?? ""
            } else {
                bundleID = ""
            }
            
            if !bundleID.isEmpty {
                let perAppPrompts = Defaults[.perAppSystemPrompts]
                if let appPrompt = perAppPrompts[bundleID], !appPrompt.isEmpty {
                    let appName = frontmostAppName.isEmpty
                        ? (NSWorkspace.shared.frontmostApplication?.localizedName ?? bundleID)
                        : frontmostAppName
                    activeSystemPromptLabel = appName
                    print("📝 SystemPrompt: Using per-app prompt for \(appName) (\(bundleID))")
                    return appPrompt
                }
            }
        }
        
        // Fall back to global prompt
        if !globalPrompt.isEmpty {
            activeSystemPromptLabel = "Default"
            return globalPrompt
        }
        
        activeSystemPromptLabel = "None"
        return ""
    }
    
    // MARK: - Per-App Prompt Management
    
    /// Add or update a per-app system prompt
    func setPrompt(for bundleID: String, prompt: String) {
        var prompts = Defaults[.perAppSystemPrompts]
        if prompt.isEmpty {
            prompts.removeValue(forKey: bundleID)
        } else {
            prompts[bundleID] = prompt
        }
        Defaults[.perAppSystemPrompts] = prompts
        _ = resolveSystemPrompt()
    }
    
    /// Remove a per-app system prompt
    func removePrompt(for bundleID: String) {
        var prompts = Defaults[.perAppSystemPrompts]
        prompts.removeValue(forKey: bundleID)
        Defaults[.perAppSystemPrompts] = prompts
        _ = resolveSystemPrompt()
    }
    
    /// Get the configured prompt for a specific app
    func prompt(for bundleID: String) -> String {
        return Defaults[.perAppSystemPrompts][bundleID] ?? ""
    }
    
    /// Get all configured per-app prompts
    func allPerAppPrompts() -> [(bundleID: String, prompt: String)] {
        return Defaults[.perAppSystemPrompts]
            .map { (bundleID: $0.key, prompt: $0.value) }
            .sorted { $0.bundleID < $1.bundleID }
    }
    
    /// Get a list of currently running applications (for the picker UI)
    func runningApplications() -> [(bundleID: String, name: String, icon: NSImage?)] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular } // Only user-facing apps
            .compactMap { app -> (bundleID: String, name: String, icon: NSImage?)? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? bundleID
                return (bundleID: bundleID, name: name, icon: app.icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        return apps
    }
}
