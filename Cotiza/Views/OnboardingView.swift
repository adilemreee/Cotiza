import SwiftData
import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var profiles: [BusinessProfile]
    @State private var step = 0
    @State private var businessName = ""
    @State private var phone = ""
    @State private var trade: Trade = .general
    @State private var customTrade = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    welcome
                } else {
                    setup
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.tint)
                            .padding(.bottom, 4)
                        Text("Say the job. Send the estimate.")
                            .font(.largeTitle.bold())
                        Text("Describe the work in Spanish or English. Precia writes a professional estimate your client can approve on the spot.")
                            .font(.body)
                            .foregroundStyle(Color.secondary)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        benefit("mic.fill", "Talk, don't type", "Prices, quantities and tasks become line items automatically.")
                        benefit("globe.americas.fill", "Speak Spanish, send English", "Your client gets a clean estimate in the language they read.")
                        benefit("lock.fill", "Private by design", "No account, no ads. Your jobs and prices stay with you.")
                    }
                }
                .readableWidth(alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 24)
            }
            Button("Get started") {
                withAnimation(.smooth) { step = 1 }
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func benefit(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Color.secondary)
            }
        }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Business name", text: $businessName)
                        .textContentType(.organizationName)
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Your business")
                } footer: {
                    Text("This appears at the top of every estimate. You can change it later.")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        ForEach(Trade.allCases) { option in
                            tradeButton(option)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    if trade == .other {
                        TextField("What do you do? For example: pool cleaning", text: $customTrade)
                            .textInputAutocapitalization(.sentences)
                    }
                } header: {
                    Text("What kind of work do you do?")
                } footer: {
                    if trade == .other {
                        Text("Precia uses this to understand the jobs you describe.")
                    }
                }
            }
            Button("Continue") { finish() }
                .accessibilityIdentifier("onboarding.continue")
                .buttonStyle(.primary)
                .disabled(businessName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Set up")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", systemImage: "chevron.left") {
                    withAnimation(.smooth) { step = 0 }
                }
            }
        }
        .onAppear { nameFocused = true }
    }

    private func tradeButton(_ option: Trade) -> some View {
        let selected = option == trade
        return Button {
            trade = option
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.symbol)
                    .font(.title3)
                Text(option.label)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: trade)
    }

    private func finish() {
        let profile = profiles.first ?? {
            let created = BusinessProfile()
            // Documents start in the phone's language; Settings changes it.
            created.documentLanguage = .device
            // Amounts start in the phone region's currency, and stay in it if the region changes later.
            created.currency = Money.regionCurrency
            context.insert(created)
            return created
        }()
        profile.businessName = businessName.trimmingCharacters(in: .whitespaces)
        profile.phone = phone.trimmingCharacters(in: .whitespaces)
        profile.trade = trade
        profile.customTrade = trade == .other ? customTrade.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        try? context.save()
        onFinish()
    }
}
