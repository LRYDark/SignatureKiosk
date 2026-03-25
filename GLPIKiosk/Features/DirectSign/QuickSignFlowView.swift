import SwiftUI
import WebKit

private enum QuickSignStage: Equatable {
    case entry
    case blDetails
    case ticketPreview
    case signature
}

private enum QuickBLFullscreenStage: Equatable {
    case preview
    case signature
}

struct QuickSignFlowView: View {
    let type: DirectSignType

    @EnvironmentObject private var kiosk: KioskState
    @Environment(\.dismiss) private var dismiss

    @State private var stage: QuickSignStage = .entry

    @State private var technicians: [QuickTechnician] = []
    @State private var selectedTechnicianID: Int? = nil

    @State private var blQuery: String = "BL"
    @State private var blResults: [QuickBLSearchResult] = []
    @State private var blPrepared: QuickBLPrepareResponse?
    @State private var blSelectedDocumentName: String = ""
    @State private var blComment: String = ""
    @State private var blCounterInvoiceClient: Bool = false

    @State private var ticketInput: String = ""
    @State private var ticketPrepared: QuickTicketPrepareResponse?
    @State private var selectedDocumentType: String = "intervention_report"

    @State private var signerName: String = ""
    @State private var signerEmail: String = ""
    @State private var signatureB64: String? = nil

    @State private var isLoadingTechnicians = false
    @State private var isSearchingBL = false
    @State private var isPreparingBL = false
    @State private var isLoadingTicket = false
    @State private var isSubmitting = false
    @State private var errorMsg: String?
    @State private var showConfirmation = false
    @State private var showBLFullscreenFlow = false
    @State private var blFullscreenStage: QuickBLFullscreenStage = .preview
    @State private var showTicketFullscreenFlow = false

    private var api: QuickSignAPIService { QuickSignAPIService(settings: kiosk.settings) }

    private var selectedTechnician: QuickTechnician? {
        guard let id = selectedTechnicianID else { return nil }
        return technicians.first(where: { $0.id == id })
    }

    private var canSubmitSignature: Bool {
        !signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !((signatureB64 ?? "").isEmpty) &&
        !isSubmitting
    }

