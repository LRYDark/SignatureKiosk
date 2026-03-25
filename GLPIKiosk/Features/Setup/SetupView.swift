// GLPIKiosk — SetupView.swift
// Reprend la logique de connexion de APPAPPLE (import JSON sécurisé + manuel),
// adaptée au mode kiosque (borne + PIN admin + polling).

import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

private enum KioskSetupMode {
    case choose
    case imported
    case manual
}

private enum KioskConfigImportError: LocalizedError {
    case invalidJSON
    case missingBaseURL
    case missingAuthMode
    case unsupportedAuthMode(String)
    case missingOAuthClient
    case missingLegacyAppToken
    case missingDecryptionPassword
    case encryptedPayloadMalformed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Fichier de configuration invalide (JSON attendu)."
        case .missingBaseURL:
            return "Le fichier de configuration doit contenir une base URL."
        case .missingAuthMode:
            return "Le fichier de configuration doit contenir la méthode API (V1 ou V2.2)."
        case .unsupportedAuthMode(let value):
            return "Méthode API non supportée dans le fichier : \(value)"
        case .missingOAuthClient:
            return "Configuration V2.2 incomplète : client_id et client_secret sont obligatoires."
        case .missingLegacyAppToken:
            return "Configuration V1 incomplète : app_token est obligatoire."
        case .missingDecryptionPassword:
            return "Ce fichier est chiffré. Renseignez la clé de déchiffrement."
        case .encryptedPayloadMalformed:
            return "Le fichier chiffré est invalide."
        case .decryptionFailed:
            return "Impossible de déchiffrer ce fichier (clé invalide ou fichier corrompu)."
        }
    }
}

struct SetupView: View {
    @EnvironmentObject private var kiosk: KioskState
    private let authService = GLPIAuthService()

    @State private var setupMode: KioskSetupMode = .choose
    @State private var showConfigImporter = false
    @State private var importedConfigName = ""
    @State private var importMessage = ""
    @State private var showDecryptSheet = false
    @State private var decryptPassword = ""
    @State private var decryptError = ""
    @State private var pendingEncryptedConfigURL: URL?

    @State private var baseURL = ""
    @State private var authMode: APIAuthMode = .oauthV22Password
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var username = ""
    @State private var password = ""
    @State private var appToken = ""
    @State private var userToken = ""
    @State private var deviceName = ""
    @State private var deviceSerial = ""
    @State private var adminCode = ""
    @State private var pollIntervalSeconds: Double = 4

