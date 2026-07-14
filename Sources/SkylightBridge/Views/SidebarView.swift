import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavigationSection

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(NavigationSection.sources) { section in
                    row(section)
                }
            }
            Section("Configuration") {
                ForEach(NavigationSection.configuration) { section in
                    row(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Skylight Bridge")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    private func row(_ section: NavigationSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
            .accessibilityIdentifier("sidebar.\(section.rawValue)")
    }
}
