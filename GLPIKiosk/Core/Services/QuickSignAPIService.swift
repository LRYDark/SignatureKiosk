import Foundation

final class QuickSignAPIService {
    private let http: HTTPClient
    private let settings: KioskSettings

    init(settings: KioskSettings, http: HTTPClient = .shared) {
        self.settings = settings
        self.http = http
    }

    // MARK: - Public

    func fetchTechnicians() async throws -> [QuickTechnician] {
        let resp = try await requestGestionPrepare(
            method: "GET",
            queryItems: [
                URLQueryItem(name: "action", value: "technicians"),
                URLQueryItem(name: "include_remote_technicians", value: "1")
            ]
        )
        let root = try parseJSONDict(resp)
        if (root["ok"] as? Bool) != true {
            throw APIError.httpError(status: resp.statusCode, message: (root["error"] as? String) ?? "technicians_failed")
        }

        let data = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(GestionPrepareTechniciansEnvelope.self, from: data)
        return decoded.remoteTechnicians ?? []
    }

    func searchBL(query: String) async throws -> (results: [QuickBLSearchResult], technicians: [QuickTechnician]) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return ([], []) }

        let resp = try await requestGestionPrepare(
            method: "GET",
            queryItems: [
                URLQueryItem(name: "q", value: clean),
                URLQueryItem(name: "include_remote_technicians", value: "1")
            ]
        )
        let root = try parseJSONDict(resp)
        if (root["ok"] as? Bool) != true {
            throw APIError.httpError(status: resp.statusCode, message: (root["error"] as? String) ?? "bl_search_failed")
        }

        let data = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(GestionPrepareSearchEnvelope.self, from: data)
        return (decoded.results ?? [], decoded.remoteTechnicians ?? [])
    }

    func prepareBL(selection: QuickBLSearchResult) async throws -> QuickBLPrepareResponse {
        guard let save = selection.save, !save.isEmpty,
              let filename = selection.filename, !filename.isEmpty,
              let folder = selection.folder, !folder.isEmpty else {
            throw APIError.parsing("Résultat BL incomplet")
        }

        let body: JSONDict = [
            "save": save,
            "filename": filename,
            "folder": folder,
            "signed": selection.signed ?? 0
        ]

        let resp = try await requestGestionPrepare(method: "POST", jsonBody: body)
        let data = resp.data
        let decoded = try JSONDecoder().decode(QuickBLPrepareResponse.self, from: data)
        if !decoded.ok {
            let root = (try? parseJSONDict(resp)) ?? [:]
            throw APIError.httpError(status: resp.statusCode, message: (root["error"] as? String) ?? "bl_prepare_failed")
        }
        return decoded
    }

    func prepareTicket(ticketID: Int, documentType: String = "intervention_report") async throws -> QuickTicketPrepareResponse {
        let resp = try await request(
            path: "/plugins/rp/api/ticket_prepare.php",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "ticket_id", value: String(ticketID)),
                URLQueryItem(name: "document_type", value: documentType),
                URLQueryItem(name: "include_tasks", value: "1"),
                URLQueryItem(name: "include_followups_details", value: "1"),
                URLQueryItem(name: "include_client_email", value: "1")
            ]
        )

        let decoded = try JSONDecoder().decode(QuickTicketPrepareResponse.self, from: resp.data)
        if !decoded.ok {
            let root = (try? parseJSONDict(resp)) ?? [:]
            throw APIError.httpError(status: resp.statusCode, message: (root["error"] as? String) ?? "ticket_prepare_failed")
        }
        return decoded
    }

    func submitQuickBL(
        surveyID: Int,
        signerName: String,
        signerEmail: String,
        signatureB64: String,
        technicianLogin: String,
        comment: String,
        counterInvoiceClient: Bool
    ) async throws -> QuickSubmitResponse {
        let body: JSONDict = [
            "survey_id": surveyID,
            "signer_name": signerName,
            "signer_email": signerEmail,
            "signature": signatureB64,
            "technician_login": technicianLogin,
            "comment": comment,
            "counter_invoice_client": counterInvoiceClient ? 1 : 0,
            "mail_to_client": signerEmail.isEmpty ? 0 : 1
        ]

        let resp = try await request(path: "/plugins/gestion/api/bl_sign.php", method: "POST", jsonBody: body)
        let decoded = try JSONDecoder().decode(QuickSubmitResponse.self, from: resp.data)
        if !decoded.ok {
            let root = (try? parseJSONDict(resp)) ?? [:]
            throw APIError.httpError(status: resp.statusCode, message: (root["message"] as? String) ?? (root["error"] as? String) ?? "bl_sign_failed")
        }
        return decoded
    }

    func submitQuickTicket(
        prepared: QuickTicketPrepareResponse,
        signerName: String,
        signerEmail: String,
        signatureB64: String,
        technicianID: Int,
        documentType: String = "intervention_report",
        includeFollowups: Bool = true
    ) async throws -> QuickSubmitResponse {
        let taskIDs = prepared.tasks.map(\.id)
        let followupIDs = includeFollowups ? prepared.followups.map(\.id) : []

        var body: JSONDict = [
            "mode": "report",
            "ticket_id": prepared.ticketID,
            "document_type": documentType,
            "signer_name": signerName,
            "signer_email": signerEmail,
            "signature": signatureB64,
            "mail_to_client": signerEmail.isEmpty ? 0 : 1,
            "users_id_tech": technicianID,
            "description": prepared.ticketDescription ?? prepared.ticketTitle ?? "",
            "task_ids": taskIDs,
            "include_followups": includeFollowups ? 1 : 0
        ]
        if includeFollowups {
            body["followup_ids"] = followupIDs
        }

        let resp = try await request(path: "/plugins/rp/api/ticket_sign.php", method: "POST", jsonBody: body)
        let decoded = try JSONDecoder().decode(QuickSubmitResponse.self, from: resp.data)
        if !decoded.ok {
            let root = (try? parseJSONDict(resp)) ?? [:]
            throw APIError.httpError(status: resp.statusCode, message: (root["message"] as? String) ?? (root["error"] as? String) ?? "ticket_sign_failed")
        }
        return decoded
    }

    // MARK: - Private

    private func requestGestionPrepare(
        method: String,
        queryItems: [URLQueryItem] = [],
        jsonBody: JSONDict? = nil
    ) async throws -> HTTPResponse {
        try await request(
            path: "/plugins/gestion/api/bl_prepare.php",
            method: method,
            queryItems: queryItems,
            jsonBody: jsonBody
        )
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        jsonBody: JSONDict? = nil,
        allowOAuthReloginRetry: Bool = true
    ) async throws -> HTTPResponse {
        let initialHeaders = try await authHeaders()
        var resp = try await http.request(
            baseURL: settings.normalizedBaseURL,
            path: path,
            method: method,
            queryItems: queryItems,
            headers: initialHeaders,
            jsonBody: jsonBody
        )

        if shouldRetryOAuthRequest(resp),
           settings.authMode == .oauthV22Password,
           allowOAuthReloginRetry,
           let refreshedHeaders = try await oauthBearerHeaders(forceRelogin: true) {
            resp = try await http.request(
                baseURL: settings.normalizedBaseURL,
                path: path,
                method: method,
                queryItems: queryItems,
                headers: refreshedHeaders,
                jsonBody: jsonBody
            )
        }

        guard resp.statusCode >= 200, resp.statusCode < 300 else {
            let root = (try? parseJSONDict(resp)) ?? [:]
            throw APIError.httpError(status: resp.statusCode, message: (root["message"] as? String) ?? (root["error"] as? String) ?? resp.text)
        }
        return resp
    }

    private func authHeaders() async throws -> [String: String] {
        switch settings.authMode {
        case .legacyV1UserToken:
            let appToken = settings.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let userToken = settings.userToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !appToken.isEmpty else {
                throw APIError.httpError(status: 401, message: "App-Token manquant (mode legacy)")
            }
            guard !userToken.isEmpty else {
                throw APIError.httpError(status: 401, message: "user_token manquant (mode legacy)")
            }
            return [
                "App-Token": appToken,
                "Authorization": "user_token \(userToken)"
            ]

        case .oauthV22Password:
            if let oauthHeaders = try await oauthBearerHeaders(forceRelogin: false) {
                return oauthHeaders
            }

            throw APIError.httpError(
                status: 401,
                message: "Session OAuth absente ou expirée. Connectez/reconnectez l'utilisateur OAuth."
            )
        }
    }

    private func oauthBearerHeaders(forceRelogin: Bool) async throws -> [String: String]? {
        if !forceRelogin,
           let tokens = KeychainStore.getCodable(OAuthTokens.self, forKey: KeychainStore.keyOAuthTokens),
           !tokens.accessToken.isEmpty,
           !tokens.isExpired {
            return ["Authorization": "Bearer \(tokens.accessToken)"]
        }

        let username = settings.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = settings.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = settings.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = (KeychainStore.get(KeychainStore.keyOAuthPassword) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty, !password.isEmpty else {
            return nil
        }

        let authService = GLPIAuthService(http: http)
        let tokens = try await authService.oauthPasswordLogin(settings: settings, password: password)
        KeychainStore.setCodable(tokens, forKey: KeychainStore.keyOAuthTokens)
        return ["Authorization": "Bearer \(tokens.accessToken)"]
    }

    private func shouldRetryOAuthRequest(_ resp: HTTPResponse) -> Bool {
        guard resp.statusCode == 401 || resp.statusCode == 403 else { return false }
        guard let json = resp.json as? JSONDict,
              let error = json["error"] as? String else {
            return resp.statusCode == 401
        }
        return ["invalid_bearer_token", "missing_bearer_token", "auth_failed"].contains(error)
    }

    private func parseJSONDict(_ resp: HTTPResponse) throws -> JSONDict {
        guard let json = resp.json as? JSONDict else {
            throw APIError.parsing("Réponse JSON invalide")
        }
        return json
    }
}

private struct GestionPrepareTechniciansEnvelope: Decodable {
    var ok: Bool
    var remoteTechnicians: [QuickTechnician]?

    enum CodingKeys: String, CodingKey {
        case ok
        case remoteTechnicians = "remote_technicians"
    }
}

private struct GestionPrepareSearchEnvelope: Decodable {
    var ok: Bool
    var results: [QuickBLSearchResult]?
    var remoteTechnicians: [QuickTechnician]?

    enum CodingKeys: String, CodingKey {
        case ok, results
        case remoteTechnicians = "remote_technicians"
    }
}
