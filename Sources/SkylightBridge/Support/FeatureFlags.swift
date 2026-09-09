/// Compile-time feature switches.
enum FeatureFlags {
    /// Shared sync links remain disabled. Enabling multiple Mac writers needs
    /// validated exclusive ownership, interruption recovery, deletion handling,
    /// frame/account isolation, and a deployed SharedSyncState schema.
    /// Schema deployment alone is insufficient. The warning-only heartbeat
    /// was removed because it never granted exclusive permission to write.
    /// Shared preferences and selected photos use separate deployed types.
    static let multiDeviceCoordinationEnabled = false

    /// The Meals workflow is hidden from the sidebar and Overview while it is
    /// unfinished. This flag makes hidden mean off: a meal selection enabled
    /// before the hiding must not keep syncing with no interface to see or
    /// stop it. Re-enable the UI (NavigationSection.sources, OverviewView) and
    /// this flag together.
    static let mealSyncEnabled = false
}
