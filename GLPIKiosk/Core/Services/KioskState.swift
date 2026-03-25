// GLPIKiosk — KioskState.swift
// Machine à états centrale de l'application kiosque.
//
// États :
//   idle          → En attente (écran veille)
//   polling       → Interroge le serveur (silencieux, depuis idle)
//   requestReceived → Affiche la requête de signature reçue
//   signing       → L'utilisateur est en train de signer
//   submitting    → Envoi de la signature au serveur
//   confirmed     → Confirmation de succès (5s puis retour idle)
//   refused       → Refus confirmé (3s puis retour idle)
//   error         → Erreur affichée temporairement (5s puis retour idle)
//   settings      → Écran de configuration (protégé PIN admin)

import Foundation
import Combine
import Network

enum KioskPhase: Equatable {
    case setup              // Premier lancement — URL non configurée
    case idle
    case polling
    case requestReceived(SignatureRequest)
    case signing(SignatureRequest)
    case submitting
    case confirmed
    case refused
    case error(String)
    case settings
}

@MainActor
final class KioskState: ObservableObject {

    // ── État ──────────────────────────────────────────────────────────────────
    @Published var phase:            KioskPhase = .idle
    @Published var isOnline:         Bool       = true
    @Published var adminUnlocked:    Bool       = false
    @Published var pendingRetry:     PendingRetry? = nil
    @Published private(set) var isBootstrapping: Bool = true
    @Published private(set) var bootstrapStatus: String = "Verification de la configuration..."

    // ── Settings ──────────────────────────────────────────────────────────────
    @Published var settings: KioskSettings = KioskSettings()

    // ── Privé ─────────────────────────────────────────────────────────────────
    private var deviceService:   DeviceService?
    private var pollTask:        Task<Void, Never>?
    private var automaticWorkTask: Task<Void, Never>?
    private var networkMonitor:  NWPathMonitor?
    private let monitorQueue     = DispatchQueue(label: "fr.jcd.glpikiosk.network")
    private let authService      = GLPIAuthService()
    private var isAppActive      = true
    private var isIdleScreenSleeping = false

    // ── Retry queue (stockage offline) ───────────────────────────────────────
    struct PendingRetry: Codable {
        var requestId:   Int
        var signerName:  String
        var signerEmail: String
        var signatureB64: String
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        isBootstrapping = true
        bootstrapStatus = "Verification de la configuration..."
        defer {
            isBootstrapping = false
        }

        loadSettings()
        startNetworkMonitor()

        // Si aucune URL configurée → écran de setup obligatoire
        guard !settings.normalizedBaseURL.isEmpty else {
            phase = .setup
            return
        }

        bootstrapStatus = "Verification de la session..."
        await restoreQuickSignAuthenticationIfPossible()

        rebuildDeviceService()
        bootstrapStatus = "Connexion de l'application..."
        phase = .idle
        startPolling()
        await performCheckin()
    }

    // MARK: - Settings

    func loadSettings() {
        // 1. UserDefaults (non-sensibles)
        if let data = UserDefaults.standard.data(forKey: "kiosk.settings"),
           let saved = try? JSONDecoder().decode(KioskSettings.self, from: data) {
            settings = saved
        }

        // 2. Keychain (secrets)
        if let secret = KeychainStore.get(KeychainStore.keyClientSecret) {
            settings.clientSecret = secret
        }
        if let appToken = KeychainStore.get(KeychainStore.keyAppToken) {
            settings.appToken = appToken
        }
        if let token = KeychainStore.get(KeychainStore.keyUserToken) {
            settings.userToken = token
        }
        if let code = KeychainStore.get(KeychainStore.keyAdminCode) {
            settings.adminCode = code
        }

        // 3. MDM override (prioritaire)
        let managed = KioskManagedConfig.load()
        if managed.isActive {
            if let url  = managed.baseURL     { settings.baseURL      = url  }
            if let cid  = managed.clientID    { settings.clientID     = cid  }
            if let sec  = managed.clientSecret { settings.clientSecret = sec  }
            if let usr  = managed.defaultUsername { settings.username = usr }
            if let at   = managed.appToken    { settings.appToken     = at   }
            if let ut   = managed.userToken   { settings.userToken    = ut   }
            if let code = managed.adminCode   { settings.adminCode    = code }
            if let name = managed.deviceName  { settings.deviceName   = name }
            if let serial = managed.deviceSerial { settings.deviceSerial = serial }
            if let mode = managed.authMode    { settings.authMode     = mode }
            if let pi   = managed.pollInterval { settings.pollIntervalSeconds = pi }
        }
    }

