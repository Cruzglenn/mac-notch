import Foundation
import PDFKit

struct PDFSkillHandler {
    /// Extracts all text content from a PDF file at the specified URL.
    static func extractText(from url: URL) -> String {
        guard let pdf = PDFDocument(url: url) else { 
            return "Could not open PDF at \(url.path)." 
        }
        
        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let content = page.string {
                fullText += content + "\n"
            }
        }
        
        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The PDF appears to be empty or contains only images (OCR not performed)."
        }
        
        return fullText
    }
    
    /// Helper to check if a URL points to a PDF
    static func isPDF(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == "pdf"
    }
    
    /// Convenience method for ScreenAssistantFile
    static func extractText(from file: ScreenAssistantFile?) -> String {
        guard let file = file, 
              let fileURLString = file.fileURL, 
              let url = URL(string: fileURLString) else {
            return "No valid PDF file attached."
        }
        return extractText(from: url)
    }
}
