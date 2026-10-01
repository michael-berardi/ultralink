import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var monitor: Monitor
    @AppStorage("dishAddress") private var address = ""
    @AppStorage("menuBarReadout") private var readout = MenuBarReadout.speeds.rawValue
    @AppStorage("notifyOutages") private var notify = true
    @AppStorage("demoMode") private var demo = false
    @State private var login = LoginItem.enabled
    @State private var test: String?
    @State private var testing = false
    @State private var confirmErase = false
    @StateObject private var updates = Updates.shared

    var body: some View {
        Form {
            Section("Dish") {
                HStack {
                    TextField("Address", text: $address, prompt: Text("192.168.100.1"))
                        .onSubmit { monitor.restart() }
                    Button(testing ? "Testing…" : "Test") { runTest() }.disabled(testing)
                }
                if let test { Text(test).font(.caption).foregroundStyle(test.hasPrefix("Connected") ? .green : .red) }
                Text("Starlink dishes answer at 192.168.100.1 on the Starlink router's network. Leave this empty unless your setup is different.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Picker("Show", selection: $readout) {
                    ForEach(MenuBarReadout.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Open at login", isOn: $login).onChange(of: login) { LoginItem.set($0) }
                Toggle("Notify me about outages", isOn: $notify).onChange(of: notify) { if $0 { monitor.requestNotificationPermission() } }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(get: { updates.automatic }, set: { updates.automatic = $0 }))
                Button("Check Now") { updates.checkForUpdates() }
            }
            Section("Data") {
                Toggle("Demo mode", isOn: $demo).onChange(of: demo) { monitor.configure(demo: $0) }
                Button("Erase History…", role: .destructive) { confirmErase = true }.disabled(monitor.demo)
                    .confirmationDialog("Erase all saved history?", isPresented: $confirmErase) {
                        Button("Erase", role: .destructive) { monitor.eraseHistory() }
                    } message: { Text("Charts and data totals start over. The dish itself is not touched.") }
                Text("UltraLink keeps a week of per-minute readings in ~/Library/Application Support/UltraLink. It never sends anything off your Mac and never changes your dish.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Text("UltraLink \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    Spacer()
                    Link("Source on GitHub", destination: URL(string: "https://github.com/michael-berardi/ultralink")!)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }

    private func runTest() {
        testing = true; test = nil
        let host = address.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "192.168.100.1"
        Task {
            do {
                let s = try await Monitor.client(for: host).status()
                test = "Connected: \(s.hardwareName), software \(s.software)"
            } catch { test = error.localizedDescription }
            testing = false
        }
    }
}
