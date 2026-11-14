import SwiftData
import SwiftUI

/// Income, materials and profit for a month or a year, exportable for the accountant.
struct ReportView: View {
    let profile: BusinessProfile

    @Environment(\.dismiss) private var dismiss
    @Query private var documents: [JobDocument]
    @State private var period: ProfitReport.Period = .month
    @State private var anchor = Date.now
    @State private var files: (csv: URL, pdf: URL)?

    private var calendar: Calendar { .current }

    private var report: ProfitReport {
        ProfitReport(rows: documents.compactMap(ProfitReport.Row.init), period: period, containing: anchor)
    }

    private var canGoForward: Bool { report.interval.end <= .now }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $period) {
                        Text("Month").tag(ProfitReport.Period.month)
                        Text("Year").tag(ProfitReport.Period.year)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    HStack {
                        Button("Previous", systemImage: "chevron.left") { move(-1) }
                            .labelStyle(.iconOnly)
                        Spacer()
                        Text(report.periodTitle(period, locale: .current))
                            .font(.headline)
                        Spacer()
                        Button("Next", systemImage: "chevron.right") { move(1) }
                            .labelStyle(.iconOnly)
                            .disabled(!canGoForward)
                    }
                    .buttonStyle(.borderless)
                }
                Section {
                    row("Revenue (before tax)", report.revenue)
                    row("Sales tax collected", report.tax)
                    row("Materials cost", -report.materialsCost)
                    LabeledContent {
                        Text(Money.string(report.profit, locale: .current))
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(report.profit >= 0 ? Color.green : Color.red)
                    } label: {
                        Text("Profit").font(.headline)
                    }
                } footer: {
                    Text("Income is counted on the day a job is marked paid. Materials cost comes from scanned receipts and the cost you enter on each item.")
                }
                Section {
                    if report.rows.isEmpty {
                        Text("No jobs were paid in this period.")
                            .foregroundStyle(Color.secondary)
                    }
                    ForEach(report.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.client.isEmpty ? (row.job.isEmpty ? row.number : row.job) : row.client)
                                    .lineLimit(1)
                                Text("\(row.number) · \(row.paidAt.formatted(.dateTime.month(.abbreviated).day()))")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(Money.string(row.revenue, locale: .current)).monospacedDigit()
                                if row.materialsCost > 0 {
                                    Text("Profit \(Money.string(row.profit, locale: .current))")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                } header: {
                    Text("Jobs paid: \(report.rows.count)")
                }
            }
            .readableListWidth()
            .sensoryFeedback(.selection, trigger: period)
            .sensoryFeedback(.selection, trigger: anchor)
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let files {
                        Menu("Export", systemImage: "square.and.arrow.up") {
                            ShareLink("Spreadsheet (CSV)", item: files.csv)
                            ShareLink("PDF summary", item: files.pdf)
                        }
                    }
                }
            }
            .task(id: "\(period.rawValue)-\(report.interval.start.timeIntervalSince1970)-\(report.rows.count)-\(report.total)") {
                let name = profile.businessName.isEmpty ? profile.ownerName : profile.businessName
                files = try? report.writeFiles(period: period, business: name, language: profile.documentLanguage)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Double) -> some View {
        LabeledContent(title) {
            Text(Money.string(value, locale: .current)).monospacedDigit()
        }
    }

    private func move(_ step: Int) {
        let component: Calendar.Component = period == .month ? .month : .year
        anchor = calendar.date(byAdding: component, value: step, to: anchor) ?? anchor
    }
}