    func saveSettings(_ newSettings: KioskSettings) {
        // Séparer sensibles / non-sensibles
        var toStore       = newSettings
        let appToken      = toStore.appToken
        let clientSecret  = toStore.clientSecret
        let userToken     = toStore.userToken
        let adminCode     = toStore.adminCode
        toStore.appToken     = ""
        toStore.clientSecret = ""
        toStore.userToken    = ""
        toStore.adminCode    = ""

        if let data = try? JSONEncoder().encode(toStore) {
            UserDefaults.standard.set(data, forKey: "kiosk.settings")
        }

        KeychainStore.set(appToken,     forKey: KeychainStore.keyAppToken)
        KeychainStore.set(clientSecret, forKey: KeychainStore.keyClientSecret)
        KeychainStore.set(userToken,    forKey: KeychainStore.keyUserToken)
        KeychainStore.set(adminCode,    forKey: KeychainStore.keyAdminCode)

        settings = newSettings
        rebuildDeviceService()
        restartPolling()
        Task { await performCheckin() }
    }

    func setApplicationActive(_ isActive: Bool) {
        guard isAppActive != isActive else { return }
        isAppActive = isActive
        refreshAutomaticNetworking(
            performCheckinOnResume: isActive,
            retryPendingOnResume: isActive
        )
    }

    func setIdleSleepActive(_ isActive: Bool) {
        guard isIdleScreenSleeping != isActive else { return }
        isIdleScreenSleeping = isActive
        refreshAutomaticNetworking(retryPendingOnResume: !isActive)
    }

    // MARK: - Admin

    func unlockAdmin(code: String) -> Bool {
        let expected = settings.adminCode.isEmpty ? "2580" : settings.adminCode
        if code == expected {
            adminUnlocked = true
            return true
        }
        return false
    }

    func lockAdmin() {
        adminUnlocked = false
        if phase == .settings {
            phase = .idle
        }
    }

