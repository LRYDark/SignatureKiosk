//
//  Scan.swift
//  GLPIKiosk
//
//  Created by Cyprien Cotinaut on 20/07/2026.
//

import SwiftUI
import VisionKit

struct DocumentScannerView: View {
    @EnvironmentObject private var kiosk: KioskState
    @Binding var scannedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    // États pour la gestion de l'envoi et de l'affichage de ConfirmationView
    @State private var isUploading = false
    @State private var showConfirmation = false
    @State private var isSuccess = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            if isUploading {
                // Écran de chargement pendant l'envoi
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Envoi du document en cours...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Le scanner natif
                ScannerRepresentable(
                    onSuccess: { images in
                        scannedImage = images.first
                        uploadImages(images)
                    },
                    onCancel: {
                        dismiss()
                    }
                )
                .ignoresSafeArea()
            }
        }
        // Affichage de la page de réussite / échec
        .fullScreenCover(isPresented: $showConfirmation) {
            ConfirmationView(success: isSuccess, onDismiss: {
                dismiss() // Ferme le scanner une fois l'écran de confirmation validé
            })
        }
    }
    
    // MARK: - Logique d'envoi API
    
    private func uploadImages(_ images: [UIImage]) {
        isUploading = true
        
        Task {
            do {
                try await sendInvoice(images: images)
                // Succès
                await MainActor.run {
                    isUploading = false
                    isSuccess = true
                    showConfirmation = true
                }
            } catch {
                // Échec
                await MainActor.run {
                    isUploading = false
                    isSuccess = false
                    showConfirmation = true
                }
            }
        }
    }

    private func sendInvoice(images: [UIImage]) async throws {
        let settings = kiosk.settings
        
        var baseURLString = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseURLString.hasSuffix("/") { baseURLString.removeLast() }
        
        guard !baseURLString.isEmpty, let url = URL(string: "\(baseURLString)/plugins/gestion/public/api/device_send_invoice.php") else {
            throw URLError(.badURL)
        }
        
        var serial = settings.deviceSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        if serial.isEmpty {
            serial = UIDevice.current.identifierForVendor?.uuidString ?? "UNKNOWN_SERIAL"
        }

        var authToken = ""
        if settings.authMode == .oauthV22Password {
            if let tokens = KeychainStore.getCodable(OAuthTokens.self, forKey: KeychainStore.keyOAuthTokens) {
                authToken = tokens.accessToken
            }
        } else {
            authToken = settings.userToken
        }
        
        guard let pdfBase64 = images.toMultiPagePDFBase64() else {
            throw NSError(domain: "PDFError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Conversion PDF échouée"])
        }

        let bodyDict: [String: Any] = [
            "file_base64": pdfBase64,
            "filename": "facture.pdf"
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: bodyDict)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(serial, forHTTPHeaderField: "X-Device-Serial")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // 1. On récupère la data en plus de la response
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 2. Logs dans la console Xcode
        if let httpResponse = response as? HTTPURLResponse {
            print("🚀 [Scan API] Code HTTP : \(httpResponse.statusCode)")
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("📦 [Scan API] Réponse : \(responseString)")
        } else {
            print("📦 [Scan API] Réponse : <Impossible de lire les données (non UTF-8)>")
        }
        
        // 3. Vérification indispensable pour détecter les erreurs 4xx/5xx et forcer la page d'échec
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Representable pour le Scanner (VisionKit)

private struct ScannerRepresentable: UIViewControllerRepresentable {
    var onSuccess: ([UIImage]) -> Void
    var onCancel: () -> Void
    
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
        let parent: ScannerRepresentable

        init(_ parent: ScannerRepresentable) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else {
                parent.onCancel()
                return
            }

            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            parent.onSuccess(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
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
