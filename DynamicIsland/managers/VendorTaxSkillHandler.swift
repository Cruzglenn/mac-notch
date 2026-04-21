import Foundation

struct VendorTaxSkillHandler {
    static func buildContext(from pdfText: String) -> String {
        return """
        [SKILL: vendor_tax]
        You are a UK VAT specialist. Analyze the following invoice and return ONLY the compact verdict format. No extra text.

        RULES:
        - Non-UK supplier (US, EU, etc.) → ALWAYS "Reverse Charge (20%)" even if VAT = 0
        - UK supplier + VAT charged → "20% VAT on Expenses"
        - UK supplier + 0% VAT → "Zero Rated"
        - Clearly exempt + UK-based only → "No VAT / Exempt"

        OUTPUT FORMAT:
        🏷️  [SUPPLIER NAME]
        📍  [REGISTRATION: UK / Outside UK / UK Branch of foreign co.]
        ✅  RECOMMENDED TAX: [exact Dext tax label]
        💰  TAX AMOUNT: [£X.XX or $X.XX or £0 / reverse charge]
        📝  DESCRIPTION: [short expense description for Dext]
        WHY: [1-2 sentences max]
        ⚠️  [Only if unusual]

        [INVOICE CONTENT]
        \(pdfText)
        """
    }
}
