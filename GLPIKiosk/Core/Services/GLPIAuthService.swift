import Foundation

final class GLPIAuthService {
    private let http: HTTPClient

    init(http: HTTPClient = .shared) {
        self.http = http
    }

    func oauthPasswordLogin(settings: KioskSettings, password: String) async throws -> OAuthTokens {
        let response = try await http.request(
            baseURL: settings.normalizedBaseURL,
            path: "/api.php/v2.2/token",
            method: "POST",
            formBody: [
                "grant_type": "password",
                "client_id": settings.clientID,
                "client_secret": settings.clientSecret,
                "username": settings.username,
                "password": password,
                "scope": "api user"
            ]
        )

        guard response.statusCode >= 200, response.statusCode < 300 else {
            throw APIError.httpError(
                status: response.statusCode,
                message: "POST \(settings.normalizedBaseURL)/api.php/v2.2/token\n\(response.text)"
            )
        }

        guard let json = response.json as? JSONDict,
              let accessToken = asString(json["access_token"]),
              !accessToken.isEmpty else {
            throw APIError.parsing("Token OAuth introuvable")
        }

        let refreshToken = asString(json["refresh_token"])
        let expiresIn = asInt(json["expires_in"])
        let expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        return OAuthTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    func legacyInitSession(settings: KioskSettings) async throws -> String {
        let appToken = settings.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let userToken = settings.userToken.trimmingCharacters(in: .whitespacesAndNewlines)

        let response = try await http.request(
            baseURL: settings.normalizedBaseURL,
            path: "/api.php/v1/initSession",
            method: "GET",
            headers: [
                "App-Token": appToken,
                "Authorization": "user_token \(userToken)"
            ]
        )

        guard response.statusCode >= 200, response.statusCode < 300 else {
            throw APIError.httpError(
                status: response.statusCode,
                message: "GET \(settings.normalizedBaseURL)/api.php/v1/initSession\n\(response.text)"
            )
        }

        guard let json = response.json as? JSONDict,
              let sessionToken = asString(json["session_token"]),
              !sessionToken.isEmpty else {
            throw APIError.parsing("session_token manquant")
        }

        return sessionToken
    }

}
