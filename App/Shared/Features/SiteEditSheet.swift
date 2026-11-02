import SwiftUI
import StarlinkKit

enum SiteSheetTarget: Identifiable {
    case add
    case edit(Site)
    var id: String { switch self { case .add: "add"; case .edit(let s): s.id.uuidString } }
}

/// Add or edit a saved site. Deleting the current site is refused here too — switch to another site first.
struct SiteEditSheet: View {
    @Environment(StarlinkSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let editing: Site?

    @State private var name: String
    @State private var routerHost: String
    @State private var dishHost: String

    init(editing: Site?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _routerHost = State(initialValue: editing?.routerHost ?? "192.168.1.1")
        _dishHost = State(initialValue: editing?.dishHost ?? "192.168.100.1")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. “Cabin”, “Boat”)", text: $name)
                    TextField("Router address", text: $routerHost)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                        #endif
                    TextField("Dish address", text: $dishHost)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                        #endif
                } footer: {
                    Text("Each site keeps its own history, alert rules and saved stall tests.")
                }
                if let editing {
                    Section {
                        Button("Delete site", role: .destructive) {
                            session.siteStore.remove(editing.id)
                            Task { await session.sync.sync() }
                            dismiss()
                        }
                        .disabled(editing.id == session.currentSite.id || session.siteStore.sites.count <= 1)
                    } footer: {
                        if editing.id == session.currentSite.id {
                            Text("Switch to another site before deleting this one.")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add site" : "Edit site")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let editing {
                            var updated = editing
                            updated.name = name; updated.routerHost = routerHost; updated.dishHost = dishHost
                            session.siteStore.update(updated)
                            if updated.id == session.currentSite.id {
                                session.routerHost = routerHost
                                session.dishHost = dishHost
                                session.refreshCurrentSiteFromStore()
                                session.reconnect()
                            }
                        } else {
                            session.siteStore.add(Site(name: name.isEmpty ? "New site" : name, routerHost: routerHost, dishHost: dishHost))
                        }
                        Task { await session.sync.sync() }
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 320)
        #endif
    }
}
