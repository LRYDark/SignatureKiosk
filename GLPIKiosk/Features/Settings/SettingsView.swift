// GLPIKiosk — SettingsView.swift
// Modal de réglages aligné sur APPAPPLE (accès admin + debug + config API),
// avec sections kiosque conservées (borne, polling, reset).

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var kiosk: KioskState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var debugStore = DebugLogger.shared

    private let authService = GLPIAuthService()

    @State private var draft = KioskSettings()

    @State private var adminCodeInput = ""
    @State private var newAdminCode = ""
    @State private var adminMessage = ""

    @State private var debugEnabled = DebugLogger.isEnabled
    @State private var isCheckingIn = false
    @State private var checkinStatus: String?
    @State private var configMessage = ""
    @State private var quickSignUserPassword = ""
    @State private var userAuthStatus: String?
    @State private var isAuthenticatingUser = false

    @State private var showResetAlert = false

    private var managed: KioskManagedConfig { KioskManagedConfig.load() }
    private var isAdmin: Bool { kiosk.adminUnlocked }

    private var appVersionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Application \(v) (\(b))"
    }

    private var privacyPolicyURL: URL? {
        guard let raw = Bundle.main.infoDictionary?["PrivacyPolicyURL"] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var kioskPhaseLabel: String {
        String(describing: kiosk.phase).components(separatedBy: "(").first ?? ""
    }

    private var oauthTokenStatusSummary: String {
        guard let tokens = KeychainStore.getCodable(OAuthTokens.self, forKey: KeychainStore.keyOAuthTokens),
              !tokens.accessToken.isEmpty else {
            return "Aucun token OAuth utilisateur en mémoire."
        }
        if tokens.isExpired {
            return "Token OAuth expiré (reconnexion automatique tentée si login/mdp sont stockés)."
        }
        if let exp = tokens.expiresAt {
            let fmt = DateFormatter()
            fmt.dateFormat = "dd/MM HH:mm"
            return "Token OAuth actif jusqu'au \(fmt.string(from: exp))."
        }
        return "Token OAuth actif."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Borne kiosque") {
                    LabeledContent("N° de série") {
                        Text(DeviceService.resolvedDeviceSerial(settings: kiosk.settings))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("URL active") {
                        Text(kiosk.settings.normalizedBaseURL.isEmpty ? "Non configurée" : kiosk.settings.normalizedBaseURL)
                            .font(.caption)
                            .foregroundStyle(kiosk.settings.normalizedBaseURL.isEmpty ? .red : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    LabeledContent("Nom") {
                        Text(DeviceService.resolvedDeviceName(settings: kiosk.settings))
                            .foregroundStyle(.secondary)
                    }
                }

                if managed.isActive {
                    Section("Configuration Intune/MDM") {
                        Text("Paramètres déployés automatiquement détectés.")
                        Text(managed.lockAPIConfig
                             ? "Config API verrouillée tant que le code admin n'est pas valide."
                             : "Config API modifiable si le mode admin est déverrouillé.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Accès admin") {
                    if isAdmin {
                        Label("Mode admin actif", systemImage: "lock.open")
                            .foregroundStyle(.green)

                        Button("Reverrouiller") {
                            kiosk.lockAdmin()
                            adminMessage = "Mode admin verrouillé."
                            adminCodeInput = ""
                        }

                        if managed.adminCode == nil {
                            SecureField("Nouveau code admin (4+)", text: $newAdminCode)
                                .keyboardType(.numberPad)

                            Button("Changer le code admin") {
                                let cleaned = newAdminCode.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard cleaned.count >= 4 else {
                                    adminMessage = "Le code admin doit contenir au moins 4 caractères."
                                    return
                                }
                                draft.adminCode = cleaned
                                kiosk.saveSettings(draft)
                                draft = kiosk.settings
                                adminMessage = "Code admin mis à jour."
                                configMessage = ""
                                newAdminCode = ""
                            }
                        } else {
                            Text("Code admin piloté par Intune/MDM")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        SecureField("Code admin", text: $adminCodeInput)
                            .keyboardType(.numberPad)

                        Button("Déverrouiller") {
                            let ok = kiosk.unlockAdmin(code: adminCodeInput)
                            adminMessage = ok ? "Mode admin déverrouillé." : "Code admin invalide."
                            adminCodeInput = ""
                        }
                    }

                    if !adminMessage.isEmpty {
                        Text(adminMessage)
                            .font(.footnote)
                            .foregroundStyle(adminMessage.lowercased().contains("invalide")
                                             || adminMessage.lowercased().contains("au moins")
                                             ? .red : .green)
                    }
                }

                if isAdmin {
                    Section("Debug") {
                        Toggle("Mode debug", isOn: $debugEnabled)

                        Button {
                            doCheckin()
                        } label: {
                            HStack {
                                if isCheckingIn {
                                    ProgressView().controlSize(.small)
                                }
                                Text(isCheckingIn ? "Checkin en cours..." : "Forcer un checkin")
                            }
                        }
                        .disabled(isCheckingIn || kiosk.settings.normalizedBaseURL.isEmpty)

                        if let status = checkinStatus {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(status.hasPrefix("OK") ? .green : .red)
                        }

                        if debugEnabled {
                            NavigationLink {
                                DebugLogsViewerView(
                                    debugStore: debugStore,
                                    exportDataProvider: { try? makeDebugLogsExportData() }
                                )
                            } label: {
                                Label("Voir les logs", systemImage: "doc.text.magnifyingglass")
                            }
                        }

                    }

                    Section("Configuration API GLPI (admin)") {
                        TextField("Base URL", text: $draft.baseURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(managed.lockAPIConfig)

                        Picker("Méthode API", selection: $draft.authMode) {
                            ForEach(APIAuthMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .disabled(managed.lockAPIConfig)

                        if draft.authMode == .oauthV22Password {
                            TextField("Client ID", text: $draft.clientID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(managed.lockAPIConfig)

                            SecureField("Client Secret", text: $draft.clientSecret)
                                .disabled(managed.lockAPIConfig)
                        } else {
                            SecureField("App-Token", text: $draft.appToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(managed.lockAPIConfig)

                            SecureField("Jeton utilisateur (user_token)", text: $draft.userToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(managed.lockAPIConfig)
                        }

                        Text("Endpoint auth : \(resolvedEndpoint())")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if managed.lockAPIConfig {
                            Text("Configuration API verrouillée par Intune/MDM.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Mode admin : modification API autorisée.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Utilisateur Signature Rapide (admin)") {
                        if draft.authMode == .oauthV22Password {
                            TextField("Login GLPI (OAuth)", text: $draft.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            SecureField("Mot de passe GLPI (OAuth)", text: $quickSignUserPassword)

                            Text(oauthTokenStatusSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Button {
                                reconnectQuickSignUser()
                            } label: {
                                HStack {
                                    if isAuthenticatingUser {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(isAuthenticatingUser ? "Connexion en cours..." : "Connecter / reconnecter l'utilisateur OAuth")
                                }
                            }
                            .disabled(isAuthenticatingUser)

                            Button("Déconnecter l'utilisateur OAuth", role: .destructive) {
                                KeychainStore.delete(KeychainStore.keyOAuthTokens)
                                KeychainStore.delete(KeychainStore.keyOAuthPassword)
                                quickSignUserPassword = ""
                                userAuthStatus = "Utilisateur OAuth déconnecté sur la tablette."
                            }
                            .disabled(isAuthenticatingUser)

                            Text("Le login est enregistré avec la configuration. Le mot de passe OAuth est stocké en Keychain pour reconnecter automatiquement la session OAuth de la borne et de Signature Rapide.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Mode Legacy v1 : App-Token et user_token sont conservés sur la tablette (Keychain) et utilisés directement pour Signature Rapide.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Button {
                                reconnectQuickSignUser()
                            } label: {
                                HStack {
                                    if isAuthenticatingUser {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(isAuthenticatingUser ? "Test en cours..." : "Tester App-Token + user_token")
                                }
                            }
                            .disabled(isAuthenticatingUser)
                        }

                        if let userAuthStatus {
                            Text(userAuthStatus)
                                .font(.footnote)
                                .foregroundStyle(userAuthStatus.lowercased().hasPrefix("erreur") ? .red : .green)
                        }
                    }

                    Section("Borne (admin)") {
                        TextField("Nom de la borne", text: $draft.deviceName)
                            .autocorrectionDisabled()
                            .disabled(managed.deviceName != nil)

                        if managed.deviceName != nil {
                            Text("Nom de la borne piloté par Intune/MDM.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if draft.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Si vide, le nom de l'iPad est utilisé automatiquement.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        TextField("N° de série (override)", text: $draft.deviceSerial)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(managed.deviceSerial != nil)

                        if managed.deviceSerial != nil {
                            Text("N° de série piloté par Intune/MDM.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Optionnel : utilisé pour X-Device-Serial. Si vide, fallback iOS (UUID identifierForVendor).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Stepper(
                            "Intervalle de polling : \(Int(draft.pollIntervalSeconds))s",
                            value: $draft.pollIntervalSeconds,
                            in: 2...30,
                            step: 1
                        )
                        .disabled(managed.pollInterval != nil)

                        if managed.pollInterval != nil {
                            Text("Polling piloté par Intune/MDM.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Veille écran (idle)")
                            Picker("Veille écran (idle)", selection: $draft.softSleepDelayMinutes) {
                                Text("2 min").tag(2)
                                Text("5 min").tag(5)
                                Text("10 min").tag(10)
                                Text("15 min").tag(15)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        Text("Après ce délai sans interaction, l'écran d'attente passe en fond noir avec le logo et \"Borne de signature\". Un tap réveille l'écran.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Enregistrer la configuration") {
                        saveConfiguration()
                    }

                    if !configMessage.isEmpty {
                        Text(configMessage)
                            .font(.footnote)
                            .foregroundStyle(configMessage.lowercased().hasPrefix("erreur") ? .red : .green)
                    }
                }

                if isAdmin {
                    Section("Endpoints utiles") {
                        if draft.authMode == .oauthV22Password {
                            Text("/api.php/v2.2/token")
                        } else {
                            Text("/api.php/v1/initSession")
                        }
                        Text("/plugins/gestion/public/api/device_checkin.php")
                        Text("/plugins/gestion/public/api/device_poll_v2.php")
                        Text("/plugins/gestion/public/api/device_submit_v2.php")
                        Text("/plugins/gestion/public/api/device_direct_sign.php")
                    }

                    Section {
                        Button("Réinitialiser et déconnecter la borne", role: .destructive) {
                            showResetAlert = true
                        }
                    } header: {
                        Text("Zone dangereuse")
                    } footer: {
                        Text("Efface l'URL, les identifiants et le code admin. L'assistant de configuration sera réaffiché.")
                    }
                }

                Section("Version") {
                    Text(appVersionLabel)
                }

                Section("Confidentialité") {
                    if let privacyPolicyURL {
                        Link(destination: privacyPolicyURL) {
                            Label("Politique de confidentialité", systemImage: "hand.raised.fill")
                        }
                    } else {
                        Text("URL de politique de confidentialité à renseigner dans Info.plist avant publication App Store.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") {
                        closeSettings()
                    }
                }
            }
            .onAppear {
                draft = kiosk.settings
                debugEnabled = DebugLogger.isEnabled
                quickSignUserPassword = KeychainStore.get(KeychainStore.keyOAuthPassword) ?? ""
                configMessage = ""
                userAuthStatus = nil
            }
            .onChange(of: debugEnabled) { _, newValue in
                DebugLogger.isEnabled = newValue
            }
            .onChange(of: draft.authMode) { _, _ in
                userAuthStatus = nil
            }
            .alert("Réinitialiser la borne ?", isPresented: $showResetAlert) {
                Button("Réinitialiser", role: .destructive) {
                    kiosk.resetToSetup()
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Tous les paramètres seront effacés. Cette action est irréversible.")
            }
        }
        .debugBar(if: kiosk.phase != .settings)
    }

    // MARK: - Helpers

    private func closeSettings() {
        if kiosk.phase == .settings {
            kiosk.phase = .idle
            return
        }
        dismiss()
    }

    private func saveConfiguration() {
        let previous = kiosk.settings
        let previousAPI = APIConfigurationSnapshot(settings: previous)

        draft.trimAllFields()
        draft.pollIntervalSeconds = min(30, max(2, draft.pollIntervalSeconds))
        if ![2, 5, 10, 15].contains(draft.softSleepDelayMinutes) {
            draft.softSleepDelayMinutes = 5
        }

        let cleanOAuthPassword = quickSignUserPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.authMode == .oauthV22Password {
            if cleanOAuthPassword.isEmpty {
                KeychainStore.delete(KeychainStore.keyOAuthPassword)
            } else {
                KeychainStore.set(cleanOAuthPassword, forKey: KeychainStore.keyOAuthPassword)
            }
        } else {
            KeychainStore.delete(KeychainStore.keyOAuthTokens)
            KeychainStore.delete(KeychainStore.keyOAuthPassword)
        }

        kiosk.saveSettings(draft)
        draft = kiosk.settings

        let newAPI = APIConfigurationSnapshot(settings: kiosk.settings)

        if previousAPI != newAPI {
            KeychainStore.delete(KeychainStore.keyOAuthTokens)
        }

        if previousAPI != newAPI {
            configMessage = "Configuration enregistrée. Polling et checkin relancés."
        } else {
            configMessage = "Réglages enregistrés."
        }
        checkinStatus = nil
    }

    private func reconnectQuickSignUser() {
        userAuthStatus = nil
        isAuthenticatingUser = true

        var authDraft = draft
        authDraft.trimAllFields()
        let cleanPassword = quickSignUserPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                switch authDraft.authMode {
                case .oauthV22Password:
                    guard !authDraft.normalizedBaseURL.isEmpty else {
                        throw APIError.httpError(status: 400, message: "Base URL manquante.")
                    }
                    guard !authDraft.clientID.isEmpty, !authDraft.clientSecret.isEmpty else {
                        throw APIError.httpError(status: 400, message: "Client ID / Client Secret OAuth manquants.")
                    }
                    guard !authDraft.username.isEmpty else {
                        throw APIError.httpError(status: 400, message: "Login OAuth manquant.")
                    }
                    guard !cleanPassword.isEmpty else {
                        throw APIError.httpError(status: 400, message: "Mot de passe OAuth manquant.")
                    }

                    let tokens = try await authService.oauthPasswordLogin(settings: authDraft, password: cleanPassword)
                    KeychainStore.setCodable(tokens, forKey: KeychainStore.keyOAuthTokens)
                    KeychainStore.set(cleanPassword, forKey: KeychainStore.keyOAuthPassword)

                    await MainActor.run {
                        isAuthenticatingUser = false
                        userAuthStatus = "Utilisateur OAuth connecté. Token enregistré sur la tablette."
                    }

                case .legacyV1UserToken:
                    guard !authDraft.normalizedBaseURL.isEmpty else {
                        throw APIError.httpError(status: 400, message: "Base URL manquante.")
                    }
                    guard !authDraft.appToken.isEmpty else {
                        throw APIError.httpError(status: 400, message: "App-Token manquant.")
                    }
                    guard !authDraft.userToken.isEmpty else {
                        throw APIError.httpError(status: 400, message: "user_token manquant.")
                    }

                    _ = try await authService.legacyInitSession(settings: authDraft)
                    await MainActor.run {
                        isAuthenticatingUser = false
                        userAuthStatus = "App-Token + user_token valides (session GLPI OK)."
                    }
                }
            } catch {
                await MainActor.run {
                    isAuthenticatingUser = false
                    userAuthStatus = "Erreur : \(error.localizedDescription)"
                }
            }
        }
    }

    private func doCheckin() {
        isCheckingIn = true
        checkinStatus = nil
        Task {
            do {
                let name = kiosk.settings.deviceName.isEmpty ? nil : kiosk.settings.deviceName
                _ = try await DeviceService(settings: kiosk.settings).checkin(deviceName: name)
                await MainActor.run {
                    isCheckingIn = false
                    checkinStatus = "OK — checkin réussi"
                }
            } catch {
                await MainActor.run {
                    isCheckingIn = false
                    checkinStatus = "Erreur : \(error.localizedDescription)"
                }
            }
        }
    }

    private func makeDebugLogsExportData() throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let payload = DebugLogsExportPayload(
            exportedAt: formatter.string(from: Date()),
            appVersion: appVersionLabel,
            phase: kioskPhaseLabel,
            baseURL: kiosk.settings.normalizedBaseURL,
            authMode: kiosk.settings.authMode.label,
            deviceName: DeviceService.resolvedDeviceName(settings: kiosk.settings),
            deviceSerial: DeviceService.resolvedDeviceSerial(settings: kiosk.settings),
            pollingSeconds: Int(kiosk.settings.pollIntervalSeconds),
            softSleepDelayMinutes: kiosk.settings.softSleepDelayMinutes,
            debugEnabled: debugEnabled,
            entries: debugStore.entries.map {
                DebugLogsExportEntry(
                    timestamp: formatter.string(from: $0.timestamp),
                    level: $0.level,
                    category: $0.category,
                    message: $0.message,
                    durationS: $0.duration
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private func resolvedEndpoint() -> String {
        let base = draft.normalizedBaseURL
        guard !base.isEmpty else { return draft.authMode.tokenPath }
        return base + draft.authMode.tokenPath
    }
}

private struct APIConfigurationSnapshot: Equatable {
    let baseURL: String
    let authModeRawValue: String
    let clientID: String
    let clientSecret: String
    let username: String
    let appToken: String
    let userToken: String

    init(settings: KioskSettings) {
        self.baseURL = settings.normalizedBaseURL
        self.authModeRawValue = settings.authMode.rawValue
        self.clientID = settings.clientID
        self.clientSecret = settings.clientSecret
        self.username = settings.username
        self.appToken = settings.appToken
        self.userToken = settings.userToken
    }
}

private struct DebugLogsExportPayload: Encodable {
    let exportedAt: String
    let appVersion: String
    let phase: String
    let baseURL: String
    let authMode: String
    let deviceName: String
    let deviceSerial: String
    let pollingSeconds: Int
    let softSleepDelayMinutes: Int
    let debugEnabled: Bool
    let entries: [DebugLogsExportEntry]
}

private struct DebugLogsExportEntry: Encodable {
    let timestamp: String
    let level: String
    let category: String
    let message: String
    let durationS: TimeInterval?
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DebugLogsViewerView: View {
    @ObservedObject var debugStore: DebugLogStore
    let exportDataProvider: () -> Data?

    @State private var filterCategory = "Tous"
    @State private var showShareSheet = false
    @State private var exportURL: URL?

    private var categories: [String] {
        var cats = Set(debugStore.entries.map(\.category))
        cats.insert("Tous")
        cats.insert("Erreurs")
        return ["Tous", "Erreurs"] + cats.subtracting(["Tous", "Erreurs"]).sorted()
    }

    private var filteredEntries: [DebugLogEntry] {
        switch filterCategory {
        case "Tous":
            return debugStore.entries
        case "Erreurs":
            return debugStore.entries.filter { $0.isError }
        default:
            return debugStore.entries.filter { $0.category == filterCategory }
        }
    }

    private var errorCount: Int {
        debugStore.entries.filter { $0.isError }.count
    }

    private var notFoundCount: Int {
        debugStore.entries.filter {
            let lower = $0.message.lowercased()
            return lower.contains("404") || lower.contains("not found")
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            if !debugStore.entries.isEmpty {
                HStack(spacing: 12) {
                    statBadge("\(debugStore.entries.count) total", color: .secondary)
                    if errorCount > 0 {
                        statBadge("\(errorCount) erreurs", color: .red)
                    }
                    if notFoundCount > 0 {
                        statBadge("\(notFoundCount) x 404", color: .orange)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .systemGroupedBackground))
            }

            if debugStore.entries.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                filterCategory = cat
                            } label: {
                                Text(cat)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(filterCategory == cat ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                    .foregroundStyle(filterCategory == cat ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            List {
                if filteredEntries.isEmpty {
                    Text("Aucun log. Activez le mode debug puis reproduisez le flux.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.formattedTime)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(entry.category)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(categoryColor(entry.category).opacity(0.15))
                                    .clipShape(Capsule())
                                if let duration = entry.duration {
                                    Text(String(format: "%.1fs", duration))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(duration > 5 ? .red : duration > 2 ? .orange : .green)
                                }
                            }
                            Text(entry.message)
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.isError ? .red : .primary)
                                .textSelection(.enabled)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Debug Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    exportLogs()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(debugStore.entries.isEmpty)

                Button {
                    debugStore.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(debugStore.entries.isEmpty)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                ActivityShareSheet(items: [exportURL])
            }
        }
    }

    @ViewBuilder
    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "HTTP":
            return .blue
        case "Planning":
            return .orange
        case "BL":
            return .pink
        default:
            return .secondary
        }
    }

    private func exportLogs() {
        guard let data = exportDataProvider() else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "glpikiosk-debug_\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
            showShareSheet = true
        } catch {
            // silent
        }
    }
}
