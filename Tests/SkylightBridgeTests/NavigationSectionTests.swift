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
}
