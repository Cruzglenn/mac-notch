import Foundation

enum TaskComplexity {
    case simple
    case complex
}

struct ComplexityRouter {
    /// Classifies a message and context as 'simple' or 'complex'
    static func classify(message: String, hasAttachment: Bool, skill: Skill) -> TaskComplexity {
        // Complex tasks always use robust local models (e.g., Gemma 4 via LM Studio)
        if hasAttachment { return .complex }
        if skill == .pdfAnalysis { return .complex }
        if skill == .imageScreenAnalysis { return .complex }
        if skill == .vendorTax { return .complex }
        
        // Long queries are considered complex
        if message.split(separator: " ").count > 30 { 
            return .complex 
        }

        // Fast/Simple tasks (quick questions) are routed to Apple Intelligence (on-device)
        return .simple
    }
}
