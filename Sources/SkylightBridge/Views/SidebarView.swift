import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavigationSection

    var body: some View {
        List(NavigationSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
                .accessibilityIdentifier("sidebar.\(section.rawValue)")
        }
        .listStyle(.sidebar)
        .navigationTitle("Skylight Bridge")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    }
}
