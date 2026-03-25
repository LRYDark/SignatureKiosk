// GLPIKiosk — AppModels.swift
// Modèles de données partagés.
// NOTE: Base Description / Info intentionnellement absent de tous les modèles.

import Foundation

// MARK: - Auth

enum APIAuthMode: String, Codable, CaseIterable, Identifiable {
    case oauthV22Password       = "oauth_v22_password"
    case legacyV1UserToken      = "legacy_v1_user_token"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oauthV22Password:  return "OAuth v2.2 (recommandé)"
        case .legacyV1UserToken: return "Legacy v1 (App-Token)"
        }
    }

    var tokenPath: String {
        switch self {
        case .oauthV22Password:  return "/api.php/v2.2/token"
        case .legacyV1UserToken: return "/api.php/v1/initSession"
        }
    }

    /// Parse une chaîne brute (import JSON, MDM…) en APIAuthMode.
    static func parse(_ raw: String) -> APIAuthMode? {
        let compact = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch compact {
        case "oauthv22password", "oauthv22", "oauthv2", "oauth", "v22", "v2":
            return .oauthV22Password
        case "legacyv1usertoken", "legacyv1", "legacy", "v1":
            return .legacyV1UserToken
        default:
            return nil
        }
    }
}

struct OAuthTokens: Codable {
    var accessToken:  String
    var refreshToken: String?
    var expiresAt:    Date?

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() >= exp.addingTimeInterval(-60)
    }
}

// MARK: - Device Config (stocké en Keychain + UserDefaults non-sensible)

struct KioskSettings: Codable {
    var baseURL:      String = ""
    var authMode:     APIAuthMode = .oauthV22Password
    // OAuth v2.2
    var clientID:     String = ""
    var clientSecret: String = ""
    var username:     String = ""
    // Legacy v1
    var appToken:     String = ""
    var userToken:    String = ""
    // Admin
    var adminCode:    String = "2580"
    // Device
    var deviceName:   String = ""
    var deviceSerial: String = ""
    var softSleepDelayMinutes: Int = 5
    // Polling
    var pollIntervalSeconds: Double = 4.0

    var normalizedBaseURL: String {
        baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Supprime les espaces/slashes superflus sur tous les champs texte.
    mutating func trimAllFields() {
        baseURL      = normalizedBaseURL
        clientID     = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        appToken     = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        userToken    = userToken.trimmingCharacters(in: .whitespacesAndNewlines)
        username     = username.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceName   = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceSerial = deviceSerial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init() {}

    enum CodingKeys: String, CodingKey {
        case baseURL
        case authMode
        case clientID
        case clientSecret
        case username
        case appToken
        case userToken
        case adminCode
        case deviceName
        case deviceSerial
        case softSleepDelayMinutes
        case pollIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)

        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? baseURL
        authMode = try c.decodeIfPresent(APIAuthMode.self, forKey: .authMode) ?? authMode
        clientID = try c.decodeIfPresent(String.self, forKey: .clientID) ?? clientID
        clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret) ?? clientSecret
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? username
        appToken = try c.decodeIfPresent(String.self, forKey: .appToken) ?? appToken
        userToken = try c.decodeIfPresent(String.self, forKey: .userToken) ?? userToken
        adminCode = try c.decodeIfPresent(String.self, forKey: .adminCode) ?? adminCode
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? deviceName
        deviceSerial = try c.decodeIfPresent(String.self, forKey: .deviceSerial) ?? deviceSerial
        softSleepDelayMinutes = try c.decodeIfPresent(Int.self, forKey: .softSleepDelayMinutes) ?? softSleepDelayMinutes
        pollIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds) ?? pollIntervalSeconds
    }
}

// MARK: - Managed Config (Intune/MDM)

