// GLPIKiosk — SignatureRequestView.swift
// Affiche la requête de signature reçue depuis le PC :
//   - Infos ticket (titre)
//   - Tâches (liste)
//   - Pad de signature
//   - Nom + email signataire
//   - Boutons Signer / Refuser
//
// NOTE: Base Description / Info intentionnellement absent.

import SwiftUI
import WebKit

private enum RemoteSignatureStage {
    case preview
    case signature
}

struct SignatureRequestView: View {
    @EnvironmentObject private var kiosk: KioskState
    let request: SignatureRequest

    @State private var stage: RemoteSignatureStage = .preview
    @State private var signerName:   String = ""
    @State private var signerEmail:  String = ""
    @State private var signatureB64: String? = nil
    @State private var showRefuseConfirm = false
    @State private var validationError: String? = nil

    private var params: SignatureParameters? { request.parameters }
    private var previewURL: URL? { resolvedPreviewURL() }

    var body: some View {
        Group {
            if stage == .preview {
                previewFullPage
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        Divider()
                        signatureContent
                    }
                    .padding(24)
                }
                .background(KioskTheme.background)
            }
        }
        .background(KioskTheme.background)
        .onAppear {
            if signerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let raw = params?.clientEmail {
                signerEmail = raw
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? ""
            }
        }
        .confirmationDialog(
            "Refuser la demande de signature ?",
            isPresented: $showRefuseConfirm,
            titleVisibility: .visible
        ) {
            Button("Refuser", role: .destructive) {
                Task { await kiosk.refuse(request: request) }
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: - Preview stage: full-page layout (no outer scroll, PDF fills space)

    @ViewBuilder
    private var previewFullPage: some View {
        VStack(spacing: 0) {

            // ── En-tête ─────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Demande de signature")
                        .font(.title.weight(.bold))
                    if let title = params?.ticketTitle {
                        Text(title)
                            .font(.title3)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            if previewURL == nil {
                // ── Mode ticket : description + tâches + suivis (remplit l'espace) ─
                let desc      = params?.ticketDescription.map { sanitizedHTMLText($0) } ?? ""
                let tasks     = params?.ticketTasks     ?? []
                let followups = params?.ticketFollowups ?? []
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Description
                        if !desc.isEmpty {
                            Text("Description")
                                .font(.headline)
                                .padding(.bottom, 8)
                            Text(desc)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(.secondary)
                            if !tasks.isEmpty || !followups.isEmpty {
                                Divider().padding(.vertical, 14)
                            }
                        }
                        // Tâches
                        if !tasks.isEmpty {
                            Text("Tâches effectuées")
                                .font(.headline)
                                .padding(.bottom, 12)
                            ForEach(Array(tasks.enumerated()), id: \.element.id) { idx, task in
                                if idx > 0 { Divider().padding(.vertical, 8) }
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(KioskTheme.brand)
                                        .font(.body)
                                        .padding(.top, 2)
                                    Text(sanitizedHTMLText(task.content))
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        // Suivis
                        if !followups.isEmpty {
                            if !tasks.isEmpty { Divider().padding(.vertical, 14) }
                            Text("Suivis")
                                .font(.headline)
                                .padding(.bottom, 12)
                            ForEach(Array(followups.enumerated()), id: \.element.id) { idx, fu in
                                if idx > 0 { Divider().padding(.vertical, 8) }
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "bubble.left.fill")
                                        .foregroundStyle(KioskTheme.warning)
                                        .font(.body)
                                        .padding(.top, 2)
                                    Text(sanitizedHTMLText(fu.content))
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if tasks.isEmpty && followups.isEmpty {
                            Text("Aucun élément associé à ce ticket.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KioskTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 10)
            } else {
                // ── Mode BL : tâches compactes + BL info + PDF viewer ────────

                // Tâches (hauteur limitée)
                if let tasks = params?.ticketTasks, !tasks.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tâches effectuées")
                                .font(.headline)
                            ForEach(tasks) { task in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(KioskTheme.brand)
                                        .font(.body)
                                    Text(sanitizedHTMLText(task.content))
                                        .font(.body)
                                }
                            }
                        }
                        .padding(14)
                    }
                    .frame(maxHeight: 160)
                    .background(KioskTheme.card)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                // BL associé (si présent)
                if let bl = params?.blNumber {
                    HStack(spacing: 16) {
                        Label("BL \(bl)", systemImage: "doc.text.fill")
                        if let ht = params?.blAmountHT {
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("HT : \(ht) €")
                                if let ttc = params?.blAmountTTC {
                                    Text("TTC : \(ttc) €").bold()
                                }
                            }
                            .font(.callout)
                        }
                    }
                    .padding(14)
                    .background(KioskTheme.card)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }

                // PDF viewer (remplit l'espace restant)
                if let url = previewURL {
                    RemoteSignatureDocumentPreviewWebView(url: url)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // BL sans PDF disponible
                    VStack(spacing: 10) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Aperçu PDF indisponible")
                            .font(.headline)
                        Text("Le document peut tout de même être signé.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }

            // ── Boutons épinglés en bas ──────────────────────────────────────
            VStack(spacing: 0) {
                Divider()
                if let err = validationError {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                HStack(spacing: 16) {
                    Button(role: .destructive) {
                        showRefuseConfirm = true
                    } label: {
                        Label("Refuser", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        validationError = nil
                        let rtype = params?.reportType ?? ""
                        if previewURL == nil,
                           (rtype == "rapport" || rtype == "rapport_hotline"),
                           (params?.ticketTasks ?? []).isEmpty {
                            validationError = "Au moins une tâche est requise pour signer ce rapport."
                            return
                        }
                        stage = .signature
                    } label: {
                        Label("Signer", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KioskTheme.brand)
                    .controlSize(.large)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 10 + 8)
                .background(.ultraThinMaterial)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Signature stage (scrollable)

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Demande de signature")
                    .font(.title.weight(.bold))
                if let title = params?.ticketTitle {
                    Text(title)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var signatureContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signataire")
                .font(.headline)

            TextField("Nom complet *", text: $signerName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textContentType(.name)

            TextField("Email (optionnel)", text: $signerEmail)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled(true)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
        }
        .padding(16)
        .background(KioskTheme.card)
        .cornerRadius(12)

        VStack(alignment: .leading, spacing: 8) {
            Text("Signature")
                .font(.headline)
            SignaturePadView(signatureB64: $signatureB64)
                .frame(height: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
        .padding(16)
        .background(KioskTheme.card)
        .cornerRadius(12)

        if let err = validationError {
            Label(err, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        }

        HStack(spacing: 16) {
            Button {
                validationError = nil
                stage = .preview
            } label: {
                Label("Retour", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(role: .destructive) {
                showRefuseConfirm = true
            } label: {
                Label("Refuser", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                handleSign()
            } label: {
                Label("Valider la signature", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(KioskTheme.brand)
            .controlSize(.large)
        }
        .padding(.top, 8)
    }

    // MARK: - Validation & Submit

    private func handleSign() {
        validationError = nil

        let name = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            validationError = "Le nom du signataire est obligatoire."
            return
        }
        guard let sig = signatureB64, !sig.isEmpty else {
            validationError = "Veuillez apposer votre signature."
            return
        }

        let email = signerEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await kiosk.submit(
                request:      request,
                signerName:   name,
                signerEmail:  email,
                signatureB64: sig
            )
        }
    }

    private func resolvedPreviewURL() -> URL? {
        let raw = (params?.documentURL ?? params?.legacyURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return URL(string: raw)
        }

        guard let baseURL = URL(string: kiosk.settings.normalizedBaseURL) else {
            return URL(string: raw)
        }

        if raw.hasPrefix("/") {
            var c = URLComponents()
            c.scheme = baseURL.scheme
            c.host = baseURL.host
            c.port = baseURL.port
            c.path = raw
            return c.url
        }

        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - HTML helpers

    private func sanitizedHTMLText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let htmlNormalized = trimmed
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>",  with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</div>", with: "\n", options: [.regularExpression, .caseInsensitive])

        let noTags = htmlNormalized.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        var output = noTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        output = decodeNumericHTMLEntities(output)
        output = output.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeNumericHTMLEntities(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") else { return input }
        let nsInput = input as NSString
        let matches = regex.matches(in: input, options: [], range: NSRange(location: 0, length: nsInput.length))
        guard !matches.isEmpty else { return input }
        var output = input
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let fullRange  = match.range(at: 0)
            let tokenRange = match.range(at: 1)
            guard fullRange.location != NSNotFound, tokenRange.location != NSNotFound else { continue }
            let token = nsInput.substring(with: tokenRange)
            let scalarValue: UInt32? = token.lowercased().hasPrefix("x")
                ? UInt32(token.dropFirst(), radix: 16)
                : UInt32(token, radix: 10)
            guard let value = scalarValue,
                  let scalar = UnicodeScalar(value),
                  let swiftRange = Range(fullRange, in: output) else { continue }
            output.replaceSubrange(swiftRange, with: String(Character(scalar)))
        }
        return output
    }
}

private struct RemoteSignatureDocumentPreviewWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
