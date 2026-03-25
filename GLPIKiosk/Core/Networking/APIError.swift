// GLPIKiosk — APIError.swift

import Foundation

enum APIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpError(status: Int, message: String)
    case network(String)
    case parsing(String)
    case deviceBanned
    case deviceUnknown
    case rateLimited
    case remoteSignatureDisabled

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "URL de base invalide"
        case .invalidResponse:
            return "Réponse serveur invalide"
        case .httpError(let status, let message):
            return "Erreur HTTP \(status): \(message)"
        case .network(let msg):
            return "Erreur réseau: \(msg)"
        case .parsing(let msg):
            return "Erreur de parsing: \(msg)"
        case .deviceBanned:
            return "Cet appareil est banni. Contactez l'administrateur."
        case .deviceUnknown:
            return "Appareil non enregistré. Vérifiez la configuration."
        case .rateLimited:
            return "Trop de requêtes. Ralentissement automatique."
        case .remoteSignatureDisabled:
            return "La signature déportée est désactivée sur le serveur."
        }
    }
}
