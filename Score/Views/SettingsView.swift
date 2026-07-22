import SwiftUI

struct SettingsView: View {
    @Environment(ScoreStore.self) private var store
    @State private var server = UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
    var body: some View {
        Form {
            TextField("Score server", text: $server)
            Button("Save") { if let url = URL(string: server) { store.serverURL = url; UserDefaults.standard.set(server, forKey: "serverURL") } }
            if let account = store.account { LabeledContent("Signed in", value: "\(account.name) · \(account.role.label)"); Button("Log out", role: .destructive) { store.signOut() } }
        }.padding().frame(minWidth: 420)
    }
}
