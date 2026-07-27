//
//  Scan.swift
//  GLPIKiosk
//
//  Created by Cyprien Cotinaut on 20/07/2026.
//

import SwiftUI
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    @EnvironmentObject private var kiosk: KioskState
    @Binding var scannedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            
            guard scan.pageCount > 0 else {
                parent.dismiss()
                return
            }

            // Récupération de TOUTES les pages scannées
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                let img = scan.imageOfPage(at: i)
                images.append(img)
            }
            
            // Preview dans l'interface
            parent.scannedImage = images.first

            // Envoi automatique du PDF multi-pages à l'API après la capture
            Task {
                do {
                    try await parent.sendInvoice(images: images)
                } catch {
                    //
                }
            }

            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }

    // MARK: - Requête API basée sur la conf locale

    private func sendInvoice(images: [UIImage]) async throws {
        let settings = kiosk.settings
        
        // 1. Récupération et nettoyage de la Base URL
        var baseURLString = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseURLString.hasSuffix("/") {
            baseURLString.removeLast()
        }
        
        guard !baseURLString.isEmpty, let url = URL(string: "\(baseURLString)/plugins/gestion/public/api/device_send_invoice.php") else {
            throw URLError(.badURL)
        }
        
        // 2. Extraction du numéro de série
        var serial = settings.deviceSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        if serial.isEmpty {
            serial = UIDevice.current.identifierForVendor?.uuidString ?? "UNKNOWN_SERIAL"
        }

        // 3. Extraction des tokens
        var authToken = ""
        if settings.authMode == .oauthV22Password {
            if let tokens = KeychainStore.getCodable(OAuthTokens.self, forKey: KeychainStore.keyOAuthTokens) {
                authToken = tokens.accessToken
            }
        } else {
            authToken = settings.userToken
        }
        
        // 4. Conversion des images en un seul PDF multi-pages Base64
        guard let pdfBase64 = images.toMultiPagePDFBase64() else {
            throw NSError(domain: "PDFError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Conversion PDF échouée"])
        }

        // 5. Construction du Payload
        let bodyDict: [String: Any] = [
            "file_base64": pdfBase64,
            "filename": "facture.pdf"
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: bodyDict)

        // 6. Préparation et exécution HTTP
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(serial, forHTTPHeaderField: "X-Device-Serial")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
    }
}

// MARK: - Extension PDF Robuste avec UIGraphicsPDFRenderer

extension Array where Element: UIImage {
    /// Convertit un ensemble d'images en un fichier PDF multi-pages encodé en Base64 Data URI
    func toMultiPagePDFBase64() -> String? {
        guard !isEmpty else { return nil }
        
        let renderer = UIGraphicsPDFRenderer(bounds: .zero)
        
        let pdfData = renderer.pdfData { context in
            for image in self {
                let pageBounds = CGRect(origin: .zero, size: image.size)
                
                // Démarre une nouvelle page aux dimensions exactes de l'image
                context.beginPage(withBounds: pageBounds, pageInfo: [:])
                
                // Dessine l'image en tenant compte de l'orientation iOS native
                image.draw(in: pageBounds)
            }
        }
        
        let base64String = pdfData.base64EncodedString()
        return "data:application/pdf;base64,\(base64String)"
    }
}