struct KioskManagedConfig {
    var authMode:           APIAuthMode?
    var baseURL:            String?
    var clientID:           String?
    var clientSecret:       String?
    var defaultUsername:    String?
    var appToken:           String?
    var userToken:          String?
    var adminCode:          String?
    var deviceName:         String?
    var deviceSerial:       String?
    var pollInterval:       Double?
    var lockAPIConfig:      Bool = false

    var isActive: Bool {
        authMode != nil
            || baseURL != nil
            || clientID != nil
            || clientSecret != nil
            || defaultUsername != nil
            || appToken != nil
            || userToken != nil
            || adminCode != nil
            || deviceName != nil
            || deviceSerial != nil
            || pollInterval != nil
            || lockAPIConfig
    }

    static func load() -> KioskManagedConfig {
        guard let managed = UserDefaults.standard.dictionary(forKey: "com.apple.configuration.managed"),
              !managed.isEmpty else {
            return KioskManagedConfig()
        }

        func str(_ keys: String...) -> String? {
            for k in keys {
                if let v = managed[k] as? String, !v.isEmpty { return v }
            }
            return nil
        }
        func dbl(_ keys: String...) -> Double? {
            for k in keys {
                if let v = managed[k] as? Double { return v }
                if let s = managed[k] as? String, let d = Double(s) { return d }
            }
            return nil
        }
        func bool(_ keys: String...) -> Bool? {
            for k in keys {
                if let v = managed[k] as? Bool { return v }
                if let s = managed[k] as? String { return s.lowercased() == "true" }
            }
            return nil
        }

        var cfg = KioskManagedConfig()
        cfg.baseURL       = str("glpi_base_url", "GLPI_BASE_URL", "base_url")
        cfg.clientID      = str("glpi_client_id", "GLPI_CLIENT_ID", "client_id")
        cfg.clientSecret  = str("glpi_client_secret", "GLPI_CLIENT_SECRET", "client_secret")
        cfg.defaultUsername = str(
            "glpi_username_default",
            "GLPI_USERNAME_DEFAULT",
            "username_default",
            "username"
        )
        cfg.appToken      = str("glpi_app_token", "GLPI_APP_TOKEN", "app_token")
        cfg.userToken     = str("glpi_user_token", "GLPI_USER_TOKEN", "user_token")
        cfg.adminCode     = str("glpi_admin_code", "GLPI_ADMIN_CODE", "admin_code")
        cfg.deviceName    = str("glpi_device_name", "GLPI_DEVICE_NAME", "device_name")
        cfg.deviceSerial  = str(
            "glpi_device_serial",
            "GLPI_DEVICE_SERIAL",
            "device_serial",
            "serial_number",
            "serial"
        )
        cfg.pollInterval  = dbl("glpi_poll_interval", "poll_interval")
        cfg.lockAPIConfig = bool("glpi_lock_api_config", "lock_api_config") ?? false

        if let modeStr = str("glpi_auth_mode", "GLPI_AUTH_MODE", "auth_mode") {
            cfg.authMode = APIAuthMode.parse(modeStr)
        }
        return cfg
    }
}

// MARK: - Signature Request (retournée par device_poll_v2)

struct SignatureRequest: Identifiable, Codable, Equatable {
    var id:            Int
    var ticketID:      Int
    var status:        String
    var dateCreation:  String
    var parameters:    SignatureParameters?

    enum CodingKeys: String, CodingKey {
        case id          = "request_id"
        case ticketID    = "ticket_id"
        case status
        case dateCreation = "date_creation"
        case parameters
    }
}

/// Paramètres de la requête de signature envoyée par le PC.
/// NOTE: base_description / base_info / base_items sont intentionnellement
/// exclus — ils ne sont ni stockés ni affichés.
struct SignatureParameters: Codable, Equatable {
    var documentName:      String?
    var documentURL:       String?
    var legacyURL:         String?
    var ticketTitle:       String?
    var entityName:        String?
    var clientEmail:       String?
    var reportType:        String?
    var ticketDescription: String?
    var ticketTasks:       [TicketTask]?
    var ticketFollowups:   [TicketTask]?
    // BL associé (optionnel)
    var blNumber:          String?
    var blAmountHT:        String?
    var blAmountTTC:       String?

