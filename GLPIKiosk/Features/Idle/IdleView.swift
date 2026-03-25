// GLPIKiosk — IdleView.swift
// Écran de veille affiché quand aucune requête n'est en attente.
// Appui long (5s) en haut-à-droite → accès paramètres (PIN admin).

import SwiftUI
import UIKit

struct IdleView: View {
    @EnvironmentObject private var kiosk: KioskState
    @State private var showSettings      = false
    @State private var showDirectSignBL  = false
    @State private var showDirectSignTkt = false
    @State private var isSoftSleeping    = false
    @State private var softSleepTask: Task<Void, Never>? = nil

    private var softSleepDelayNanos: UInt64 {
        let minutes = min(60, max(1, kiosk.settings.softSleepDelayMinutes))
        return UInt64(minutes) * 60 * 1_000_000_000
    }

    private var isQuickSignAuthConfigured: Bool {
        switch kiosk.settings.authMode {
        case .legacyV1UserToken:
            let appToken = kiosk.settings.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let userToken = kiosk.settings.userToken.trimmingCharacters(in: .whitespacesAndNewlines)
            return !appToken.isEmpty && !userToken.isEmpty
        case .oauthV22Password:
            if let tokens = KeychainStore.getCodable(OAuthTokens.self, forKey: KeychainStore.keyOAuthTokens),
               !tokens.accessToken.isEmpty,
               !tokens.isExpired {
                return true
            }
            let oauthPassword = (KeychainStore.get(KeychainStore.keyOAuthPassword) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let username = kiosk.settings.username.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientID = kiosk.settings.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientSecret = kiosk.settings.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            return !oauthPassword.isEmpty && !username.isEmpty && !clientID.isEmpty && !clientSecret.isEmpty
        }
    }

    var body: some View {
        ZStack {
            KioskTheme.background.ignoresSafeArea()

            // Contenu central
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "signature")
                    .font(.system(size: 80))
                    .foregroundStyle(KioskTheme.brand)

                Spacer().frame(height: 24)

                VStack(spacing: 8) {
                    Text("Borne de signature")
                        .font(.largeTitle.weight(.bold))

                    Text("En attente d'une demande de signature…")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer().frame(height: 24)

                // Indicateur de polling
                PulsingDot()

                Spacer()

                // ── Boutons Signature Rapide ──────────────────────────────────
                VStack(spacing: 14) {
                    HStack(spacing: 16) {
                        // BL
                        Button {
                            showDirectSignBL = true
                        } label: {
                            Label("Signature Rapide BL", systemImage: "shippingbox.fill")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(KioskTheme.brand)
                        .disabled(!isQuickSignAuthConfigured)

                        // Ticket
                        Button {
                            showDirectSignTkt = true
                        } label: {
                            Label("Signature Rapide Ticket", systemImage: "ticket.fill")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                        }
                        .buttonStyle(.bordered)
                        .tint(KioskTheme.brand)
                        .disabled(!isQuickSignAuthConfigured)
                    }
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 700)

                    if !isQuickSignAuthConfigured {
                        Text("La borne kiosque fonctionne sans utilisateur. Les boutons Signature Rapide nécessitent un utilisateur GLPI (OAuth déjà connecté ou mode Legacy v1 avec App-Token + user_token).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 700)
                            .padding(.horizontal, 40)
                    }

                    // Pied de page discret
                    Text("GLPI Kiosk")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                HStack {
                    BatteryStatusBadge()
                        .padding(.leading, 20)
                        .padding(.top, 20)

                    Spacer()

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(KioskTheme.brand.opacity(0.5))
                            .padding(20)
                    }
                }
                Spacer()
            }

            if isSoftSleeping {
                SoftSleepOverlay {
                    registerActivity()
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    if !isSoftSleeping {
                        registerActivity()
                    }
                }
        )
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            kiosk.setIdleSleepActive(false)
            registerActivity()
        }
        .onDisappear {
            cancelSoftSleepTimer()
            isSoftSleeping = false
            kiosk.setIdleSleepActive(false)
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        .onChange(of: isSoftSleeping) { _, newValue in
            kiosk.setIdleSleepActive(newValue)
        }
        .onChange(of: showSettings) { _, _ in
            handleSheetPresentationChanged()
        }
        .onChange(of: showDirectSignBL) { _, _ in
            handleSheetPresentationChanged()
        }
        .onChange(of: showDirectSignTkt) { _, _ in
            handleSheetPresentationChanged()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(kiosk)
        }
        .sheet(isPresented: $showDirectSignBL) {
            QuickSignFlowView(type: .bl)
                .environmentObject(kiosk)
        }
        .sheet(isPresented: $showDirectSignTkt) {
            QuickSignFlowView(type: .ticket)
                .environmentObject(kiosk)
        }
    }

    private var isPresentingSheet: Bool {
        showSettings || showDirectSignBL || showDirectSignTkt
    }

    private func handleSheetPresentationChanged() {
        if isPresentingSheet {
            cancelSoftSleepTimer()
            isSoftSleeping = false
        } else {
            registerActivity()
        }
    }

    private func registerActivity() {
        if isSoftSleeping {
            withAnimation(.easeOut(duration: 0.2)) {
                isSoftSleeping = false
            }
        }
        restartSoftSleepTimer()
    }

    private func restartSoftSleepTimer() {
        cancelSoftSleepTimer()
        guard !isPresentingSheet else { return }

        softSleepTask = Task {
            try? await Task.sleep(nanoseconds: softSleepDelayNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !isPresentingSheet else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSoftSleeping = true
                }
            }
        }
    }

    private func cancelSoftSleepTimer() {
        softSleepTask?.cancel()
        softSleepTask = nil
    }
}

// MARK: - Pulsing dot (indicateur de polling)

struct PulsingDot: View {
    var color: Color = KioskTheme.brand.opacity(0.5)
    @State private var scale: CGFloat = 1

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 1.6
                }
            }
    }
}

