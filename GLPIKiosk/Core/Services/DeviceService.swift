// GLPIKiosk — DeviceService.swift
// Gère : checkin, poll, submit, refuse.
// Identification : serial (X-Device-Serial).
// Authentification : Token GLPI v1 (App-Token + User-Token) ou v2 (Bearer OAuth).

import Foundation
import UIKit

final class DeviceService {
    private let http:     HTTPClient
    private let settings: KioskSettings
    private let oauthAccessTokenOverride: String?
    private let authService: GLPIAuthService

    // iOS ne fournit pas le numéro de série matériel aux apps standard.
    // On accepte donc un override (réglages / MDM / Info.plist), sinon fallback IFV.
    static var deviceSerial: String {
        resolvedDeviceSerial()
    }

    static func resolvedDeviceSerial(settings: KioskSettings? = nil) -> String {
        if let override = settings?.deviceSerial.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }

        let managed = KioskManagedConfig.load()
        if let managedSerial = managed.deviceSerial?.trimmingCharacters(in: .whitespacesAndNewlines),
           !managedSerial.isEmpty {
            return managedSerial
        }

        // Essai Info.plist (build config / MDM packaging)
        let plist = Bundle.main.infoDictionary
        for key in ["DeviceSerial", "GLPI_DEVICE_SERIAL", "device_serial"] {
            if let plistSerial = plist?[key] as? String,
               !plistSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return plistSerial
            }
        }

        // Fallback : identifierForVendor (UUID, pas le serial matériel)
        return UIDevice.current.identifierForVendor?.uuidString ?? "UNKNOWN"
    }

    static func resolvedDeviceName(settings: KioskSettings? = nil) -> String {
        if let override = settings?.deviceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }

        let managed = KioskManagedConfig.load()
        if let managedName = managed.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !managedName.isEmpty {
            return managedName
        }

        let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return deviceName.isEmpty ? "iPad" : deviceName
    }

    init(
        settings: KioskSettings,
        oauthAccessTokenOverride: String? = nil,
        http: HTTPClient = .shared
    ) {
        self.settings = settings
        self.oauthAccessTokenOverride = oauthAccessTokenOverride
        self.http     = http
        self.authService = GLPIAuthService(http: http)
    }

    // MARK: - Checkin

    /// Enregistre/met à jour cet appareil sur le serveur.
    func checkin(deviceName: String?) async throws -> CheckinResponse {
        var body: JSONDict = [:]
        let providedName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = providedName.isEmpty
            ? DeviceService.resolvedDeviceName(settings: settings)
            : providedName
        if !resolvedName.isEmpty {
            body["name"] = resolvedName
        }

        let resp = try await requestDeviceEndpoint(
            path: "plugins/gestion/public/api/device_checkin.php",
            method: "POST",
            jsonBody: body
        )

        return try handleDeviceResponse(resp, as: CheckinResponse.self)
    }

    // MARK: - Poll

    /// Interroge le serveur pour une requête de signature en attente.
    func poll() async throws -> PollResponse {
        let resp = try await requestDeviceEndpoint(
            path: "plugins/gestion/public/api/device_poll_v2.php",
            method: "GET"
        )

        return try handleDeviceResponse(resp, as: PollResponse.self)
    }

    // MARK: - Submit

    /// Soumet la signature au serveur.
    func submit(
        requestId:    Int,
        signerName:   String,
        signerEmail:  String,
        signatureB64: String
    ) async throws -> SubmitResponse {
        let body: JSONDict = [
            "request_id":   requestId,
            "signer_name":  signerName,
            "signer_email": signerEmail,
            "signature":    signatureB64,
        ]

        let resp = try await requestDeviceEndpoint(
            path: "plugins/gestion/public/api/device_submit_v2.php",
            method: "POST",
            jsonBody: body
        )

        return try handleDeviceResponse(resp, as: SubmitResponse.self)
    }

    // MARK: - Refuse

    /// Refuse la requête de signature.
    func refuse(requestId: Int) async throws -> SubmitResponse {
        let body: JSONDict = ["request_id": requestId]

        let resp = try await requestDeviceEndpoint(
            path: "plugins/gestion/public/api/device_refuse_v2.php",
            method: "POST",
            jsonBody: body
        )

        return try handleDeviceResponse(resp, as: SubmitResponse.self)
    }

    // MARK: - Direct Sign (Signature Rapide BL / Ticket)

    /// Enregistre une signature directe depuis la borne (sans demande PC).
    func directSign(
        type:         String,
        reference:    String,
        signerName:   String,
        signerEmail:  String,
        signatureB64: String
    ) async throws -> DirectSignResponse {
        let body: JSONDict = [
            "type":             type,
            "reference":        reference,
            "signer_name":      signerName,
            "signer_email":     signerEmail,
            "signature_base64": signatureB64,
        ]

        let resp = try await requestDeviceEndpoint(
            path: "plugins/gestion/public/api/device_direct_sign.php",
            method: "POST",
            jsonBody: body
        )

        return try handleDeviceResponse(resp, as: DirectSignResponse.self)
    }

    // MARK: - Privé

    /// Construit les headers HTTP pour tous les endpoints device.
    /// - X-Device-Serial : identification de la tablette physique
    /// - Auth GLPI (Bearer ou App-Token + User-Token) : sécurité
    private func deviceHeaders(forceOAuthRelogin: Bool = false) async throws -> [String: String] {
        var headers: [String: String] = [
            "X-Device-Serial": DeviceService.resolvedDeviceSerial(settings: settings)
        ]

        switch settings.authMode {
        case .legacyV1UserToken:
            let appToken  = settings.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let userToken = settings.userToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !appToken.isEmpty else {
                throw APIError.httpError(status: 401, message: "App-Token manquant (mode legacy)")
            }
            guard !userToken.isEmpty else {
                throw APIError.httpError(status: 401, message: "user_token manquant (mode legacy)")
            }
            headers["App-Token"] = appToken
            headers["Authorization"] = "user_token \(userToken)"

        case .oauthV22Password:
            if let bearerToken = try await oauthBearerToken(forceRelogin: forceOAuthRelogin) {
                headers["Authorization"] = "Bearer \(bearerToken)"
            } else {
                throw APIError.httpError(
                    status: 401,
                    message: "Session OAuth absente ou expirée. Connectez/reconnectez l'utilisateur OAuth."
                )
            }
        }

        return headers
    }

    private func requestDeviceEndpoint(
        path: String,
        method: String,
        jsonBody: JSONDict? = nil,
        allowOAuthReloginRetry: Bool = true
    ) async throws -> HTTPResponse {
        let initialHeaders = try await deviceHeaders()
        var resp = try await http.request(
            baseURL: settings.normalizedBaseURL,
            path: path,
            method: method,
            headers: initialHeaders,
            jsonBody: jsonBody
        )

        if settings.authMode == .oauthV22Password,
           allowOAuthReloginRetry,
           shouldRetryOAuthRequest(resp),
           let refreshedToken = try await oauthBearerToken(forceRelogin: true) {
            let refreshedHeaders = [
                "X-Device-Serial": DeviceService.resolvedDeviceSerial(settings: settings),
                "Authorization": "Bearer \(refreshedToken)"
            ]
            resp = try await http.request(
                baseURL: settings.normalizedBaseURL,
                path: path,
                method: method,
                headers: refreshedHeaders,
                jsonBody: jsonBody
            )
        }

        return resp
    }

    private func oauthBearerToken(forceRelogin: Bool) async throws -> String? {
        let overrideToken = oauthAccessTokenOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !forceRelogin, !overrideToken.isEmpty {
            return overrideToken
        }

        if !forceRelogin,
           let tokens = KeychainStore.getCodable(OAuthTokens.self, forKey: KeychainStore.keyOAuthTokens),
           !tokens.accessToken.isEmpty,
           !tokens.isExpired {
            return tokens.accessToken
        }

        let username = settings.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = settings.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = settings.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = (KeychainStore.get(KeychainStore.keyOAuthPassword) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty, !password.isEmpty else {
            return nil
        }

        let tokens = try await authService.oauthPasswordLogin(settings: settings, password: password)
        KeychainStore.setCodable(tokens, forKey: KeychainStore.keyOAuthTokens)
        return tokens.accessToken
    }

    private func shouldRetryOAuthRequest(_ resp: HTTPResponse) -> Bool {
        guard resp.statusCode == 401 || resp.statusCode == 403 else { return false }
        guard let json = resp.json as? JSONDict,
              let error = json["error"] as? String else {
            return false
        }
        return ["invalid_bearer_token", "missing_bearer_token", "auth_failed"].contains(error)
    }

    private func handleDeviceResponse<T: Decodable>(_ resp: HTTPResponse, as type: T.Type) throws -> T {
        switch resp.statusCode {
        case 200, 201:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(type, from: resp.data)
            } catch {
                throw APIError.parsing(error.localizedDescription)
            }
        case 401, 403:
            if let json = resp.json as? [String: Any],
               let errStr = json["error"] as? String {
                if errStr == "device_banned"  { throw APIError.deviceBanned }
                if errStr == "device_unknown" { throw APIError.deviceUnknown }
                // Erreurs d'authentification GLPI
                if ["auth_failed", "api_disabled", "invalid_bearer_token",
                    "missing_app_token", "invalid_app_token", "missing_bearer_token",
                    "user_disabled", "hl_api_disabled"].contains(errStr) {
                    let msg = json["message"] as? String ?? errStr
                    throw APIError.httpError(status: resp.statusCode, message: msg)
                }
            }
            throw APIError.deviceUnknown
        case 429:
            throw APIError.rateLimited
        case 503:
            throw APIError.remoteSignatureDisabled
        default:
            let msg = (resp.json as? [String: Any])?["error"] as? String ?? "HTTP \(resp.statusCode)"
            throw APIError.httpError(status: resp.statusCode, message: msg)
        }
    }
}
