import PhotosUI
import StoreKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Bindable var profile: BusinessProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionStore.self) private var store
    @State private var logoSelection: PhotosPickerItem?
    @State private var showsPaywall = false
    @State private var showsManage = false

    var body: some View {
        NavigationStack {
            Form {
                subscriptionSection

                Section("Your business") {
                    TextField("Business name", text: $profile.businessName)
                        .textContentType(.organizationName)
                    TextField("Your name", text: $profile.ownerName)
                        .textContentType(.name)
                    TextField("Phone", text: $profile.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $profile.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Address", text: $profile.address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                    TextField("License number", text: $profile.licenseNumber)
                        .autocorrectionDisabled()
                    Picker("Trade", selection: $profile.tradeRaw) {
                        ForEach(Trade.allCases) { trade in
                            Text(trade.label).tag(trade.rawValue)
                        }
                    }
                    if profile.trade == .other {
                        TextField("What do you do? For example: pool cleaning", text: $profile.customTrade)
                            .textInputAutocapitalization(.sentences)
                    }
                }

                logoSection

                Section {
                    Picker("Document language", selection: $profile.documentLanguageRaw) {
                        ForEach(DocumentLanguage.allCases) { language in
                            Text(language.label).tag(language.rawValue)
                        }
                    }
                    LabeledContent("Sales tax (%)") {
                        TextField("0", value: $profile.defaultTaxRate, format: .number.precision(.fractionLength(0...3)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    LabeledContent("Markup on materials (%)") {
                        TextField("0", value: $profile.materialMarkupPercent, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Defaults for new estimates")
                } footer: {
                    Text("Speak in any language. The estimate is written in the document language.")
                }

                Section {
                    Stepper(value: $profile.estimateValidDays, in: 1...180) {
                        LabeledContent("Estimates valid for", value: String(localized: "\(profile.estimateValidDays) days"))
                    }
                    Stepper(value: $profile.paymentDueDays, in: 0...120) {
                        LabeledContent("Payment due after", value: String(localized: "\(profile.paymentDueDays) days"))
                    }
                    Toggle("Reminders", isOn: $profile.remindersEnabled)
                        .onChange(of: profile.remindersEnabled) { _, on in
                            Task {
                                if on { await ReminderScheduler.requestPermissionIfNeeded() }
                                await ReminderScheduler.sync()
                            }
                        }
                } header: {
                    Text("Dates and reminders")
                } footer: {
                    Text("Precia reminds you when an estimate has waited \(ReminderScheduler.followUpDays) days for an answer and when an invoice is past due.")
                }

                Section {
                    TextField("Example: 50% deposit to start, balance on completion.", text: $profile.terms, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Terms")
                } footer: {
                    Text("Printed at the bottom of every document.")
                }

                Section {
                    TextField("Example: Zelle 555-123-4567, check or cash.", text: $profile.paymentInstructions, axis: .vertical)
                        .lineLimit(2...6)
                    LabeledContent("Deposit to start (%)") {
                        PercentField(value: $profile.defaultDepositPercent)
                    }
                } header: {
                    Text("How clients pay you")
                } footer: {
                    Text("Printed on invoices, and on estimates that ask for a deposit. New estimates ask for this deposit; 0 means none.")
                }

                iCloudSection

                Section {
                    NavigationLink {
                        ClientListView()
                    } label: {
                        Label("Clients", systemImage: "person.2.fill")
                    }
                    NavigationLink {
                        PriceBookView()
                    } label: {
                        Label("My prices", systemImage: "book.closed.fill")
                    }
                }

                Section {
                    Link(destination: AppLinks.supportPage) {
                        Label("Help and FAQ", systemImage: "questionmark.circle.fill")
                    }
                    if let review = AppLinks.writeReview {
                        Link(destination: review) {
                            Label("Rate Precia on the App Store", systemImage: "star.fill")
                        }
                    }
                    Link(destination: AppLinks.support) {
                        Label("Contact support", systemImage: "envelope.fill")
                    }
                    Link(destination: AppLinks.privacy) {
                        Label("Privacy policy", systemImage: "hand.raised.fill")
                    }
                    Link(destination: AppLinks.terms) {
                        Label("Terms of use", systemImage: "doc.plaintext.fill")
                    }
                } footer: {
                    Text("Precia \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .readableListWidth()
            .sensoryFeedback(.selection, trigger: profile.estimateValidDays)
            .sensoryFeedback(.selection, trigger: profile.paymentDueDays)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .manageSubscriptionsSheet(isPresented: $showsManage)
            .onChange(of: logoSelection) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        profile.logoData = Self.preparedLogo(from: data)
                    }
                    logoSelection = nil
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var iCloudSection: some View {
        let signedIn = FileManager.default.ubiquityIdentityToken != nil
        Section {
            if !AppDatabase.syncsWithICloud {
                Label("iCloud sync isn't available right now", systemImage: "exclamationmark.icloud")
            } else if signedIn {
                Label("Synced with iCloud", systemImage: "checkmark.icloud")
            } else {
                Label("Sign in to iCloud in the Settings app to back up and sync", systemImage: "icloud.slash")
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Your jobs, clients and prices are kept in your private iCloud and appear on every iPhone and iPad signed in to your Apple Account. We can't see them.")
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            if store.isPro {
                LabeledContent {
                    Text("Active").foregroundStyle(.green)
                } label: {
                    Label("Precia Pro", systemImage: "crown.fill")
                }
                Button("Manage subscription") { showsManage = true }
            } else {
                Button {
                    showsPaywall = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "crown.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to Precia Pro")
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Text("Unlimited estimates, invoices and your logo.")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
        }
    }

    private var logoSection: some View {
        Section {
            HStack(spacing: 14) {
                if let data = profile.logoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(Color.secondary)
                        .frame(width: 56, height: 56)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if store.isPro {
                    let hasLogo = profile.logoData != nil
                    PhotosPicker(selection: $logoSelection, matching: .images) {
                        Text(hasLogo ? "Change logo" : "Choose logo")
                    }
                } else {
                    Button("Choose logo") { showsPaywall = true }
                }
                Spacer()
                if profile.logoData != nil {
                    Button("Remove", role: .destructive) { profile.logoData = nil }
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Logo")
        } footer: {
            if !store.isPro {
                Text("Your logo on estimates and invoices is part of Precia Pro.")
            }
        }
    }

    /// Scales the picked photo down so PDFs stay small enough to text or email.
    private static func preparedLogo(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 600
        let scale = min(maxSide / max(image.size.width, image.size.height), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
