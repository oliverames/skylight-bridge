import Testing
@testable import SkylightBridge

struct NavigationSectionTests {
    @Test("Configuration follows setup-to-support order")
    func configurationOrder() {
        #expect(NavigationSection.configuration == [
            .account,
            .sync,
            .activity,
            .diagnostics
        ])
    }

    @Test("Every navigation section except hidden Meals reaches the sidebar exactly once")
    func sidebarGroupsCoverAllVisibleSections() {
        let grouped = NavigationSection.sources + NavigationSection.configuration

        // A new section forgotten in a sidebar group would be unreachable UI.
        #expect(grouped.count == Set(grouped).count)
        #expect(Set(grouped) == Set(NavigationSection.allCases).subtracting([.meals]))
    }
}
