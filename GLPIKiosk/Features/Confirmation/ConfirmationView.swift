// GLPIKiosk — ConfirmationView.swift
// Écran de confirmation (succès ou refus). Retour automatique vers idle.

import SwiftUI

struct ConfirmationView: View {
    let success: Bool
    var onDismiss: (() -> Void)? = nil
    private var duration: Int { success ? 5 : 3 }

    @State private var countdown: Int    = 5
    @State private var progress: CGFloat = 1.0
    @State private var iconScale: CGFloat  = 0.0
    @State private var contentOpacity: Double  = 0.0
    @State private var contentOffset: CGFloat  = 50.0

    private var accent: Color {
        success
            ? Color(red: 0.13, green: 0.75, blue: 0.42)
            : Color(red: 0.93, green: 0.27, blue: 0.27)
    }

    private var bgGradient: LinearGradient {
        LinearGradient(
            colors: success
                ? [Color(red: 0.04, green: 0.22, blue: 0.12), Color(red: 0.02, green: 0.10, blue: 0.06)]
                : [Color(red: 0.28, green: 0.05, blue: 0.05), Color(red: 0.12, green: 0.02, blue: 0.02)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            bgGradient.ignoresSafeArea()

            // Cercles décoratifs en arrière-plan
            Circle()
                .fill(accent.opacity(0.09))
                .frame(width: 700, height: 700)
                .offset(x: -230, y: -230)
                .allowsHitTesting(false)

            Circle()
                .fill(accent.opacity(0.06))
                .frame(width: 500, height: 500)
                .offset(x: 230, y: 230)
                .allowsHitTesting(false)

            // Contenu principal
            VStack(spacing: 44) {

                // ── Icône ──────────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.20))
                        .frame(width: 190, height: 190)
                    Circle()
                        .fill(accent)
                        .frame(width: 134, height: 134)
                        .shadow(color: accent.opacity(0.55), radius: 28, x: 0, y: 10)
                    Image(systemName: success ? "checkmark" : "xmark")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(iconScale)

                // ── Texte ──────────────────────────────────────────────
                VStack(spacing: 14) {
                    Text(success ? "Signature validée !" : "Signature refusée")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(success
                         ? "Votre signature a bien été enregistrée."
                         : "La demande de signature a été annulée.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                // ── Barre de progression + compte à rebours ────────────
                VStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .frame(width: 360, height: 6)
                        Capsule()
                            .fill(accent)
                            .frame(width: 360 * progress, height: 6)
                            .animation(.linear(duration: 0.92), value: progress)
                    }

                    Text("Retour à l'accueil dans \(countdown) s…")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.50))
                }
            }
            .opacity(contentOpacity)
            .offset(y: contentOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            countdown = duration
            progress  = 1.0

            withAnimation(.spring(response: 0.55, dampingFraction: 0.74)) {
                contentOpacity = 1
                contentOffset  = 0
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.58).delay(0.18)) {
                iconScale = 1
            }
            startCountdown()
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        var remaining = duration
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            remaining -= 1
            countdown  = remaining
            progress   = CGFloat(remaining) / CGFloat(duration)
            if remaining <= 0 {
                timer.invalidate()
                onDismiss?()
            }
        }
    }
}