    enum CodingKeys: String, CodingKey {
        case documentName    = "document_name"
        case documentURL     = "document_url"
        case legacyURL       = "url"
        case ticketTitle     = "ticket_title"
        case entityName      = "entity_name"
        case clientEmail     = "client_email"
        case reportType      = "report_type"
        case ticketDescription = "ticket_description"
        case ticketTasks     = "ticket_tasks"
        case ticketFollowups = "ticket_followups"
        case blNumber        = "bl_number"
        case blAmountHT      = "bl_amount_ht"
        case blAmountTTC     = "bl_amount_ttc"
    }
}

struct TicketTask: Codable, Identifiable, Equatable {
    var id:      Int
    var content: String
    var state:   Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? c.decode(String.self,    forKey: .content)) ?? ""
        state   =  try? c.decodeIfPresent(Int.self, forKey: .state)
        id      = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? abs(content.hashValue)
    }
}

// MARK: - Poll Response

struct PollResponse: Codable {
    var ok:            Bool
    var pending:       Bool
    var requestId:     Int?
    var ticketId:      Int?
    var status:        String?
    var dateCreation:  String?
    var parameters:    SignatureParameters?

    enum CodingKeys: String, CodingKey {
        case ok, pending
        case requestId    = "request_id"
        case ticketId     = "ticket_id"
        case status
        case dateCreation = "date_creation"
        case parameters
    }

    var asSignatureRequest: SignatureRequest? {
        guard pending, let rid = requestId, let tid = ticketId else { return nil }
        return SignatureRequest(
            id: rid,
            ticketID: tid,
            status: status ?? "pending",
            dateCreation: dateCreation ?? "",
            parameters: parameters
        )
    }
}

// MARK: - Submit / Refuse

struct SubmitResponse: Codable {
    var ok:     Bool
    var status: String?
    var rowId:  Int?

    enum CodingKeys: String, CodingKey {
        case ok, status
        case rowId = "row_id"
    }
}

struct DirectSignResponse: Codable {
    var ok:      Bool
    var id:      Int?
    var message: String?
    var error:   String?
}

struct CheckinResponse: Codable {
    var ok:       Bool
    var status:   String?
    var deviceId: Int?
    var message:  String?

    enum CodingKeys: String, CodingKey {
        case ok, status, message
        case deviceId = "device_id"
    }
}

// MARK: - Quick Sign (shared API Gestion/RP)

struct QuickTechnician: Decodable, Identifiable, Equatable {
    var id: Int
    var login: String
    var label: String
    var display: String?
}

struct QuickBLSearchResult: Decodable, Identifiable, Equatable {
    var id: String
    var text: String?
    var filename: String?
    var folder: String?
    var save: String?
    var source: String?
    var signed: Int?
    var html: String?

    enum CodingKeys: String, CodingKey {
        case id, text, filename, folder, save, source, signed, html
    }

    var displayText: String {
        if let t = text, !t.isEmpty { return t }
        if let f = filename, !f.isEmpty { return f }
        return id
    }

    var isSigned: Bool { (signed ?? 0) == 1 }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func decodeString(_ key: CodingKeys) -> String? {
            if let v = try? c.decodeIfPresent(String.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return String(v) }
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return String(v) }
            return nil
        }
        func decodeInt(_ key: CodingKeys) -> Int? {
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return v ? 1 : 0 }
            if let v = try? c.decodeIfPresent(String.self, forKey: key), let n = Int(v) { return n }
            return nil
        }

        id = decodeString(.id) ?? ""
        text = decodeString(.text)
        filename = decodeString(.filename)
        folder = decodeString(.folder)
        save = decodeString(.save)
        source = decodeString(.source)
        signed = decodeInt(.signed)
        html = decodeString(.html)
    }
}

