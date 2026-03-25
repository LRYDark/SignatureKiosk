// GLPIKiosk — RootView.swift
// Routeur principal basé sur KioskPhase.

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var kiosk: KioskState

    var body: some View {
        ZStack {
            // Fond global
            KioskTheme.background.ignoresSafeArea()

            if kiosk.isBootstrapping {
                KioskLaunchView(status: kiosk.bootstrapStatus)
            } else {
                // Bandeau offline
                VStack(spacing: 0) {
                    if !kiosk.isOnline {
                        OfflineBanner()
                    }

                    // Routage par phase
                    Group {
                        switch kiosk.phase {

                        case .setup:
                            SetupView()

                        case .idle, .polling:
                            IdleView()

                        case .requestReceived(let req):
                            SignatureRequestView(request: req)

                        case .signing(let req):
                            SignatureRequestView(request: req) // intègre le pad

                        case .submitting:
                            SubmittingView()

                        case .confirmed:
                            ConfirmationView(success: true)

                        case .refused:
                            ConfirmationView(success: false)

                        case .error(let msg):
                            ErrorBannerView(message: msg)

                        case .settings:
                            SettingsView()
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: kiosk.phase)
                }
            }
        }
        .statusBarHidden(true)   // Kiosque : cacher la barre de statut
        .debugBar()
    }
}

private struct KioskLaunchView: View {
    let status: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "signature")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(KioskTheme.brand)

            Text("GLPI Kiosk")
                .font(.largeTitle.weight(.bold))

            ProgressView()
                .scaleEffect(1.3)
                .tint(KioskTheme.brand)

            Text(status)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Offline Banner

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Hors ligne — vérifiez la connexion réseau")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange)
    }
}

// MARK: - Submitting overlay

struct SubmittingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(2)
                .tint(KioskTheme.brand)
            Text("Envoi de la signature…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error Banner

struct ErrorBannerView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            Text(message)
                .font(.title2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
