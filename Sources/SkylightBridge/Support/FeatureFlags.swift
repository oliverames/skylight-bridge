/// Compile-time feature switches.
enum FeatureFlags {
    /// Multi-device coordination publishes `ClientHeartbeat` and
    /// `SharedSyncState` records to CloudKit and reads them back to warn about
    /// two Macs syncing one frame. Those two record types are not deployed to
    /// the production CloudKit schema, so with this on, every sync surfaces a
    /// "Did not find record type" / "needs its schema deployed" message to the
    /// user. Keep it off until the schema is deployed to production; the rest
    /// of shared-iCloud state (preferences, selected photos) uses already
    /// deployed types and is unaffected.
    static let multiDeviceCoordinationEnabled = false

    /// The Meals workflow is hidden from the sidebar and Overview while it is
    /// unfinished. This flag makes hidden mean off: a meal selection enabled
    /// before the hiding must not keep syncing with no interface to see or
    /// stop it. Re-enable the UI (NavigationSection.sources, OverviewView) and
    /// this flag together.
    static let mealSyncEnabled = false
}
