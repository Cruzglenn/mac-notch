import Foundation
import Defaults

enum Skill {
    case fileOperations
    case codeExecution
    case imageScreenAnalysis
    case pdfAnalysis
    case vendorTax
    case none
}

struct SkillRouter {
    static func detect(from message: String, hasAttachment: Bool, attachmentType: String? = nil) -> Skill {
        let lower = message.lowercased()

        // Vendor Tax check first if enabled
        if Defaults[.vendorTaxEnabled] {
            let isInvoiceOrReceipt = lower.contains("invoice") || lower.contains("receipt") || lower.contains("vat") || lower.contains("tax") || lower.contains("dext") || lower.contains("xero")
            
            if isInvoiceOrReceipt {
                return .vendorTax
            }
        }

        // PDF skill — check attachment type first
        if let type = attachmentType, type.lowercased() == "pdf" { return .pdfAnalysis }
        
        // Image skill
        if hasAttachment || lower.contains("screenshot") || lower.contains("what do you see") || lower.contains("analyze this") || lower.contains("describe") { 
            return .imageScreenAnalysis 
        }

        // Code skill
        if lower.contains("run") || lower.contains("execute") || lower.contains("bash") || lower.contains("terminal") || lower.contains("python") || lower.contains("swift") || lower.contains("debug") || lower.contains("script") { 
            return .codeExecution 
        }

        // File skill
        if lower.contains("list files") || lower.contains("read file") || lower.contains("open file") || lower.contains("find file") || lower.contains("write to") || lower.contains("create file") || lower.contains("save as") { 
            return .fileOperations 
        }

        return .none
    }
}
