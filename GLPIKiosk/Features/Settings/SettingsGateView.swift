// GLPIKiosk — SettingsGateView.swift
// Demande le code admin avant d'accéder aux paramètres.

import SwiftUI

struct SettingsGateView: View {
    @EnvironmentObject private var kiosk: KioskState
    @Environment(\.dismiss) private var dismiss

    @State private var code:       String = ""
    @State private var failed:     Bool   = false
    @State private var attempts:   Int    = 0
    private let maxAttempts = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "lock.shield")
                    .font(.system(size: 64))
                    .foregroundStyle(KioskTheme.brand)

                Text("Code administrateur")
                    .font(.title2.weight(.bold))

                SecureField("Code PIN", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 240)
                    .multilineTextAlignment(.center)

                if failed {
                    Text(attempts >= maxAttempts
                         ? "Trop de tentatives. Réessayez plus tard."
                         : "Code incorrect.")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                HStack(spacing: 16) {
                    Button("Annuler", role: .cancel) { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                    Button("Valider") { validate() }
                        .buttonStyle(.borderedProminent)
                        .tint(KioskTheme.brand)
                        .controlSize(.large)
                        .disabled(code.isEmpty || attempts >= maxAttempts)
                }

                Spacer()
            }
            .padding(32)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    private func validate() {
        if kiosk.unlockAdmin(code: code) {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                kiosk.phase = .settings
            }
        } else {
            attempts += 1
            failed    = true
            code      = ""
        }
    }
}
