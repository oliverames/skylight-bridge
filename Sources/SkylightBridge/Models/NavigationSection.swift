enum NavigationSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case photos
    case reminders
    case recipes
    case meals
    case activity
    case apiCoverage

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .photos: "Photos"
        case .reminders: "Reminders"
        case .recipes: "Recipes"
        case .meals: "Meals"
        case .activity: "Activity"
        case .apiCoverage: "API Coverage"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .photos: "photo.on.rectangle.angled"
        case .reminders: "checklist"
        case .recipes: "book.closed"
        case .meals: "fork.knife"
        case .activity: "clock.arrow.circlepath"
        case .apiCoverage: "network"
        }
    }
}
