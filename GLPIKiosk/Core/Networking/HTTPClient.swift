// GLPIKiosk — HTTPClient.swift
// Client HTTP générique, basé sur URLSession async/await.

import Foundation

typealias JSONDict = [String: Any]

struct HTTPResponse {
    let statusCode: Int
    let data:       Data

    var text: String { String(data: data, encoding: .utf8) ?? "" }

    var json: Any? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    func decoded<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = .init()) throws -> T {
        try decoder.decode(type, from: data)
    }
}

final class HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        let config                         = URLSessionConfiguration.default
        config.timeoutIntervalForRequest   = 20
        config.timeoutIntervalForResource  = 30
        self.session = URLSession(configuration: config)
    }

    /// Effectue une requête HTTP.
    /// - Parameters:
    ///   - baseURL: URL de base (ex: "https://glpi.example.com/glpi11")
    ///   - path: Chemin (ex: "/plugins/gestion/public/api/device_poll_v2.php")
    ///   - method: GET, POST, etc.
    ///   - queryItems: Paramètres URL pour GET
    ///   - headers: En-têtes supplémentaires
    ///   - jsonBody: Corps JSON (encode en application/json)
    ///   - formBody: Corps form-urlencoded
    func request(
        baseURL:    String,
        path:       String,
        method:     String        = "GET",
        queryItems: [URLQueryItem] = [],
        headers:    [String: String] = [:],
        jsonBody:   JSONDict?     = nil,
        formBody:   [String: String]? = nil
    ) async throws -> HTTPResponse {

        let rawURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                   + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard var components = URLComponents(string: rawURL) else {
            throw APIError.invalidBaseURL
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidBaseURL
        }

        var request        = URLRequest(url: url)
        request.httpMethod = method

        // En-têtes par défaut
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // En-têtes personnalisés (incluant X-Device-Serial)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Corps
        if let json = jsonBody {
            let data = try JSONSerialization.data(withJSONObject: json)
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let form = formBody {
            let encoded = form.map { k, v in
                "\(k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k)"
                + "="
                + "\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)"
            }.joined(separator: "&")
            request.httpBody = encoded.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(start)

            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            DebugLogger.log(
                "HTTP",
                "\(method.uppercased()) \(path) -> \(http.statusCode) (\(data.count)B)",
                duration: elapsed
            )

            return HTTPResponse(statusCode: http.statusCode, data: data)
        } catch let error as APIError {
            throw error
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            DebugLogger.error("HTTP", "\(method.uppercased()) \(path) -> ERREUR: \(error.localizedDescription)", duration: elapsed)
            throw APIError.network(error.localizedDescription)
        }
    }
}