    private var blDocumentTitle: String {
        let candidate = blSelectedDocumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty { return sanitizedDocumentTitle(candidate) }
        let preparedBL = (blPrepared?.bl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !preparedBL.isEmpty { return sanitizedDocumentTitle(preparedBL) }
        return "-"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KioskTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerView

                        switch stage {
                        case .entry:
                            entryView
                        case .blDetails:
                            blDetailsView
                        case .ticketPreview:
                            ticketPreviewView
                        case .signature:
                            signatureView
                        }

                        if let errorMsg {
                            Text(errorMsg)
                                .foregroundStyle(.red)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if stage != .entry {
                        Button("Retour") { goBack() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task {
            await loadTechniciansIfNeeded()
        }
        .fullScreenCover(isPresented: $showBLFullscreenFlow) {
            blFullscreenFlowView
                .debugBar()
        }
        .fullScreenCover(isPresented: $showTicketFullscreenFlow) {
            ticketFullscreenFlowView
                .debugBar()
        }
        .debugBar()
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: type.icon)
                    .foregroundStyle(KioskTheme.brand)
                Text(type == .bl ? "Signature Rapide BL" : "Signature Rapide Ticket")
                    .font(.title2.weight(.bold))
            }
            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitleText: String {
        switch stage {
        case .entry:
            return type == .bl
                ? "Choisissez le technicien puis recherchez un BL."
                : "Choisissez le technicien puis chargez le ticket."
        case .blDetails:
            return "Renseignez les détails BL avant la signature."
        case .ticketPreview:
            return "Vérifiez la description, les tâches et les suivis."
        case .signature:
            return "Saisissez le signataire puis signez."
        }
    }

    @ViewBuilder
    private var entryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            technicianPickerCard

            if type == .bl {
                blEntryCard
            } else {
                ticketEntryCard
            }
        }
    }

    private var technicianPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Technicien")
                .font(.headline)

            if isLoadingTechnicians {
                ProgressView("Chargement des techniciens…")
            } else {
                Picker("Technicien", selection: $selectedTechnicianID) {
                    Text("Sélectionner").tag(Optional<Int>.none)
                    ForEach(technicians) { tech in
                        Text(tech.display ?? tech.label).tag(Optional(tech.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(16)
        .background(KioskTheme.card)
        .cornerRadius(14)
    }

    private var blEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recherche BL")
                .font(.headline)

            HStack(spacing: 10) {
                PhonePadTextField(placeholder: "Ex: BL199550", text: $blQuery, minLength: 2, onSubmit: { searchBL() })
                    .frame(height: 36)
                    .onChange(of: blQuery) { _, newValue in
                        normalizeBLQuery(newValue)
                    }

                Button {
                    searchBL()
                } label: {
                    if isSearchingBL {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Rechercher")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(KioskTheme.brand)
                .disabled(isSearchingBL || (selectedTechnician == nil))
            }

            if !blResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Résultats")
                        .font(.subheadline.weight(.semibold))
                    ForEach(blResults) { item in
                        Button {
                            selectBL(item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.displayText)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text("\((item.save ?? item.source ?? "-").uppercased())\(item.isSigned ? " • déjà signé" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isPreparingBL {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(.white.opacity(0.001))
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreparingBL)
                        Divider()
                    }
                }
                .padding(12)
                .background(KioskTheme.card)
                .cornerRadius(14)
            }
        }
        .padding(16)
        .background(KioskTheme.card)
        .cornerRadius(14)
    }

    private var ticketEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ticket")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Type de document")
                    .font(.subheadline.weight(.medium))
                Picker("Type de document", selection: $selectedDocumentType) {
                    Text("Rapport d'intervention").tag("intervention_report")
                    Text("Rapport Hotline").tag("hotline_report")
                    Text("Prise en charge").tag("charge_sheet")
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 10) {
                PhonePadTextField(placeholder: "ID du ticket", text: $ticketInput, onSubmit: { loadTicket() })
                    .frame(height: 36)

                Button {
                    loadTicket()
                } label: {
                    if isLoadingTicket {
                        ProgressView().tint(.white)
                    } else {
                        Text("Charger")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(KioskTheme.brand)
                .disabled(isLoadingTicket || selectedTechnician == nil || Int(ticketInput) == nil)
            }
        }
        .padding(16)
        .background(KioskTheme.card)
        .cornerRadius(14)
    }

    @ViewBuilder
    private var blDetailsView: some View {
        if let prepared = blPrepared {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BL sélectionné")
                        .font(.headline)
                    Text(prepared.bl ?? "-")
                        .font(.title3.weight(.semibold))
                }
                .padding(16)
                .background(KioskTheme.card)
                .cornerRadius(14)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Détails BL")
                        .font(.headline)

                    TextField("Commentaire (optionnel)", text: $blComment, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Règlement effectué au comptoir", isOn: $blCounterInvoiceClient)

                    if let ht = prepared.amountHT, !ht.isEmpty {
                        Text("Montant HT : \(formattedAmount(ht)) €")
                            .font(.subheadline.weight(.semibold))
                    }
                    if let ttc = prepared.amountTTC, !ttc.isEmpty {
                        Text("Montant TTC : \(formattedAmount(ttc)) €")
                            .font(.subheadline.weight(.semibold))
                    }

                    Button("Continuer vers la signature") {
                        errorMsg = nil
                        blFullscreenStage = .preview
                        showBLFullscreenFlow = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KioskTheme.brand)
                    .disabled(selectedTechnician == nil)
                }
                .padding(16)
                .background(KioskTheme.card)
                .cornerRadius(14)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var ticketPreviewView: some View {
        if let prepared = ticketPrepared {
            VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ticket #\(prepared.ticketID)")
                        .font(.headline)
                    Spacer()
                    Text(documentTypeLabel(selectedDocumentType))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(KioskTheme.brand.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(sanitizedHTMLText(prepared.ticketTitle ?? prepared.ticketName ?? "-"))
                    .font(.title3.weight(.semibold))
                if let entity = prepared.entityName, !entity.isEmpty {
                    Text(entity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(KioskTheme.card)
            .cornerRadius(14)

            let cleanDescription = sanitizedHTMLText(prepared.ticketDescription ?? "")
            if !cleanDescription.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)
                    Text(cleanDescription)
                        .font(.body)
                }
                .padding(16)
                .background(KioskTheme.card)
                .cornerRadius(14)
            }

            if !prepared.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tâches (\(prepared.tasks.count))")
                        .font(.headline)
                    ForEach(prepared.tasks) { task in
                        let cleanTaskContent = sanitizedHTMLText(task.content)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cleanTaskContent.isEmpty ? "-" : cleanTaskContent)
                            if let author = task.author, !author.isEmpty {
                                Text(sanitizedHTMLText(author))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(16)
                .background(KioskTheme.card)
                .cornerRadius(14)
            }

            if !prepared.followups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suivis (\(prepared.followups.count))")
                        .font(.headline)
                    ForEach(prepared.followups) { item in
                        let cleanFollowupContent = sanitizedHTMLText(item.content)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cleanFollowupContent.isEmpty ? "-" : cleanFollowupContent)
                            if let author = item.author, !author.isEmpty {
                                Text(sanitizedHTMLText(author))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(16)
                .background(KioskTheme.card)
                .cornerRadius(14)
            }

            Button("Continuer vers la signature") {
                errorMsg = nil
                let requiresTask = selectedDocumentType == "intervention_report" || selectedDocumentType == "hotline_report"
                if requiresTask && prepared.tasks.isEmpty {
                    errorMsg = "Au moins une tâche est requise pour signer ce rapport."
                    return
                }
                stage = .signature
            }
            .buttonStyle(.borderedProminent)
            .tint(KioskTheme.brand)
            }
        } else {
            EmptyView()
        }
    }

    private var signatureView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if type == .bl && showBLFullscreenFlow {
                blDocumentCard
            } else if type == .ticket && showTicketFullscreenFlow {
                ticketDocumentCard
            } else {
                recapCard
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Signataire")
                    .font(.headline)
                TextField("Nom complet *", text: $signerName)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                TextField("Email (optionnel)", text: $signerEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
            .padding(16)
            .background(KioskTheme.card)
            .cornerRadius(14)

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
            .cornerRadius(14)

            Button {
                submit()
            } label: {
                HStack {
                    Spacer()
                    if isSubmitting { ProgressView().tint(.white) }
                    Text(isSubmitting ? "Envoi…" : "Valider la signature")
                        .font(.body.weight(.semibold))
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(KioskTheme.brand)
            .disabled(!canSubmitSignature)
        }
    }

    @ViewBuilder
    private var blFullscreenFlowView: some View {
        NavigationStack {
            ZStack {
                KioskTheme.background.ignoresSafeArea()

                switch blFullscreenStage {
                case .preview:
                    blPreviewFullscreenView
                case .signature:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Signature client")
                                    .font(.title2.weight(.bold))
                                Text("Renseignez le signataire puis signez le document.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            signatureView

                            if let errorMsg {
                                Text(errorMsg)
                                    .foregroundStyle(.red)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if blFullscreenStage == .signature {
                        Button("Retour") {
                            errorMsg = nil
                            blFullscreenStage = .preview
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        closeQuickSignFlow()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if blFullscreenStage == .preview {
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            Button {
                                errorMsg = nil
                                blFullscreenStage = .signature
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Signer")
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(KioskTheme.brand)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 10 + 8)
                        .background(.ultraThinMaterial)
                    }
                }
            }
            .fullScreenCover(isPresented: $showConfirmation) {
                ConfirmationView(success: true, onDismiss: closeQuickSignFlow)
            }
        }
    }

    @ViewBuilder
    private var ticketFullscreenFlowView: some View {
        NavigationStack {
            ZStack {
                KioskTheme.background.ignoresSafeArea()

                switch stage {
                case .ticketPreview:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Aperçu du ticket")
                                    .font(.title2.weight(.bold))
                                Text("Vérifiez le ticket puis appuyez sur Continuer vers la signature.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            ticketPreviewView

                            if let errorMsg {
                                Text(errorMsg)
                                    .foregroundStyle(.red)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 980)
                        .frame(maxWidth: .infinity)
                    }

                case .signature:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Signature client")
                                    .font(.title2.weight(.bold))
                                Text("Renseignez le signataire puis signez le ticket.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            signatureView

                            if let errorMsg {
                                Text(errorMsg)
                                    .foregroundStyle(.red)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                    }

                default:
                    EmptyView()
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if stage == .signature {
                        Button("Retour") {
                            errorMsg = nil
                            stage = .ticketPreview
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        closeQuickSignFlow()
                    }
                }
            }
            .fullScreenCover(isPresented: $showConfirmation) {
                ConfirmationView(success: true, onDismiss: closeQuickSignFlow)
            }
        }
    }

    @ViewBuilder
    private var blPreviewFullscreenView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── En-tête ──
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aperçu du document")
                        .font(.title2.weight(.bold))
                    Text("Vérifiez le BL puis appuyez sur Signer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                blDocumentCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // ── PDF remplit l'espace restant ──
            if let url = preparedBLPreviewURL {
                QuickSignDocumentPreviewWebView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Aperçu PDF indisponible")
                        .font(.headline)
                    Text("Le document sera tout de même signable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KioskTheme.card.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            if let errorMsg {
                Text(errorMsg)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let raw = blPrepared?.previewURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolved = preparedBLPreviewURL?.absoluteString ?? "(nil)"
            if raw.isEmpty {
                DebugLogger.warn("BL preview URL absente (prepareBL.preview_url vide)")
            } else {
                DebugLogger.log("BL preview URL raw=\(raw) | resolved=\(resolved)")
            }
        }
    }

    private var preparedBLPreviewURL: URL? {
        guard let raw = blPrepared?.previewURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: raw)
        }

        guard let baseURL = URL(string: kiosk.settings.normalizedBaseURL) else {
            return URL(string: raw)
        }

        if raw.hasPrefix("/") {
            if var c = URLComponents(string: raw) {
                c.scheme = baseURL.scheme
                c.host = baseURL.host
                c.port = baseURL.port
                return c.url
            }

            // Fallback if URLComponents cannot parse the relative URL.
            let parts = raw.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            var c = URLComponents()
            c.scheme = baseURL.scheme
            c.host = baseURL.host
            c.port = baseURL.port
            c.path = String(parts.first ?? "")
            if parts.count > 1 {
                c.percentEncodedQuery = String(parts[1])
            }
            return c.url
        }

        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    private var blDocumentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BL : \(blDocumentTitle)")
                .font(.headline)
        }
        .padding(16)
        .background(KioskTheme.card)
        .cornerRadius(14)
    }

    private var ticketDocumentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prepared = ticketPrepared {
                let title = sanitizedHTMLText(prepared.ticketTitle ?? prepared.ticketName ?? "")
                let label = "Ticket #\(prepared.ticketID)" + (title.isEmpty ? "" : " \(title)")
                Text(label)
                    .font(.headline)
            } else {
                Text("Ticket")
                    .font(.headline)
            }
        }
        .padding(16)
        .background(KioskTheme.card)
        .cornerRadius(14)
    }

    @ViewBuilder
    private var recapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Récapitulatif")
                .font(.headline)

            if let tech = selectedTechnician {
                Text("Technicien : \(tech.display ?? tech.label)")
                    .font(.subheadline)
            }

            if type == .bl {
                Text("BL : \(blPrepared?.bl ?? "-")")
                    .font(.subheadline)
            } else if let prepared = ticketPrepared {
                Text("Ticket #\(prepared.ticketID)")
                    .font(.subheadline)
                if let title = prepared.ticketTitle ?? prepared.ticketName, !title.isEmpty {
                    Text(sanitizedHTMLText(title))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Tâches: \(prepared.tasks.count) • Suivis: \(prepared.followups.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(KioskTheme.card)
        .cornerRadius(14)
    }

    // MARK: - Actions

    private func normalizeBLQuery(_ newValue: String) {
        let digits = newValue.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
        let v = "BL" + String(String.UnicodeScalarView(digits))
        if blQuery != v {
            blQuery = v
        }
    }

    private func sanitizedDocumentTitle(_ value: String) -> String {
        var output = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.lowercased().hasSuffix(".pdf") {
            output.removeLast(4)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedHTMLText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let htmlNormalized = trimmed
            .replacingOccurrences(
                of: "<br\\s*/?>",
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "</p>",
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "</div>",
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )

        let noTags = htmlNormalized.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        var output = noTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        output = decodeNumericHTMLEntities(output)

        output = output.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeNumericHTMLEntities(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") else {
            return input
        }

        let nsInput = input as NSString
        let matches = regex.matches(
            in: input,
            options: [],
            range: NSRange(location: 0, length: nsInput.length)
        )
        guard !matches.isEmpty else { return input }

        var output = input
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let fullRange = match.range(at: 0)
            let tokenRange = match.range(at: 1)
            guard fullRange.location != NSNotFound, tokenRange.location != NSNotFound else { continue }

            let token = nsInput.substring(with: tokenRange)
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }
            guard let value = scalarValue, let scalar = UnicodeScalar(value),
                  let swiftRange = Range(fullRange, in: output) else {
                continue
            }

            output.replaceSubrange(swiftRange, with: String(Character(scalar)))
        }
        return output
    }

    private func goBack() {
        errorMsg = nil
        switch stage {
        case .entry:
            break
        case .blDetails, .ticketPreview:
            stage = .entry
        case .signature:
            stage = (type == .bl) ? .blDetails : .ticketPreview
        }
    }

    private func closeQuickSignFlow() {
        errorMsg = nil
        showConfirmation = false
        showBLFullscreenFlow = false
        showTicketFullscreenFlow = false
        stage = .entry
        dismiss()
    }

    private func loadTechniciansIfNeeded() async {
        guard technicians.isEmpty, !isLoadingTechnicians else { return }
        await MainActor.run {
            isLoadingTechnicians = true
            errorMsg = nil
        }
        do {
            let items = try await api.fetchTechnicians()
            await MainActor.run {
                technicians = items
                if selectedTechnicianID == nil {
                    selectedTechnicianID = items.first?.id
                }
                isLoadingTechnicians = false
            }
        } catch {
            await MainActor.run {
                isLoadingTechnicians = false
                errorMsg = "Chargement techniciens impossible : \(error.localizedDescription)"
            }
        }
    }

    private func searchBL() {
        guard selectedTechnician != nil else {
            errorMsg = "Veuillez sélectionner un technicien."
            return
        }
        let q = blQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            errorMsg = "Veuillez saisir un BL."
            return
        }

        isSearchingBL = true
        errorMsg = nil
        blResults = []

        Task {
            do {
                let result = try await api.searchBL(query: q)
                await MainActor.run {
                    blResults = result.results
                    if technicians.isEmpty, !result.technicians.isEmpty {
                        technicians = result.technicians
                    }
                    isSearchingBL = false
                    if result.results.isEmpty {
                        errorMsg = "Aucun BL trouvé."
                    }
                }
            } catch {
                await MainActor.run {
                    isSearchingBL = false
                    errorMsg = "Recherche BL impossible : \(error.localizedDescription)"
                }
            }
        }
    }

    private func selectBL(_ item: QuickBLSearchResult) {
        guard selectedTechnician != nil else {
            errorMsg = "Veuillez sélectionner un technicien."
            return
        }
        isPreparingBL = true
        errorMsg = nil

        Task {
            do {
                let prepared = try await api.prepareBL(selection: item)
                await MainActor.run {
                    isPreparingBL = false
                    if prepared.alreadySigned == true {
                        errorMsg = "Ce BL est déjà signé."
                        return
                    }
                    blSelectedDocumentName = [item.filename, item.text, item.id]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first(where: { !$0.isEmpty }) ?? ""
                    blPrepared = prepared
                    blComment = ""
                    blCounterInvoiceClient = false
                    let rawPreviewURL = prepared.previewURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let resolvedPreviewURL = preparedBLPreviewURL?.absoluteString ?? "(nil)"
                    if rawPreviewURL.isEmpty {
                        DebugLogger.warn("BL prepare: preview_url absente dans la réponse")
                    } else {
                        DebugLogger.log("BL prepare: preview_url raw=\(rawPreviewURL) | resolved=\(resolvedPreviewURL)")
                    }
                    stage = .blDetails
                }
            } catch {
                await MainActor.run {
                    isPreparingBL = false
                    errorMsg = "Préparation BL impossible : \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadTicket() {
        guard selectedTechnician != nil else {
            errorMsg = "Veuillez sélectionner un technicien."
            return
        }
        guard let ticketID = Int(ticketInput) else {
            errorMsg = "ID ticket invalide."
            return
        }

        isLoadingTicket = true
        errorMsg = nil
        Task {
            do {
                let prepared = try await api.prepareTicket(ticketID: ticketID, documentType: selectedDocumentType)
                await MainActor.run {
                    ticketPrepared = prepared
                    if signerEmail.isEmpty {
                        signerEmail = prepared.clientEmail ?? ""
                    }
                    isLoadingTicket = false
                    stage = .ticketPreview
                    showTicketFullscreenFlow = true
                }
            } catch {
                await MainActor.run {
                    isLoadingTicket = false
                    errorMsg = "Chargement ticket impossible : \(error.localizedDescription)"
                }
            }
        }
    }

    private func submit() {
        guard let tech = selectedTechnician else {
            errorMsg = "Technicien manquant."
            return
        }
        let name = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = signerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let sig = signatureB64 ?? ""

        guard !name.isEmpty else {
            errorMsg = "Veuillez saisir le nom du signataire."
            return
        }
        guard !sig.isEmpty else {
            errorMsg = "Veuillez signer dans la zone."
            return
        }

        isSubmitting = true
        errorMsg = nil

        Task {
            do {
                if type == .bl {
                    guard let prepared = blPrepared, let surveyID = prepared.id else {
                        throw APIError.parsing("BL non préparé")
                    }
                    _ = try await api.submitQuickBL(
                        surveyID: surveyID,
                        signerName: name,
                        signerEmail: email,
                        signatureB64: sig,
                        technicianLogin: tech.login,
                        comment: blComment.trimmingCharacters(in: .whitespacesAndNewlines),
                        counterInvoiceClient: blCounterInvoiceClient
                    )
                } else {
                    guard let prepared = ticketPrepared else {
                        throw APIError.parsing("Ticket non préparé")
                    }
                    _ = try await api.submitQuickTicket(
                        prepared: prepared,
                        signerName: name,
                        signerEmail: email,
                        signatureB64: sig,
                        technicianID: tech.id,
                        documentType: selectedDocumentType
                    )
                }
                await MainActor.run {
                    isSubmitting = false
                    showConfirmation = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMsg = "Envoi impossible : \(error.localizedDescription)"
                }
            }
        }
    }

    private func documentTypeLabel(_ type: String) -> String {
        switch type {
        case "hotline_report":  return "Rapport Hotline"
        case "charge_sheet":    return "Prise en charge"
        default:                return "Rapport d'intervention"
        }
    }

    private func formattedAmount(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
        }
        return trimmed
    }
}

// MARK: - PhonePadTextField

private struct PhonePadTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var minLength: Int = 0
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.borderStyle = .roundedRect
        tf.font = .preferredFont(forTextStyle: .body)

        // Supprimer la barre grise système (flèches + copier/coller)
        tf.inputAssistantItem.leadingBarButtonGroups = []
        tf.inputAssistantItem.trailingBarButtonGroups = []
        tf.inputAccessoryView = nil

        let pad = PhonePadInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 304))
        pad.onKey = { [weak tf] key in
            guard let tf else { return }
            if key == "OK" {
                tf.resignFirstResponder()
                context.coordinator.submit()
                return
            }
            var current = tf.text ?? ""
            if key == "⌫" {
                if current.count > context.coordinator.parent.minLength { current.removeLast() }
            } else {
                current += key
            }
            tf.text = current
            context.coordinator.updateBinding(current)
        }
        tf.inputView = pad

        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        if !tf.isFirstResponder, tf.text != text { tf.text = text }
        context.coordinator.parent = self  // garder le coordinator à jour
    }

    final class Coordinator: NSObject {
        var parent: PhonePadTextField
        init(_ parent: PhonePadTextField) { self.parent = parent }

        func updateBinding(_ value: String) { parent.text = value }
        func submit() { parent.onSubmit?() }
    }
}

private final class PhonePadInputView: UIView {
    var onKey: ((String) -> Void)?

    // (digit, subtitle letters) — "OK" = bouton fermer intégré
    private let keys: [(String, String)] = [
        ("1", ""),     ("2", "ABC"),  ("3", "DEF"),
        ("4", "GHI"),  ("5", "JKL"),  ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"),  ("9", "WXYZ"),
        ("OK", ""),    ("0", "+"),    ("⌫", "")
    ]

    // Fond identique au modal (KioskTheme.background = systemGroupedBackground)
    private static let bgColor      = UIColor.systemGroupedBackground
    private static let keyColor     = UIColor.white
    private static let specialColor = UIColor.systemGray4

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = PhonePadInputView.bgColor

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        // 3 ovales × ~107 pt + 2 × 14 pt = 349 pt → boutons en forme de pilule (largeur > hauteur)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            grid.centerXAnchor.constraint(equalTo: centerXAnchor),
            grid.widthAnchor.constraint(equalToConstant: 349)
        ])

        for rowIndex in 0..<4 {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 14
            row.distribution = .fillEqually
            row.heightAnchor.constraint(equalToConstant: 60).isActive = true

            for colIndex in 0..<3 {
                let (digit, letters) = keys[rowIndex * 3 + colIndex]
                if digit.isEmpty {
                    row.addArrangedSubview(UIView())
                } else {
                    row.addArrangedSubview(makeKey(digit, letters: letters))
                }
            }
            grid.addArrangedSubview(row)
        }
    }

    private func makeKey(_ digit: String, letters: String) -> UIButton {
        let isDelete = digit == "⌫"
        let isOK     = digit == "OK"

        let btn = UIButton(type: .custom)
        btn.backgroundColor = (isDelete || isOK) ? PhonePadInputView.specialColor : PhonePadInputView.keyColor
        btn.layer.cornerRadius = 30                         // 60/2 → ovale pill
        btn.layer.masksToBounds = true
        btn.accessibilityIdentifier = digit

        let para = NSMutableParagraphStyle()
        para.alignment = .center

        if isDelete {
            let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            btn.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
            btn.tintColor = UIColor.label
        } else if isOK {
            btn.setAttributedTitle(NSAttributedString(string: "OK", attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: para
            ]), for: .normal)
        } else {
            let attrStr = NSMutableAttributedString(
                string: digit + (letters.isEmpty ? "" : "\n"),
                attributes: [
                    .font: UIFont.systemFont(ofSize: letters.isEmpty ? 30 : 26, weight: .light),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: para
                ]
            )
            if !letters.isEmpty {
                attrStr.append(NSAttributedString(string: letters, attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: para
                ]))
            }
            btn.setAttributedTitle(attrStr, for: .normal)
            btn.titleLabel?.numberOfLines = 2
            btn.titleLabel?.textAlignment = .center
        }

        btn.addTarget(self, action: #selector(keyDown(_:)), for: [.touchDown, .touchDragEnter])
        btn.addTarget(self, action: #selector(keyUp(_:)),   for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        btn.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        return btn
    }

    @objc private func keyDown(_ s: UIButton) {
        s.alpha = 0.55
    }
    @objc private func keyUp(_ s: UIButton) {
        s.alpha = 1.0
    }
    @objc private func keyTapped(_ sender: UIButton) {
        guard let key = sender.accessibilityIdentifier, !key.isEmpty else { return }
        onKey?(key)
    }
}

// MARK: - QuickSignDocumentPreviewWebView

private struct QuickSignDocumentPreviewWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else {
            return
        }
        context.coordinator.loadedURL = url
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        DebugLogger.log("BL WebView load -> \(url.absoluteString)")
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let u = webView.url?.absoluteString {
                DebugLogger.log("BL WebView didStart -> \(u)")
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let urlStr = webView.url?.absoluteString ?? "(nil)"
            DebugLogger.log("BL WebView didFinish -> \(urlStr)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            DebugLogger.warn("BL WebView provisional error: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DebugLogger.warn("BL WebView navigation error: \(error.localizedDescription)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            DebugLogger.warn("BL WebView content process terminated")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if let http = navigationResponse.response as? HTTPURLResponse {
                let mime = navigationResponse.response.mimeType ?? "-"
                DebugLogger.log("BL WebView response -> HTTP \(http.statusCode) mime=\(mime)")
            }
            decisionHandler(.allow)
        }
    }
}
