import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        TabView {
            Form {
                TextField("API base URL", text: $store.configuration.account.baseURL)
                TextField("API version", text: $store.configuration.account.apiVersion)

                if store.skylightFrames.isEmpty {
                    TextField("Frame ID", text: $store.configuration.account.frameID)
                    TextField("Device ID", text: $store.configuration.account.deviceID)
                } else {
                    Picker("Frame", selection: $store.configuration.account.frameID) {
                        ForEach(store.skylightFrames, id: \.id) { frame in
                            Text(frame.attributes.name ?? frame.id).tag(frame.id)
                        }
                    }
                    .onChange(of: store.configuration.account.frameID) {
                        Task { await store.selectFrame(store.configuration.account.frameID) }
                    }

                    Picker("Device", selection: $store.configuration.account.deviceID) {
                        Text("No device selected").tag("")
                        ForEach(store.skylightDevices, id: \.id) { device in
                            Text(device.attributes.name ?? device.id).tag(device.id)
                        }
                    }
                }

                Divider()

                TextField("Skylight email", text: $email)
                SecureField("Skylight password", text: $password)
                Text("Credentials are stored only in the macOS Keychain. OAuth access and rotating refresh tokens are used for API requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button(store.isConnecting ? "Connecting…" : "Connect and Save") {
                        Task {
                            await store.saveAccountCredentials(email: email, password: password)
                            password = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isConnecting)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Account", systemImage: "person.crop.circle") }

            Form {
                Stepper(
                    "Sync every \(store.configuration.syncIntervalMinutes) minutes",
                    value: $store.configuration.syncIntervalMinutes,
                    in: 10...240,
                    step: 5
                )
                Toggle("Launch at login", isOn: $store.configuration.launchAtLogin)
                Toggle("Dry run", isOn: $store.configuration.dryRun)
                Text("Dry run plans and logs changes without modifying Skylight or Apple data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Save Settings") { store.saveConfiguration() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 620, height: 420)
        .scenePadding()
        .task {
            email = await store.storedAccountEmail()
            await store.restoreAccountConnection()
        }
    }
}