    /// Efface tous les paramètres et revient à l'écran de setup initial.
    func resetToSetup() {
        pollTask?.cancel()
        pollTask = nil
        automaticWorkTask?.cancel()
        automaticWorkTask = nil

        // Effacer Keychain
        KeychainStore.delete(KeychainStore.keyAppToken)
        KeychainStore.delete(KeychainStore.keyClientSecret)
        KeychainStore.delete(KeychainStore.keyUserToken)
        KeychainStore.delete(KeychainStore.keyOAuthTokens)
        KeychainStore.delete(KeychainStore.keyOAuthPassword)
        KeychainStore.delete(KeychainStore.keyAdminCode)

        // Effacer UserDefaults
        UserDefaults.standard.removeObject(forKey: "kiosk.settings")

        settings      = KioskSettings()
        deviceService = nil
        adminUnlocked = false
        phase         = .setup
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            // Swift 6 : on passe par Task @MainActor plutôt que DispatchQueue.main
            Task { @MainActor [weak self] in
                self?.isOnline = (path.status == .satisfied)
                if path.status == .satisfied {
                    self?.handleNetworkReachable()
                }
            }
        }
        networkMonitor?.start(queue: monitorQueue)
    }

    // MARK: - Polling

    private func startPolling() {
        guard pollTask == nil else { return }
        guard !settings.normalizedBaseURL.isEmpty, isAutomaticNetworkingAllowed else { return }
        pollTask = Task { await pollLoop() }
    }

    private func restartPolling() {
        suspendPolling()
        startPolling()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            // Uniquement si en mode idle
            if case .idle = phase, isOnline, isAutomaticNetworkingAllowed {
                await pollOnce()
            }
            let interval = settings.pollIntervalSeconds
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func pollOnce() async {
        guard let svc = deviceService else { return }
        do {
            let resp = try await svc.poll()
            if resp.pending, let req = resp.asSignatureRequest {
                phase = .requestReceived(req)
            }
        } catch is CancellationError {
            return
        } catch APIError.rateLimited {
            // Doubler l'intervalle temporairement
            try? await Task.sleep(nanoseconds: UInt64(settings.pollIntervalSeconds * 2_000_000_000))
        } catch APIError.deviceBanned {
            phase = .error("Appareil banni — contactez l'administrateur.")
        } catch APIError.remoteSignatureDisabled {
            // Feature flag désactivé — on backoff plus long
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        } catch {
            // Erreurs réseau silencieuses (tablette peut être offline momentanément)
            DebugLogger.warn("Poll error: \(error.localizedDescription)")
        }
    }

    // MARK: - Checkin

    func performCheckin() async {
        guard !Task.isCancelled else { return }
        guard let svc = deviceService, !settings.normalizedBaseURL.isEmpty else { return }
        let name = settings.deviceName.isEmpty ? nil : settings.deviceName
        do {
            _ = try await svc.checkin(deviceName: name)
        } catch is CancellationError {
            return
        } catch {
            DebugLogger.warn("Checkin error: \(error.localizedDescription)")
        }
    }

    private func restoreQuickSignAuthenticationIfPossible() async {
        switch settings.authMode {
        case .legacyV1UserToken:
            bootstrapStatus = "Chargement des identifiants legacy..."
            return

        case .oauthV22Password:
            if let tokens = KeychainStore.getCodable(OAuthTokens.self, forKey: KeychainStore.keyOAuthTokens),
               !tokens.accessToken.isEmpty,
               !tokens.isExpired {
                bootstrapStatus = "Session OAuth restauree."
                return
            }

            let password = (KeychainStore.get(KeychainStore.keyOAuthPassword) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let username = settings.username.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientID = settings.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientSecret = settings.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !password.isEmpty, !username.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty else {
                bootstrapStatus = "Aucune session OAuth complete a restaurer."
                return
            }

            bootstrapStatus = "Reconnexion automatique OAuth..."

            do {
                let tokens = try await authService.oauthPasswordLogin(settings: settings, password: password)
                KeychainStore.setCodable(tokens, forKey: KeychainStore.keyOAuthTokens)
                DebugLogger.log("Auth", "Session OAuth restauree automatiquement au lancement.")
            } catch {
                KeychainStore.delete(KeychainStore.keyOAuthTokens)
                DebugLogger.warn("Auth", "Reconnexion OAuth auto impossible: \(error.localizedDescription)")
                bootstrapStatus = "Session OAuth indisponible, poursuite du demarrage."
            }
        }
    }

    // MARK: - Submit

    func submit(
        request:     SignatureRequest,
        signerName:  String,
        signerEmail: String,
        signatureB64: String
    ) async {
        guard let svc = deviceService else { return }
        phase = .submitting

        do {
            let resp = try await svc.submit(
                requestId:    request.id,
                signerName:   signerName,
                signerEmail:  signerEmail,
                signatureB64: signatureB64
            )
            if resp.ok {
                pendingRetry = nil
                phase        = .confirmed
                // Retour idle après 5 secondes
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .confirmed = phase { phase = .idle }
            } else {
                showError("Erreur serveur lors de l'envoi de la signature.")
            }
        } catch {
            // Stocker pour retry offline
            pendingRetry = PendingRetry(
                requestId:    request.id,
                signerName:   signerName,
                signerEmail:  signerEmail,
                signatureB64: signatureB64
            )
            showError("Envoi échoué — sera réessayé automatiquement.")
        }
    }

    // MARK: - Refuse

    func refuse(request: SignatureRequest) async {
        guard let svc = deviceService else { return }
        do {
            _ = try await svc.refuse(requestId: request.id)
        } catch {
            DebugLogger.warn("Refuse error: \(error.localizedDescription)")
        }
        phase = .refused
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if case .refused = phase { phase = .idle }
    }

    // MARK: - Retry

    private func retryPendingSubmit() async {
        guard isAutomaticNetworkingAllowed, !Task.isCancelled else { return }
        guard let retry = pendingRetry, let svc = deviceService else { return }

        // Retry 3× avec backoff exponentiel
        for attempt in 1...3 {
            guard isAutomaticNetworkingAllowed, !Task.isCancelled else { return }
            do {
                let resp = try await svc.submit(
                    requestId:    retry.requestId,
                    signerName:   retry.signerName,
                    signerEmail:  retry.signerEmail,
                    signatureB64: retry.signatureB64
                )
                if resp.ok {
                    pendingRetry = nil
                    phase        = .confirmed
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if case .confirmed = phase { phase = .idle }
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                guard isAutomaticNetworkingAllowed, !Task.isCancelled else { return }
                let delay: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    // MARK: - Helpers

    private func rebuildDeviceService() {
        deviceService = DeviceService(settings: settings)
    }

    private func showError(_ message: String) {
        phase = .error(message)
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if case .error(_) = phase { phase = .idle }
        }
    }

    private var isAutomaticNetworkingAllowed: Bool {
        isAppActive && !isIdleScreenSleeping
    }

    private func suspendPolling() {
        pollTask?.cancel()
        pollTask = nil
        automaticWorkTask?.cancel()
        automaticWorkTask = nil
    }

    private func refreshAutomaticNetworking(
        performCheckinOnResume: Bool = false,
        retryPendingOnResume: Bool = false
    ) {
        guard isAutomaticNetworkingAllowed else {
            suspendPolling()
            return
        }

        restartPolling()
        scheduleAutomaticWork(
            performCheckin: performCheckinOnResume,
            retryPending: retryPendingOnResume && isOnline
        )
    }

    private func handleNetworkReachable() {
        guard isAutomaticNetworkingAllowed else { return }
        restartPolling()
        scheduleAutomaticWork(retryPending: true)
    }

    private func scheduleAutomaticWork(
        performCheckin: Bool = false,
        retryPending: Bool = false
    ) {
        automaticWorkTask?.cancel()
        automaticWorkTask = nil

        guard performCheckin || retryPending else { return }

        automaticWorkTask = Task { [weak self] in
            guard let self else { return }
            guard self.isAutomaticNetworkingAllowed, !Task.isCancelled else { return }

            if performCheckin {
                await self.performCheckin()
            }

            guard self.isAutomaticNetworkingAllowed, !Task.isCancelled else { return }

            if retryPending {
                await self.retryPendingSubmit()
            }
        }
    }
}
