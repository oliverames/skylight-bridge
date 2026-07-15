enum NavigationSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case photos
    case reminders
    case chores
    case recipes
    case meals
    case activity
    case account
    case sync
    case diagnostics

    var id: Self { self }

    /// Sync-source sections, shown as the top sidebar group.
    static let sources: [NavigationSection] = [
        .overview, .photos, .reminders, .chores, .recipes, .meals, .activity
    ]

    /// Account and configuration sections, shown as the lower sidebar group.
    /// Bringing these into the main window keeps everything, including sign-in,
    /// in one place instead of a separate Settings pane.
    static let configuration: [NavigationSection] = [
        .account, .sync, .diagnostics
    ]

    var title: String {
        switch self {
        case .overview: "Overview"
        case .photos: "Photos"
        case .reminders: "Reminders"
        case .chores: "Chores"
        case .recipes: "Recipes"
        case .meals: "Meals"
        case .activity: "Activity"
        case .account: "Account"
        case .sync: "Sync"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .photos: "photo.on.rectangle.angled"
        case .reminders: "checklist"
        case .chores: "person.2.badge.gearshape"
        case .recipes: "book.closed"
        case .meals: "fork.knife"
        case .activity: "clock.arrow.circlepath"
        case .account: "person.crop.circle"
        case .sync: "arrow.triangle.2.circlepath"
        case .diagnostics: "stethoscope"
        }
    }
}