private enum BatteryStatusBadgeStyle {
    case regular
    case sleepOverlay
}

private struct BatteryStatusBadge: View {
    var style: BatteryStatusBadgeStyle = .regular

    @State private var batteryLevel: Float = UIDevice.current.batteryLevel
    @State private var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var percentageText: String {
        guard batteryLevel >= 0 else { return "--%" }
        return "\(Int((batteryLevel * 100).rounded()))%"
    }

    private var iconName: String {
        if batteryState == .charging || batteryState == .full {
            return "battery.100"
        }

        switch batteryLevel {
        case ..<0:
            return "battery.0"
        case ..<0.25:
            return "battery.25"
        case ..<0.50:
            return "battery.50"
        case ..<0.75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private var textColor: Color {
        style == .sleepOverlay ? .white : .black
    }

    private var iconColor: Color {
        if batteryLevel >= 0, batteryLevel <= 0.20 {
            return KioskTheme.danger
        }
        return style == .sleepOverlay ? .white : .black
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(percentageText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(textColor)

            if batteryState == .charging {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(style == .sleepOverlay ? .white : KioskTheme.success)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            refreshBatteryStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            refreshBatteryStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            refreshBatteryStatus()
        }
        .onReceive(refreshTimer) { _ in
            refreshBatteryStatus()
        }
        .accessibilityLabel("Batterie \(percentageText)")
    }

    private func refreshBatteryStatus() {
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
    }
}

private struct SoftSleepOverlay: View {
    let onWake: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                HStack {
                    BatteryStatusBadge(style: .sleepOverlay)
                        .padding(.leading, 20)
                        .padding(.top, 20)

                    Spacer()
                }

                Spacer()
            }

            VStack(spacing: 18) {
                Image(systemName: "signature")
                    .font(.system(size: 72))
                    .foregroundStyle(.white.opacity(0.95))

                Text("Borne de signature")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                PulsingDot(color: .white.opacity(0.6))
                    .padding(.top, 4)
            }
            .padding(32)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onWake()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Sortir de veille")
    }
}
