import SwiftData
import SwiftUI

struct DocumentEditorView: View {
    @Bindable var document: JobDocument
    @Bindable var profile: BusinessProfile
    /// Called when this screen creates another document (an invoice or a copy) that should open next.
    var onOpen: (JobDocument) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionStore.self) private var store

    @State private var editingItem: LineItem?
    @State private var showsClientPicker = false
    @State private var showsPriceBook = false
    @State private var showsPreview = false
    @State private var showsPaywall = false
    @State private var showsSignature = false
    @State private var showsReceiptScan = false
    @State private var signLinkShare: [Any]?
    @State private var isCreatingSignLink = false
    @State private var signLinkError: String?
    @State private var confirmsDelete = false
    @State private var itemPendingDeletion: LineItem?
    @State private var deletesOnDisappear = false
    @Query private var priceBook: [PriceBookItem]

    private var missingPrices: Int {
        document.allItems.count { $0.unitPrice <= 0 }
    }

    var body: some View {
        List {
            Section {
                TextField("Job title", text: $document.title, axis: .vertical)
                    .font(.headline)
                Button {
                    showsClientPicker = true
                } label: {
                    HStack {
                        Label {
                            Text(document.client?.name ?? String(localized: "Add client"))
                                .foregroundStyle(document.client == nil ? Color.accentColor : Color.primary)
                        } icon: {
                            Image(systemName: "person.crop.circle")
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                HStack {
                    Text(document.kind.label)
                    Text(document.displayNumber).monospacedDigit()
                    Spacer()
                    StatusBadge(status: document.status)
                }
            }

            Section {
                ForEach(document.sortedItems) { item in
                    Button {
                        editingItem = item
                    } label: {
                        LineItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteItems)

                Button("Add item", systemImage: "plus.circle.fill") {
                    addItem()
                }
                Button("Scan a receipt", systemImage: "doc.text.viewfinder") {
                    showsReceiptScan = true
                }
                if !priceBook.isEmpty {
                    Button("Add from my prices", systemImage: "book.closed.fill") {
                        showsPriceBook = true
                    }
                }
            } header: {
                Text("Items")
            } footer: {
                if missingPrices > 0 {
                    Label("Items without a price: \(missingPrices)", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Sales tax (%)") {
                    TextField("0", value: $document.taxRate, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                totalsRows
            } footer: {
                Text("Tax applies only to items marked taxable.")
            }

            Section("Notes for the client") {
                TextField("Timeline, deposit, what's included…", text: $document.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                switch document.kind {
                case .estimate:
                    DatePicker("Valid until", selection: deadlineBinding, displayedComponents: .date)
                case .invoice:
                    DatePicker("Payment due", selection: deadlineBinding, displayedComponents: .date)
                    if document.isOverdue() {
                        Label("Overdue", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    Picker("Repeat", selection: Binding(get: { document.repeatInterval }, set: { document.setRepeat($0) })) {
                        ForEach(RepeatInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    if document.repeatInterval != .never {
                        DatePicker("Next invoice", selection: nextRepeatBinding, in: Calendar.current.startOfDay(for: .now)...,
                                   displayedComponents: .date)
                    }
                }
            } footer: {
                if document.kind == .invoice, document.repeatInterval != .never {
                    Text("On that day Cotiza makes a copy of this invoice with a new number and reminds you to send it.")
                } else {
                    Text("Printed on the PDF.")
                }
            }

            if document.kind == .estimate || document.signatureData != nil {
                approvalSection
            }

            Section {
                Picker("Document language", selection: $document.languageRaw) {
                    ForEach(DocumentLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                Picker("Status", selection: statusBinding) {
                    ForEach(DocumentStatus.allCases) { status in
                        Text(status.label).tag(status)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .readableListWidth()
        .navigationTitle(document.displayNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    if document.kind == .estimate {
                        Button("Convert to invoice", systemImage: "doc.badge.arrow.up") { convertToInvoice() }
                    }
                    if document.status != .paid {
                        Button("Mark as paid", systemImage: "checkmark.circle") { setStatus(.paid) }
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showsPreview = true
            } label: {
                Label("Preview and send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.primary)
            .disabled(document.allItems.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .sheet(item: $editingItem, onDismiss: cleanUpItems) { item in
            LineItemSheet(item: item) {
                itemPendingDeletion = item
            }
        }
        .sheet(isPresented: $showsClientPicker) {
            ClientPickerView(selection: $document.client)
        }
        .sheet(isPresented: $showsPriceBook) {
            PriceBookPicker { entry in
                let line = LineItem(text: entry.name, quantity: 1, unit: entry.unit, unitPrice: entry.unitPrice,
                                    isLabor: entry.isLabor, isTaxable: !entry.isLabor, sortIndex: nextSortIndex)
                context.insert(line)
                line.document = document
            }
        }
        .sheet(isPresented: $showsPreview) {
            PDFPreviewView(document: document, profile: profile)
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .sheet(isPresented: Binding(get: { signLinkShare != nil }, set: { if !$0 { signLinkShare = nil } })) {
            ActivityView(items: signLinkShare ?? [])
                .presentationDetents([.medium, .large])
        }
        .alert("Something went wrong", isPresented: Binding(get: { signLinkError != nil }, set: { if !$0 { signLinkError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signLinkError ?? "")
        }
        .task { if document.hasOpenSignLink { await SignLinkSync.run(notify: false) } }
        .modifier(EditorHaptics(document: document, error: signLinkError))
        .fullScreenCover(isPresented: $showsSignature) {
            SignatureSheet(document: document) { png, name in
                document.sign(png: png, name: name)
                ReviewPrompt.goodMoment()
                if document.signRequestID.isEmpty == false {
                    let id = document.signRequestID, secret = document.signRequestSecret
                    document.clearSignLink()
                    Task { await SignLink.delete(id: id, secret: secret) }
                }
                try? context.save()
            }
        }
        .sheet(isPresented: $showsReceiptScan) {
            ReceiptScanView(markup: profile.materialMarkupPercent) { lines, markup in
                profile.materialMarkupPercent = markup
                for line in lines {
                    let item = LineItem(text: line.text, quantity: line.quantity,
                                        unitPrice: Money.withMarkup(line.unitPrice, percent: markup),
                                        isLabor: false, isTaxable: true, sortIndex: nextSortIndex)
                    item.unitCost = line.unitPrice
                    context.insert(item)
                    item.document = document
                }
            }
        }
        .confirmationDialog("Delete this document?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deletesOnDisappear = true
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
        #if DEBUG
        .task {
            guard document.uuid == ScreenshotScene.heroID else { return }
            try? await Task.sleep(for: .seconds(0.5))
            switch ScreenshotScene.current {
            case .pdf: showsPreview = true
            case .signature: showsSignature = true
            default: break
            }
        }
        #endif
        .onAppear {
            // Documents from before dates existed: save the date the picker shows, so the PDF prints the same one.
            switch document.kind {
            case .estimate where document.validUntil == nil:
                document.validUntil = deadlineBinding.wrappedValue
            case .invoice where document.dueDate == nil && document.status != .paid:
                document.dueDate = deadlineBinding.wrappedValue
            default:
                break
            }
        }
        .onDisappear {
            // Deleted once the screen is gone, so the closing animation never reads a deleted model.
            if deletesOnDisappear {
                context.delete(document)
                try? context.save()
            }
        }
    }

    // MARK: Approval

    private var approvalSection: some View {
        Section {
            if let data = document.signatureData, let image = UIImage(data: data) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 70, alignment: .leading)
                        .padding(10)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Client signature")
                    if !document.signerName.isEmpty {
                        Text("Signed by \(document.signerName)")
                            .font(.subheadline.weight(.medium))
                    }
                    if let signedAt = document.signedAt {
                        Text(signedAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(.vertical, 4)
                Button("Remove signature", systemImage: "xmark.circle", role: .destructive) {
                    document.removeSignature()
                }
            } else if document.hasOpenSignLink {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Waiting for the client to sign", systemImage: "hourglass")
                        .font(.subheadline.weight(.medium))
                    if let sent = document.signRequestSentAt {
                        Text("Link sent \(sent.formatted(.dateTime.day().month().hour().minute()))")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(.vertical, 4)
                Button("Share the link again", systemImage: "square.and.arrow.up") { shareSignLink() }
                Button("Check now", systemImage: "arrow.clockwise") {
                    Task { await SignLinkSync.run(notify: false) }
                }
                Button("Get client signature", systemImage: "signature") { showsSignature = true }
                Button("Cancel the link", systemImage: "xmark.circle", role: .destructive) { cancelSignLink() }
            } else {
                Button("Get client signature", systemImage: "signature") {
                    if store.isPro { showsSignature = true } else { showsPaywall = true }
                }
                Button {
                    if store.isPro { createSignLink() } else { showsPaywall = true }
                } label: {
                    HStack {
                        Label("Send a signing link", systemImage: "link")
                        if isCreatingSignLink {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isCreatingSignLink || document.allItems.isEmpty)
            }
        } header: {
            Text("Client approval")
        } footer: {
            if document.hasOpenSignLink {
                Text("When your client signs, the estimate is approved and you get a notification.")
            } else if document.signatureData == nil {
                Text("Hand the phone to your client, or send a link they can sign from anywhere. Signing approves the estimate and the signature is printed on the PDF.")
            }
        }
    }

    // MARK: Signing link

    private func createSignLink() {
        isCreatingSignLink = true
        let snapshot = DocumentSnapshot(document: document, profile: profile, showsBranding: !store.isPro)
        let secret = SignLink.newSecret()
        Task {
            defer { isCreatingSignLink = false }
            do {
                let created = try await SignLink.create(snapshot: snapshot, secret: secret)
                document.signRequestID = created.id
                document.signRequestURL = created.url.absoluteString
                document.signRequestSecret = secret
                document.signRequestSentAt = .now
                if document.status == .draft { document.apply(status: .sent) }
                try? context.save()
                SignLinkSync.scheduleIfNeeded()
                await ReminderScheduler.requestPermissionIfNeeded()
                shareSignLink()
            } catch {
                signLinkError = error.localizedDescription
            }
        }
    }

    private func shareSignLink() {
        guard let url = URL(string: document.signRequestURL) else { return }
        let snapshot = DocumentSnapshot(document: document, profile: profile, showsBranding: !store.isPro)
        signLinkShare = [ClientMessage.signLink(for: snapshot, url: url)]
    }

    private func cancelSignLink() {
        let id = document.signRequestID, secret = document.signRequestSecret
        document.clearSignLink()
        try? context.save()
        SignLinkSync.scheduleIfNeeded()
        Task { await SignLink.delete(id: id, secret: secret) }
    }

    // MARK: Totals

    @ViewBuilder
    private var totalsRows: some View {
        let totals = document.totals
        if totals.tax > 0 {
            LabeledContent("Subtotal") {
                Text(Money.string(totals.subtotal, locale: .current)).monospacedDigit()
            }
            LabeledContent("Tax") {
                Text(Money.string(totals.tax, locale: .current)).monospacedDigit()
            }
        }
        LabeledContent {
            Text(Money.string(totals.total, locale: .current))
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .contentTransition(.numericText())
        } label: {
            Text("Total").font(.headline)
        }
    }

    // MARK: Actions

    /// Documents made before dates existed get one the first time it is changed.
    private var deadlineBinding: Binding<Date> {
        Binding(
            get: {
                switch document.kind {
                case .estimate: document.validUntil ?? DocumentFactory.date(days: profile.estimateValidDays, after: document.createdAt)
                case .invoice: document.dueDate ?? DocumentFactory.date(days: profile.paymentDueDays, after: document.createdAt)
                }
            },
            set: { date in
                switch document.kind {
                case .estimate: document.validUntil = date
                case .invoice: document.dueDate = date
                }
            }
        )
    }

    private var nextRepeatBinding: Binding<Date> {
        Binding(
            get: { document.nextRepeatDate ?? .now },
            set: { document.nextRepeatDate = Calendar.current.startOfDay(for: $0) }
        )
    }

    private var statusBinding: Binding<DocumentStatus> {
        Binding(get: { document.status }, set: { setStatus($0) })
    }

    private var nextSortIndex: Int {
        (document.allItems.map(\.sortIndex).max() ?? -1) + 1
    }

    private func setStatus(_ status: DocumentStatus) {
        let before = document.status
        document.apply(status: status)
        if status != before, status == .paid || status == .approved { ReviewPrompt.goodMoment() }
    }

    private func addItem() {
        let line = LineItem(text: "", sortIndex: nextSortIndex)
        context.insert(line)
        line.document = document
        editingItem = line
    }

    private func deleteItems(at offsets: IndexSet) {
        let sorted = document.sortedItems
        for index in offsets {
            remove(sorted[index])
        }
    }

    private func remove(_ item: LineItem) {
        document.items?.removeAll { $0.persistentModelID == item.persistentModelID }
        context.delete(item)
    }

    /// Runs after the item sheet has closed, so nothing on screen still reads a deleted item.
    private func cleanUpItems() {
        if let item = itemPendingDeletion {
            itemPendingDeletion = nil
            remove(item)
        }
        // An item that was added and left blank would only clutter the client's PDF.
        for item in document.allItems where item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.unitPrice == 0 {
            remove(item)
        }
    }

    private func convertToInvoice() {
        guard store.isPro else {
            showsPaywall = true
            return
        }
        let invoice = DocumentFactory(context: context).makeInvoice(from: document, profile: profile)
        try? context.save()
        onOpen(invoice)
    }

    private func duplicate() {
        if document.kind == .estimate {
            guard store.canCreateEstimate else {
                showsPaywall = true
                return
            }
            store.recordEstimateCreated()
        }
        let copy = DocumentFactory(context: context).duplicate(document, profile: profile)
        try? context.save()
        onOpen(copy)
    }
}

// MARK: - Haptics

/// Approved or paid, a signing link sent, items added from a receipt or removed, an error.
private struct EditorHaptics: ViewModifier {
    let document: JobDocument
    let error: String?

    func body(content: Content) -> some View {
        let status = document.status
        let link = document.signRequestID
        let items = document.allItems.count
        return content
            .sensoryFeedback(.success, trigger: status) { (_: DocumentStatus, new: DocumentStatus) -> Bool in
                new == .approved || new == .paid
            }
            .sensoryFeedback(.success, trigger: link) { (old: String, new: String) -> Bool in old.isEmpty && !new.isEmpty }
            .sensoryFeedback(.success, trigger: items) { (old: Int, new: Int) -> Bool in new > old + 1 }
            .sensoryFeedback(.impact(weight: .light), trigger: items) { (old: Int, new: Int) -> Bool in new < old }
            .sensoryFeedback(.error, trigger: error) { (_: String?, new: String?) -> Bool in new != nil }
    }
}

// MARK: - Row

private struct LineItemRow: View {
    let item: LineItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text.isEmpty ? String(localized: "New item") : item.text)
                    .foregroundStyle(item.text.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if item.unitPrice > 0 {
                Text(Money.string(item.amount, locale: .current))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            } else {
                Text("Add price")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        let quantity = Money.quantity(item.quantity) + (item.unit.isEmpty ? "" : " \(item.unit)")
        return "\(quantity) × \(Money.string(item.unitPrice, locale: .current))"
    }
}

// MARK: - Line item sheet

struct LineItemSheet: View {
    @Bindable var item: LineItem
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field { case text, price }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("What is being done or supplied", text: $item.text, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focus, equals: .text)
                }
                Section {
                    LabeledContent("Quantity") {
                        TextField("1", value: $item.quantity, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    LabeledContent("Unit") {
                        TextField("each", text: $item.unit)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    }
                    LabeledContent("Price per unit ($)") {
                        MoneyField(title: "0", value: $item.unitPrice)
                            .focused($focus, equals: .price)
                    }
                    LabeledContent("Your cost per unit ($)") {
                        MoneyField(title: "0", value: $item.unitCost)
                    }
                    LabeledContent("Line total") {
                        Text(Money.string(item.amount, locale: .current))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.primary)
                    }
                } footer: {
                    Text("Your cost is only for your profit report. The client never sees it.")
                }
                Section {
                    Toggle("Labor", isOn: $item.isLabor)
                    Toggle("Taxable", isOn: $item.isTaxable)
                }
                Section {
                    Button("Delete item", systemImage: "trash", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if item.text.isEmpty {
                    focus = .text
                } else if item.unitPrice <= 0 {
                    focus = .price
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Price book picker

struct PriceBookPicker: View {
    var onPick: (PriceBookItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PriceBookItem.useCount, order: .reverse) private var entries: [PriceBookItem]
    @State private var search = ""

    private var filtered: [PriceBookItem] {
        search.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { entry in
                Button {
                    onPick(entry)
                    dismiss()
                } label: {
                    HStack {
                        Text(entry.name).foregroundStyle(Color.primary)
                        Spacer()
                        Text(Money.string(entry.unitPrice, locale: .current) + (entry.unit.isEmpty ? "" : " / \(entry.unit)"))
                            .foregroundStyle(Color.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("My prices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
