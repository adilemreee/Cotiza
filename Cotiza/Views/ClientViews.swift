import SwiftData
import SwiftUI

/// Choose, create or clear the client on a document.
struct ClientPickerView: View {
    @Binding var selection: Client?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.name) private var clients: [Client]
    @State private var search = ""
    @State private var editing: Client?
    @State private var created: Client?
    @State private var showsContacts = false

    private var filtered: [Client] {
        search.isEmpty ? clients : clients.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("New client", systemImage: "person.crop.circle.badge.plus") {
                        let client = Client(name: search.trimmingCharacters(in: .whitespaces))
                        context.insert(client)
                        selection = client
                        created = client
                        editing = client
                    }
                    Button("Choose from Contacts", systemImage: "person.crop.square.filled.and.at.rectangle") {
                        showsContacts = true
                    }
                }
                Section {
                    ForEach(filtered) { client in
                        Button {
                            selection = client
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.name.isEmpty ? String(localized: "Unnamed client") : client.name)
                                        .foregroundStyle(Color.primary)
                                    if !client.phone.isEmpty {
                                        Text(client.phone).font(.subheadline).foregroundStyle(Color.secondary)
                                    }
                                }
                                Spacer()
                                if client == selection {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Edit", systemImage: "pencil") { editing = client }
                                .tint(.blue)
                        }
                    }
                }
                if selection != nil {
                    Section {
                        Button("Remove client from this document", role: .destructive) {
                            selection = nil
                            dismiss()
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search or type a new name")
            .sensoryFeedback(.selection, trigger: selection?.persistentModelID)
            .navigationTitle("Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $editing, onDismiss: {
                if let client = created, client.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    if selection?.persistentModelID == client.persistentModelID { selection = nil }
                    context.delete(client)
                }
                created = nil
                dismiss()
            }) { client in
                ClientEditView(client: client)
            }
            .contactPicker(isPresented: $showsContacts) { contact in
                // The same person picked twice stays one client.
                let existing = clients.first { $0.name.compare(contact.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                let client = existing ?? {
                    let client = Client(name: contact.name)
                    context.insert(client)
                    return client
                }()
                contact.fill(client)
                selection = client
                dismiss()
            }
        }
    }
}

struct ClientEditView: View {
    @Bindable var client: Client
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var showsContacts = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $client.name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                    TextField("Phone", text: $client.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $client.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Job address", text: $client.address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                }
                Section {
                    Button("Fill in from Contacts", systemImage: "person.crop.square.filled.and.at.rectangle") {
                        showsContacts = true
                    }
                }
            }
            .navigationTitle("Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { if client.name.isEmpty { nameFocused = true } }
            .contactPicker(isPresented: $showsContacts) { $0.fill(client) }
        }
    }
}

/// All clients, reachable from Settings.
struct ClientListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.name) private var clients: [Client]
    @State private var editing: Client?
    @State private var created: Client?

    var body: some View {
        List {
            ForEach(clients) { client in
                Button {
                    editing = client
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name.isEmpty ? String(localized: "Unnamed client") : client.name)
                            .foregroundStyle(Color.primary)
                        Text("Documents: \(client.documents?.count ?? 0)")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(clients[index]) }
            }
        }
        .overlay {
            if clients.isEmpty {
                ContentUnavailableView("No clients yet", systemImage: "person.2", description: Text("Clients are saved when you add them to an estimate."))
            }
        }
        .navigationTitle("Clients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New client", systemImage: "plus") {
                    let client = Client(name: "")
                    context.insert(client)
                    created = client
                    editing = client
                }
            }
        }
        .sheet(item: $editing, onDismiss: {
            if let client = created, client.name.trimmingCharacters(in: .whitespaces).isEmpty {
                context.delete(client)
            }
            created = nil
        }) { client in
            ClientEditView(client: client)
        }
    }
}

/// Saved prices, reachable from Settings.
struct PriceBookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PriceBookItem.name) private var entries: [PriceBookItem]
    @State private var editing: PriceBookItem?
    @State private var created: PriceBookItem?

    var body: some View {
        List {
            ForEach(entries) { entry in
                Button {
                    editing = entry
                } label: {
                    HStack {
                        Text(entry.name.isEmpty ? String(localized: "New item") : entry.name)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text(Money.string(entry.unitPrice, locale: .current) + (entry.unit.isEmpty ? "" : " / \(entry.unit)"))
                            .foregroundStyle(Color.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(entries[index]) }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("No saved prices", systemImage: "book.closed", description: Text("Precia remembers your prices each time you send an estimate."))
            }
        }
        .navigationTitle("My prices")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add price", systemImage: "plus") {
                    let entry = PriceBookItem(name: "", unitPrice: 0)
                    context.insert(entry)
                    created = entry
                    editing = entry
                }
            }
        }
        .sheet(item: $editing, onDismiss: {
            if let entry = created, entry.name.trimmingCharacters(in: .whitespaces).isEmpty {
                context.delete(entry)
            }
            created = nil
        }) { entry in
            PriceBookEditView(entry: entry)
        }
    }
}

private struct PriceBookEditView: View {
    @Bindable var entry: PriceBookItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $entry.name, axis: .vertical)
                LabeledContent("Unit") {
                    TextField("each", text: $entry.unit)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                }
                LabeledContent("Price per unit ($)") {
                    MoneyField(title: "0", value: $entry.unitPrice)
                }
                Toggle("Labor", isOn: $entry.isLabor)
            }
            .navigationTitle("Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
