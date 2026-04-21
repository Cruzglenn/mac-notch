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

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Intelligence Provider

/// Provides on-device AI inference using Apple's FoundationModels framework.
/// Available only on macOS 26.0+ (Sequoia 15.4+) with Apple Intelligence enabled.
/// This provider runs entirely on-device and requires no API key.
class AppleIntelligenceProvider {
    static let shared = AppleIntelligenceProvider()
    
    private init() {}
    
    // MARK: - Availability
    
    /// Whether Apple Intelligence is available on this device.
    /// Checks both OS version and model availability.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }
    
    /// A human-readable reason why Apple Intelligence is unavailable.
    var unavailabilityReason: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if !SystemLanguageModel.default.isAvailable {
                return "Apple Intelligence is not available on this device. Ensure Apple Intelligence is enabled in System Settings > Apple Intelligence & Siri."
            }
            return ""
        }
        #endif
        return "Apple Intelligence requires macOS 26.0 (Sequoia 15.4) or later."
    }
    
    // MARK: - Message Sending
    
    /// Send a message to the on-device Apple Intelligence model.
    /// - Parameters:
    ///   - message: The user's message text (already includes file context if applicable)
    ///   - conversationHistory: Previous messages for context
    ///   - systemPrompt: Optional system-level instructions
    /// - Returns: The model's response text
    func sendMessage(
        message: String,
        conversationHistory: [ChatMessage] = [],
        systemPrompt: String = ""
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw AppleIntelligenceError.modelUnavailable
            }
            
            // Create session with optional system instructions
            let session: LanguageModelSession
            if !systemPrompt.isEmpty {
                session = LanguageModelSession(instructions: systemPrompt)
            } else {
                session = LanguageModelSession()
            }
            
            // Build the full prompt with conversation history for context
            let fullPrompt = buildPrompt(
                currentMessage: message,
                conversationHistory: conversationHistory
            )
            
            print("🍎 AppleIntelligence: Sending prompt (\(fullPrompt.count) characters)")
            
            let response = try await session.respond(to: fullPrompt)
            let responseText = response.content
            
            print("🍎 AppleIntelligence: Got response (\(responseText.count) characters)")
            
            return responseText
        }
        #endif
        
        throw AppleIntelligenceError.osVersionTooOld
    }
    
    // MARK: - Prompt Building
    
    /// Builds a single prompt string from conversation history and the current message.
    /// Apple Intelligence does not support multi-turn chat natively via the simple API,
    /// so we concatenate history into the prompt for context.
    private func buildPrompt(
        currentMessage: String,
        conversationHistory: [ChatMessage]
    ) -> String {
        // If no history, just return the current message
        if conversationHistory.isEmpty {
            return currentMessage
        }
        
        // Build context from recent messages (last 10)
        var promptParts: [String] = []
        let recentMessages = Array(conversationHistory.suffix(10))
        
        for msg in recentMessages {
            let role = msg.isFromUser ? "User" : "Assistant"
            promptParts.append("\(role): \(msg.content)")
        }
        
        // Add the current message
        promptParts.append("User: \(currentMessage)")
        promptParts.append("Assistant:")
        
        return promptParts.joined(separator: "\n\n")
    }
}

// MARK: - Errors

enum AppleIntelligenceError: LocalizedError {
    case modelUnavailable
    case osVersionTooOld
    case sessionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Apple Intelligence is not available on this device. Please ensure Apple Intelligence is enabled in System Settings > Apple Intelligence & Siri."
        case .osVersionTooOld:
            return "Apple Intelligence requires macOS 26.0 (Sequoia 15.4) or later."
        case .sessionFailed(let detail):
            return "Apple Intelligence session failed: \(detail)"
        }
    }
}
