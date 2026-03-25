// GLPIKiosk — DirectSignView.swift
// Signature directe depuis la borne — sans demande PC préalable.
// Utilisé par les boutons "Signature Rapide BL" et "Signature Rapide Ticket".

import SwiftUI

// MARK: - Type de signature directe

enum DirectSignType: String {
    case bl     = "bl"
    case ticket = "ticket"

    var displayLabel: String {
        switch self {
        case .bl:     return "Bordereau de Livraison"
        case .ticket: return "Ticket"
        }
    }

    var referenceLabel: String {
        switch self {
        case .bl:     return "Numéro de BL"
        case .ticket: return "Numéro de ticket"
        }
    }

    var referencePlaceholder: String {
        switch self {
        case .bl:     return "Ex : BL202852"
        case .ticket: return "Ex : 1042"
        }
    }

    var icon: String {
        switch self {
        case .bl:     return "shippingbox.fill"
        case .ticket: return "ticket.fill"
        }
    }

    var keyboardType: UIKeyboardType {
        switch self {
        case .bl:     return .default
        case .ticket: return .numberPad
        }
    }
}

// MARK: - DirectSignView

struct DirectSignView: View {
    let type: DirectSignType
    @EnvironmentObject private var kiosk: KioskState
    @Environment(\.dismiss) private var dismiss

    @State private var reference:    String  = ""
    @State private var signerName:   String  = ""
    @State private var signerEmail:  String  = ""
    @State private var signature:    String? = nil   // SignaturePadView utilise String?
    @State private var isSubmitting: Bool    = false
    @State private var errorMsg:     String?
    @State private var showSuccess:  Bool    = false

    private var canSubmit: Bool {
        !reference.trimmingCharacters(in: .whitespaces).isEmpty &&
        !signerName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !(signature ?? "").isEmpty &&
        !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KioskTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {

                        // ── En-tête ───────────────────────────────────────────
                        HStack(spacing: 14) {
                            Image(systemName: type.icon)
                                .font(.title)
                                .foregroundStyle(KioskTheme.brand)
                            Text("Signature \(type.displayLabel)")
                                .font(.title2.weight(.bold))
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        // ── Référence ─────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text(type.referenceLabel)
                                .font(.headline)
                            TextField(type.referencePlaceholder, text: $reference)
                                .keyboardType(type.keyboardType)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(type == .bl ? .characters : .never)
                                .textFieldStyle(.roundedBorder)
                                .font(.title3)
                        }
                        .padding(.horizontal, 24)

                        // ── Signataire ────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Signataire")
                                .font(.headline)
                            TextField("Nom complet *", text: $signerName)
                                .autocorrectionDisabled(true)
                                .textFieldStyle(.roundedBorder)
                            TextField("Email (optionnel)", text: $signerEmail)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal, 24)

                        // ── Pad de signature ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Signature")
                                .font(.headline)

                            // Le bouton "effacer" est intégré dans SignaturePadView (↺)
                            SignaturePadView(signatureB64: $signature)
                                .frame(height: 220)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            (signature ?? "").isEmpty
                                                ? Color.secondary.opacity(0.3)
                                                : KioskTheme.brand.opacity(0.4),
                                            lineWidth: 1.5
                                        )
                                )

                            if (signature ?? "").isEmpty {
                                Text("Signez dans le cadre ci-dessus")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 24)

                        // ── Erreur ────────────────────────────────────────────
                        if let err = errorMsg {
                            Text(err)
                                .foregroundStyle(.red)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        // ── Actions ───────────────────────────────────────────
                        HStack(spacing: 16) {
                            Button("Annuler", role: .cancel) { dismiss() }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)

                            Button {
                                submit()
                            } label: {
                                HStack(spacing: 8) {
                                    if isSubmitting {
                                        ProgressView().tint(.white)
                                    }
                                    Text(isSubmitting ? "Envoi…" : "Valider la signature")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(KioskTheme.brand)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .alert("Signature enregistrée !", isPresented: $showSuccess) {
            Button("Fermer", role: .cancel) { dismiss() }
        } message: {
            Text("La signature a été transmise au serveur avec succès.")
        }
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMsg     = nil

        let svc  = DeviceService(settings: kiosk.settings)
        let ref  = reference.trimmingCharacters(in: .whitespaces)
        let name = signerName.trimmingCharacters(in: .whitespaces)
        let mail = signerEmail.trimmingCharacters(in: .whitespaces)
        let sig  = signature ?? ""

        Task {
            do {
                _ = try await svc.directSign(
                    type:         type.rawValue,
                    reference:    ref,
                    signerName:   name,
                    signerEmail:  mail,
                    signatureB64: sig
                )
                await MainActor.run {
                    isSubmitting = false
                    showSuccess  = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMsg     = "Erreur : \(error.localizedDescription)"
                }
            }
        }
    }
}
