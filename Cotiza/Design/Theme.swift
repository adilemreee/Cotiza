import SwiftUI

// MARK: - Localized labels for model enums

extension DocumentKind {
    var label: LocalizedStringResource {
        switch self {
        case .estimate: "Estimate"
        case .invoice: "Invoice"
        }
    }
}

extension DocumentStatus {
    var label: LocalizedStringResource {
        switch self {
        case .draft: "Draft"
        case .sent: "Sent"
        case .approved: "Approved"
        case .paid: "Paid"
        }
    }

    var color: Color {
        switch self {
        case .draft: .secondary
        case .sent: .blue
        case .approved: .orange
        case .paid: .green
        }
    }

    var symbol: String {
        switch self {
        case .draft: "pencil.circle.fill"
        case .sent: "paperplane.circle.fill"
        case .approved: "hand.thumbsup.circle.fill"
        case .paid: "checkmark.circle.fill"
        }
    }
}

extension RepeatInterval {
    var label: LocalizedStringResource {
        switch self {
        case .never: "Never"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Every month"
        }
    }
}

extension PaymentMethod {
    var label: LocalizedStringResource {
        switch self {
        case .cash: "Cash"
        case .check: "Check"
        case .zelle: "Zelle"
        case .cashApp: "Cash App"
        case .venmo: "Venmo"
        case .card: "Card"
        case .other: "Other"
        }
    }
}

extension DocumentLanguage {
    var label: LocalizedStringResource {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        }
    }
}

extension Trade {
    var label: LocalizedStringResource {
        switch self {
        case .general: "General contractor"
        case .painting: "Painting"
        case .landscaping: "Landscaping"
        case .cleaning: "Cleaning"
        case .flooring: "Flooring"
        case .roofing: "Roofing"
        case .plumbing: "Plumbing"
        case .electrical: "Electrical"
        case .drywall: "Drywall"
        case .concrete: "Concrete"
        case .hvac: "Heating & air"
        case .handyman: "Handyman"
        case .other: "Other"
        }
    }
}

// MARK: - Shared pieces

struct StatusBadge: View {
    let status: DocumentStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.14), in: Capsule())
    }
}

/// Full-width primary action used at the bottom of screens.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            // Capped so the button stays a comfortable size on wide and unfolded screens.
            .frame(maxWidth: 520, minHeight: 28)
            .padding(.vertical, 13)
            .padding(.horizontal, 20)
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension View {
    /// Keeps text blocks at a readable measure and centers them on wide screens.
    func readableWidth(_ width: CGFloat = 600, alignment: Alignment = .center) -> some View {
        frame(maxWidth: width, alignment: alignment)
            .frame(maxWidth: .infinity)
    }

    /// Keeps a List or Form at a comfortable reading width on iPad and unfolded screens.
    /// On a phone the system's own margins are kept.
    func readableListWidth(_ width: CGFloat = 720) -> some View {
        modifier(ReadableListWidth(maxWidth: width))
    }

    /// Card surface used on the home screen and paywall.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Text field bound to a money amount. Empty when the value is zero so the placeholder shows.
struct MoneyField: View {
    let title: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
    }
}

/// Text field for a share from 0 to 100, such as a deposit.
struct PercentField: View {
    @Binding var value: Double

    var body: some View {
        TextField("0", value: Binding(get: { value }, set: { value = min(max($0, 0), 100) }),
                  format: .number.precision(.fractionLength(0...1)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
    }
}

private struct ReadableListWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // nil keeps the default margins where the screen is narrow enough already.
            .contentMargins(.horizontal, width > maxWidth + 40 ? (width - maxWidth) / 2 : nil, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }
}