    @State private var isConnecting = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "signature")
                            .font(.system(size: 54))
                            .foregroundStyle(KioskTheme.brand)
                        Text("Configuration de la borne")
                            .font(.headline)
                        Text("Même méthode de connexion que APPAPPLE : import JSON sécurisé ou saisie manuelle.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Configuration") {
                    Button {
                        showConfigImporter = true
                    } label: {
                        Label("Importer configuration", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        setupMode = .manual
                        importMessage = ""
                        importedConfigName = ""
                    } label: {
                        Label("Connexion manuelle", systemImage: "slider.horizontal.3")
                    }

                    if !importedConfigName.isEmpty {
                        Text("Fichier importé : \(importedConfigName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !importMessage.isEmpty {
                        Text(importMessage)
                            .font(.footnote)
                            .foregroundStyle(importMessage.lowercased().hasPrefix("erreur") ? .red : .green)
                    }
                }

                if setupMode != .choose {
                    Section("Connexion GLPI") {
                        connectionFields
                    }

                    Section {
                        Button {
                            connect()
                        } label: {
                            HStack {
                                if isConnecting {
                                    ProgressView()
                                }
                                Text(isConnecting ? "Connexion en cours..." : "Connecter la borne")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isConnecting || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let error = errorMsg, !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("GLPI Kiosk")
            .tint(KioskTheme.brand)
            .onAppear {
                loadFromStore()
            }
            .fileImporter(
                isPresented: $showConfigImporter,
                allowedContentTypes: [UTType.json, UTType.data],
                allowsMultipleSelection: false
            ) { result in
                handleConfigImport(result)
            }
            .sheet(isPresented: $showDecryptSheet) {
                decryptSheet
            }
        }
    }

    @ViewBuilder
    private var connectionFields: some View {
        if setupMode == .imported {
            importedConnectionFields
        } else {
            manualConnectionFields
        }
    }

    @ViewBuilder
    private var importedConnectionFields: some View {
        LabeledContent("Base URL") {
            Text(baseURL.isEmpty ? "-" : baseURL)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Méthode API") {
            Text(authMode.label)
                .foregroundStyle(.secondary)
        }

        switch authMode {
        case .oauthV22Password:
            LabeledContent("Client ID") {
                Text(clientID.isEmpty ? "-" : "••••••")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Client Secret") {
                Text(clientSecret.isEmpty ? "-" : "••••••")
                    .foregroundStyle(.secondary)
            }

            TextField("Login GLPI (Signature Rapide OAuth)", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Mot de passe GLPI (requis pour borne OAuth)", text: $password)

            Text("En mode OAuth v2, la borne utilise uniquement la session OAuth. Le mot de passe stocké sert aussi a reconnecter automatiquement la session si le token expire.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .legacyV1UserToken:
            LabeledContent("App-Token") {
                Text(appToken.isEmpty ? "-" : "••••••")
                    .foregroundStyle(.secondary)
            }

            SecureField("Jeton utilisateur (user_token)", text: $userToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Login GLPI (optionnel)", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("La borne peut fonctionner sans utilisateur. Signature Rapide en legacy utilise App-Token + user_token.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

    }

    @ViewBuilder
    private var manualConnectionFields: some View {
        TextField("Base URL GLPI", text: $baseURL)
            .textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        Picker("Méthode API", selection: $authMode) {
            ForEach(APIAuthMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }

        if authMode == .oauthV22Password {
            TextField("Client ID OAuth", text: $clientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Client Secret OAuth", text: $clientSecret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Login GLPI (Signature Rapide OAuth)", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Mot de passe GLPI (requis pour borne OAuth)", text: $password)

            Text("En mode OAuth v2, la borne utilise uniquement OAuth. Le mot de passe est requis pour maintenir la session et reconnecter automatiquement si besoin.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            SecureField("App-Token GLPI", text: $appToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Jeton utilisateur (user_token)", text: $userToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Login GLPI (optionnel)", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("Optionnel pour la borne. Signature Rapide en legacy requiert App-Token + user_token.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

    }

    private func loadFromStore() {
        let current = kiosk.settings
        baseURL = current.baseURL
        authMode = current.authMode
        clientID = current.clientID
        clientSecret = current.clientSecret
        username = current.username
        password = KeychainStore.get(KeychainStore.keyOAuthPassword) ?? ""
        appToken = current.appToken
        userToken = current.userToken
        deviceName = current.deviceName
        deviceSerial = current.deviceSerial
        adminCode = ""
        pollIntervalSeconds = min(30, max(2, current.pollIntervalSeconds))
        if !current.normalizedBaseURL.isEmpty {
            setupMode = .manual
        } else {
            setupMode = .choose
        }
        importedConfigName = ""
        importMessage = ""
        errorMsg = nil
    }

    // MARK: - Connect

    private func connect() {
        errorMsg = nil
        isConnecting = true

        var draft = kiosk.settings
        draft.baseURL      = baseURL
        draft.authMode     = authMode
        draft.clientID     = clientID
        draft.clientSecret = clientSecret
        draft.username     = username
        draft.appToken     = appToken
        draft.userToken    = userToken
        draft.deviceSerial = deviceSerial
        draft.trimAllFields()
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        // Réglages kiosque (nom borne / code admin / polling) non modifiables depuis SetupView.
        // Ils restent pilotés via la page Réglages (admin) ou Intune/MDM.

        Task {
            do {
                let didClearOAuthUser = draft.authMode == .oauthV22Password
                    && draft.username.isEmpty
                    && cleanPassword.isEmpty

                var oauthTokens: OAuthTokens?
                var didAuthenticateOAuthUser = false

                if draft.authMode == .oauthV22Password {
                    guard !draft.clientID.isEmpty, !draft.clientSecret.isEmpty else {
                        throw APIError.httpError(
                            status: 400,
                            message: "En mode OAuth v2, renseignez Client ID et Client Secret."
                        )
                    }
                    guard !draft.username.isEmpty, !cleanPassword.isEmpty else {
                        throw APIError.httpError(
                            status: 400,
                            message: "En mode OAuth v2, renseignez login et mot de passe GLPI pour connecter la borne."
                        )
                    }
                    oauthTokens = try await authService.oauthPasswordLogin(settings: draft, password: cleanPassword)
                    didAuthenticateOAuthUser = true
                }

                let svc = DeviceService(
                    settings: draft,
                    oauthAccessTokenOverride: oauthTokens?.accessToken
                )
                let name = draft.deviceName.isEmpty ? nil : draft.deviceName
                _ = try await svc.checkin(deviceName: name)

                await MainActor.run {
                    if draft.authMode == .legacyV1UserToken {
                        clearOAuthUserSecrets()
                    } else if didAuthenticateOAuthUser, let oauthTokens {
                        persistOAuthUserSecrets(password: cleanPassword, tokens: oauthTokens)
                    } else if didClearOAuthUser {
                        clearOAuthUserSecrets()
                    }
                    kiosk.saveSettings(draft)
                    isConnecting = false
                    kiosk.phase = .idle
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMsg = "Connexion échouée : \(error.localizedDescription)\n\nVérifiez l'URL et que le plugin Gestion est actif."
                }
            }
        }
    }

    // MARK: - Config import (APPAPPLE-style)

    private func handleConfigImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try importConfiguration(from: url, decryptionPassword: nil)
                importMessage = "Configuration importée avec succès."
            } catch KioskConfigImportError.missingDecryptionPassword {
                pendingEncryptedConfigURL = url
                decryptPassword = ""
                decryptError = ""
                showDecryptSheet = true
                importMessage = "Fichier chiffré détecté. Renseignez la clé."
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                importMessage = "Erreur import : \(message)"
            }
        case .failure(let error):
            importMessage = "Erreur import : \(error.localizedDescription)"
        }
    }

    private func importConfiguration(from url: URL, decryptionPassword: String?) throws {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let json = try decodeConfigurationJSON(from: data, decryptionPassword: decryptionPassword)

        let importedBaseURL = lookupString(
            json,
            keys: ["base_url", "baseURL", "glpi_base_url", "GLPI_BASE_URL", "url", "glpi_url"]
        )
        guard !importedBaseURL.isEmpty else {
            throw KioskConfigImportError.missingBaseURL
        }

        let modeRaw = lookupString(
            json,
            keys: ["auth_mode", "authMode", "glpi_auth_mode", "GLPI_AUTH_MODE", "method", "api_method"]
        )
        guard !modeRaw.isEmpty else {
            throw KioskConfigImportError.missingAuthMode
        }
        guard let importedMode = APIAuthMode.parse(modeRaw) else {
            throw KioskConfigImportError.unsupportedAuthMode(modeRaw)
        }

        let importedClientID = lookupString(json, keys: ["client_id", "clientID", "glpi_client_id", "GLPI_CLIENT_ID"])
        let importedClientSecret = lookupString(json, keys: ["client_secret", "clientSecret", "glpi_client_secret", "GLPI_CLIENT_SECRET"])
        let importedAppToken = lookupString(json, keys: ["app_token", "appToken", "glpi_app_token", "GLPI_APP_TOKEN"])
        let importedUserToken = lookupString(json, keys: ["user_token", "userToken", "glpi_user_token", "GLPI_USER_TOKEN"])
        let importedUsername = lookupString(json, keys: ["username_default", "username", "glpi_username_default", "GLPI_USERNAME_DEFAULT"])
        let importedDeviceName = lookupString(json, keys: ["device_name", "deviceName", "glpi_device_name", "GLPI_DEVICE_NAME", "name"])
        let importedDeviceSerial = lookupString(json, keys: ["device_serial", "deviceSerial", "glpi_device_serial", "GLPI_DEVICE_SERIAL", "serial_number", "serial"])
        let importedAdminCode = lookupString(json, keys: ["admin_code", "adminCode", "glpi_admin_code", "GLPI_ADMIN_CODE"])
        let importedPollInterval = lookupDouble(json, keys: ["poll_interval", "pollInterval", "glpi_poll_interval", "GLPI_POLL_INTERVAL"])

        switch importedMode {
        case .oauthV22Password:
            guard !importedClientID.isEmpty, !importedClientSecret.isEmpty else {
                throw KioskConfigImportError.missingOAuthClient
            }
            clientID = importedClientID
            clientSecret = importedClientSecret
            appToken = ""
            userToken = ""
            password = ""
        case .legacyV1UserToken:
            guard !importedAppToken.isEmpty else {
                throw KioskConfigImportError.missingLegacyAppToken
            }
            appToken = importedAppToken
            clientID = ""
            clientSecret = ""
            password = ""
        }

        userToken = importedMode == .legacyV1UserToken ? importedUserToken : ""
        baseURL = importedBaseURL
        authMode = importedMode
        if !importedUsername.isEmpty {
            username = importedUsername
        }
        if !importedDeviceName.isEmpty {
            deviceName = importedDeviceName
        }
        if !importedDeviceSerial.isEmpty {
            deviceSerial = importedDeviceSerial
        }
        if !importedAdminCode.isEmpty {
            adminCode = importedAdminCode
        }
        if let interval = importedPollInterval {
            pollIntervalSeconds = min(30, max(2, interval))
        }

        setupMode = .imported
        importedConfigName = url.lastPathComponent
    }

    private func persistOAuthUserSecrets(password: String, tokens: OAuthTokens) {
        KeychainStore.setCodable(tokens, forKey: KeychainStore.keyOAuthTokens)
        if password.isEmpty {
            KeychainStore.delete(KeychainStore.keyOAuthPassword)
        } else {
            KeychainStore.set(password, forKey: KeychainStore.keyOAuthPassword)
        }
    }

    private func clearOAuthUserSecrets() {
        KeychainStore.delete(KeychainStore.keyOAuthTokens)
        KeychainStore.delete(KeychainStore.keyOAuthPassword)
    }

    private func decodeConfigurationJSON(from data: Data, decryptionPassword: String?) throws -> JSONDict {
        let rawObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = rawObject as? JSONDict else {
            throw KioskConfigImportError.invalidJSON
        }

        guard let format = asString(json["format"])?.lowercased(),
              format == "glpifield_encrypted_v1" else {
            return json
        }

        let cleanPassword = (decryptionPassword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPassword.isEmpty else {
            throw KioskConfigImportError.missingDecryptionPassword
        }

        guard let saltB64 = asString(json["salt"]),
              let nonceB64 = asString(json["nonce"]),
              let cipherB64 = asString(json["ciphertext"]),
              let tagB64 = asString(json["tag"]),
              let salt = Data(base64Encoded: saltB64),
              let nonceData = Data(base64Encoded: nonceB64),
              let ciphertext = Data(base64Encoded: cipherB64),
              let tag = Data(base64Encoded: tagB64) else {
            throw KioskConfigImportError.encryptedPayloadMalformed
        }

        do {
            let key = deriveKey(password: cleanPassword, salt: salt)
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let clearData = try AES.GCM.open(sealed, using: key)

            let clearObject = try JSONSerialization.jsonObject(with: clearData, options: [])
            guard let clearJSON = clearObject as? JSONDict else {
                throw KioskConfigImportError.invalidJSON
            }
            return clearJSON
        } catch {
            throw KioskConfigImportError.decryptionFailed
        }
    }

    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        var material = Data(password.utf8)
        material.append(salt)
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: Data(digest))
    }

    private func lookupString(_ json: JSONDict, keys: [String]) -> String {
        for key in keys {
            if let value = asString(json[key])?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func lookupDouble(_ json: JSONDict, keys: [String]) -> Double? {
        for key in keys {
            if let value = asDouble(json[key]) {
                return value
            }
        }
        return nil
    }


    @ViewBuilder
    private var decryptSheet: some View {
        NavigationStack {
            Form {
                Section("Fichier chiffré") {
                    SecureField("Clé de déchiffrement", text: $decryptPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Importer") {
                        importPendingEncryptedFile()
                    }
                    .disabled(decryptPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !decryptError.isEmpty {
                    Section {
                        Text(decryptError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Déchiffrer config")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        pendingEncryptedConfigURL = nil
                        decryptPassword = ""
                        decryptError = ""
                        showDecryptSheet = false
                    }
                }
            }
        }
    }

    private func importPendingEncryptedFile() {
        guard let url = pendingEncryptedConfigURL else {
            showDecryptSheet = false
            return
        }

        do {
            decryptError = ""
            try importConfiguration(from: url, decryptionPassword: decryptPassword)
            importMessage = "Configuration chiffrée importée avec succès."
            decryptPassword = ""
            pendingEncryptedConfigURL = nil
            decryptError = ""
            showDecryptSheet = false
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            decryptError = "Erreur import : \(message)"
            importMessage = "Erreur import : \(message)"
        }
    }
}
