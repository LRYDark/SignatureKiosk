//
//  InvoiceService.swift
//  GLPIKiosk
//
//  Created by Cyprien Cotinaut on 21/07/2026.
//

import Foundation
import UIKit

struct InvoiceService {
    /// Envoie un ensemble d'images scannées sous forme de document PDF multi-pages
    static func sendInvoice(images: [UIImage], serverURL: String, token: String, serialNumber: String) async throws {
        guard let url = URL(string: "\(serverURL)/plugins/gestion/public/api/device_send_invoice.php") else {
            throw URLError(.badURL)
        }
        
        guard let pdfBase64 = images.toMultiPagePDFBase64() else {
            throw NSError(domain: "PDFError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Conversion PDF multi-pages échouée"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(serialNumber, forHTTPHeaderField: "X-Device-Serial")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "file_base64": pdfBase64,
            "filename": "facture.pdf"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