struct QuickBLPrepareResponse: Decodable, Equatable {
    var ok: Bool
    var exists: Bool?
    var alreadySigned: Bool?
    var id: Int?
    var bl: String?
    var previewURL: String?
    var relatedInvoiceToBL: String?
    var amountHT: String?
    var amountTTC: String?
    var save: String?

    enum CodingKeys: String, CodingKey {
        case ok, exists, id, bl, save
        case alreadySigned = "already_signed"
        case previewURL = "preview_url"
        case relatedInvoiceToBL
        case amountHT = "amount_ht"
        case amountTTC = "amount_ttc"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func decodeString(_ key: CodingKeys) -> String? {
            if let v = try? c.decodeIfPresent(String.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return String(v) }
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return String(v) }
            return nil
        }
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        exists = try? c.decodeIfPresent(Bool.self, forKey: .exists)
        alreadySigned = try? c.decodeIfPresent(Bool.self, forKey: .alreadySigned)
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        bl = decodeString(.bl)
        previewURL = decodeString(.previewURL)
        relatedInvoiceToBL = decodeString(.relatedInvoiceToBL)
        amountHT = decodeString(.amountHT)
        amountTTC = decodeString(.amountTTC)
        save = decodeString(.save)
    }
}

struct QuickTicketPrepareResponse: Decodable, Equatable {
    var ok: Bool
    var ticketID: Int
    var ticketTitle: String?
    var ticketName: String?
    var ticketDescription: String?
    var entityName: String?
    var clientEmail: String?
    var tasks: [QuickTicketTask]
    var followups: [QuickTicketFollowup]

    enum CodingKeys: String, CodingKey {
        case ok, tasks, followups
        case ticketID = "ticket_id"
        case ticketTitle = "ticket_title"
        case ticketName = "ticket_name"
        case ticketDescription = "ticket_description"
        case entityName = "entity_name"
        case clientEmail = "client_email"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        ticketID = try c.decode(Int.self, forKey: .ticketID)
        ticketTitle = try c.decodeIfPresent(String.self, forKey: .ticketTitle)
        ticketName = try c.decodeIfPresent(String.self, forKey: .ticketName)
        ticketDescription = try c.decodeIfPresent(String.self, forKey: .ticketDescription)
        entityName = try c.decodeIfPresent(String.self, forKey: .entityName)
        clientEmail = try c.decodeIfPresent(String.self, forKey: .clientEmail)
        tasks = (try c.decodeIfPresent([QuickTicketTask].self, forKey: .tasks)) ?? []
        followups = (try c.decodeIfPresent([QuickTicketFollowup].self, forKey: .followups)) ?? []
    }
}

struct QuickTicketTask: Decodable, Identifiable, Equatable {
    var id: Int
    var content: String
    var date: String?
    var time: Int?
    var actiontime: Int?
    var author: String?
    var authorLogin: String?
    var isPrivate: Int?

    enum CodingKeys: String, CodingKey {
        case id, content, date, time, actiontime, author
        case authorLogin = "author_login"
        case isPrivate = "is_private"
    }
}

struct QuickTicketFollowup: Decodable, Identifiable, Equatable {
    var id: Int
    var content: String
    var date: String?
    var author: String?
    var authorLogin: String?
    var isPrivate: Int?

    enum CodingKeys: String, CodingKey {
        case id, content, date, author
        case authorLogin = "author_login"
        case isPrivate = "is_private"
    }
}

struct QuickSubmitResponse: Decodable, Equatable {
    var ok: Bool
    var error: String?
    var message: String?
    var id: Int?
    var bl: String?
    var ticketID: Int?
    var filename: String?

    enum CodingKeys: String, CodingKey {
        case ok, error, message, id, bl, filename
        case ticketID = "ticket_id"
    }
}
