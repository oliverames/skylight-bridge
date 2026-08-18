import ApplicationServices
@preconcurrency import Foundation

enum AppleNotesStoreError: Error, LocalizedError, Sendable {
    case accessDenied
    case authorizationUnavailable
    case scriptCreationFailed
    case automationFailed(String)
    case malformedResponse(String)
    case folderNotFound(String)
    case noteNotFound(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Apple Notes access is not authorized."
        case .authorizationUnavailable:
            "Apple Notes could not present its access request."
        case .scriptCreationFailed:
            "The Apple Notes automation script could not be created."
        case let .automationFailed(message):
            "Apple Notes automation failed: \(message)"
        case let .malformedResponse(message):
            "Apple Notes returned malformed data: \(message)"
        case let .folderNotFound(identifier):
            "Apple Notes folder \(identifier) was not found."
        case let .noteNotFound(identifier):
            "Apple Note \(identifier) was not found."
        }
    }
}

enum AppleNotesAuthorizationStatus: Sendable {
    case granted
    case denied
    case notDetermined
    /// The permission could not be checked, e.g. because Notes is not running.
    case unknown
}

actor AppleNotesStore {
    /// Queries the Automation (Apple Events) permission for Notes without
    /// prompting. Returns `.unknown` when Notes is not running, because the
    /// permission check needs a live target process to resolve against.
    nonisolated static func authorizationStatus() -> AppleNotesAuthorizationStatus {
        authorizationStatus(askUserIfNeeded: false)
    }

    /// Explicitly asks macOS for Apple Events consent. Sending an AppleScript
    /// and relying on the destination app to prompt indirectly is denied by
    /// Tahoe's TCC prompt policy, so the user-facing button calls this first.
    func requestAccess() throws {
        switch Self.authorizationStatus(askUserIfNeeded: true) {
        case .granted:
            return
        case .denied:
            throw AppleNotesStoreError.accessDenied
        case .notDetermined, .unknown:
            throw AppleNotesStoreError.authorizationUnavailable
        }
    }

    private nonisolated static func authorizationStatus(
        askUserIfNeeded: Bool
    ) -> AppleNotesAuthorizationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unknown
        }
    }

    func accounts() throws -> [AppleNotesAccountSnapshot] {
        let descriptor = try execute(
            """
            tell application "Notes"
                set resultRows to {}
                repeat with accountItem in accounts
                    set accountItem to contents of accountItem
                    set end of resultRows to {id of accountItem as text, name of accountItem as text}
                end repeat
                return resultRows
            end tell
            """
        )

        return try rows(in: descriptor).map { row in
            AppleNotesAccountSnapshot(
                id: try requiredString(in: row, at: 1, field: "account id"),
                name: try requiredString(in: row, at: 2, field: "account name")
            )
        }
    }

    func folders() throws -> [AppleNotesFolderSnapshot] {
        let descriptor = try execute(Self.folderEnumerationScript)
        return try rows(in: descriptor)
            .map { row in
                let parentID = try requiredString(in: row, at: 4, field: "parent folder id")
                return AppleNotesFolderSnapshot(
                    id: try requiredString(in: row, at: 1, field: "folder id"),
                    name: try requiredString(in: row, at: 2, field: "folder name"),
                    accountID: try requiredString(in: row, at: 3, field: "folder account id"),
                    parentFolderID: parentID.isEmpty ? nil : parentID,
                    isShared: try requiredBoolean(in: row, at: 5, field: "folder shared state")
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func noteSummaries(inFolderID folderID: String) throws -> [AppleNoteSummarySnapshot] {
        let descriptor = try execute(
            Self.noteSelectionHandlers
                + "\n"
                + """
                set requestedFolderID to "\(appleScriptLiteral(folderID))"
                tell application "Notes"
                    set targetFolder to my findFolderInAccounts(requestedFolderID)
                    if targetFolder is missing value then error "Folder not found" number 10001

                    set resultRows to {}
                    repeat with noteItem in notes of targetFolder
                        set noteItem to contents of noteItem
                        set end of resultRows to {id of noteItem as text, id of targetFolder as text, name of noteItem as text, creation date of noteItem, modification date of noteItem, password protected of noteItem, shared of noteItem, count of attachments of noteItem}
                    end repeat
                    return resultRows
                end tell
                """
        )

        return try rows(in: descriptor)
            .map { row in
                AppleNoteSummarySnapshot(
                    id: try requiredString(in: row, at: 1, field: "note id"),
                    folderID: try requiredString(in: row, at: 2, field: "note folder id"),
                    title: try requiredString(in: row, at: 3, field: "note title"),
                    creationDate: optionalDate(in: row, at: 4),
                    modificationDate: optionalDate(in: row, at: 5),
                    isPasswordProtected: try requiredBoolean(
                        in: row,
                        at: 6,
                        field: "note password state"
                    ),
                    isShared: try requiredBoolean(in: row, at: 7, field: "note shared state"),
                    attachmentCount: try requiredInteger(
                        in: row,
                        at: 8,
                        field: "note attachment count"
                    )
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func note(withID noteID: String, inFolderID folderID: String) throws -> AppleNoteSnapshot {
        let descriptor = try execute(
            Self.noteSelectionHandlers
                + "\n"
                + """
                set requestedFolderID to "\(appleScriptLiteral(folderID))"
                set requestedNoteID to "\(appleScriptLiteral(noteID))"
                tell application "Notes"
                    set targetFolder to my findFolderInAccounts(requestedFolderID)
                    if targetFolder is missing value then error "Folder not found" number 10001

                    repeat with noteItem in notes of targetFolder
                        set noteItem to contents of noteItem
                        if (id of noteItem as text) is requestedNoteID then
                            return {id of noteItem as text, id of targetFolder as text, name of noteItem as text, plaintext of noteItem as text, creation date of noteItem, modification date of noteItem, password protected of noteItem, shared of noteItem}
                        end if
                    end repeat
                    error "Note not found" number 10002
                end tell
                """
        )

        return AppleNoteSnapshot(
            id: try requiredString(in: descriptor, at: 1, field: "note id"),
            folderID: try requiredString(in: descriptor, at: 2, field: "note folder id"),
            title: try requiredString(in: descriptor, at: 3, field: "note title"),
            bodyHTML: "",
            plaintext: try requiredString(in: descriptor, at: 4, field: "note plaintext"),
            creationDate: optionalDate(in: descriptor, at: 5),
            modificationDate: optionalDate(in: descriptor, at: 6),
            isPasswordProtected: try requiredBoolean(
                in: descriptor,
                at: 7,
                field: "note password state"
            ),
            isShared: try requiredBoolean(in: descriptor, at: 8, field: "note shared state"),
            attachments: []
        )
    }

    /// Creates a note in the folder and returns its identifier. The body is
    /// Notes-flavored HTML; Notes derives the note title from the first line.
    func createNote(inFolderID folderID: String, bodyHTML: String) throws -> String {
        let descriptor = try execute(
            Self.noteSelectionHandlers
                + "\n"
                + """
                set requestedFolderID to "\(appleScriptLiteral(folderID))"
                set requestedBody to "\(appleScriptLiteral(bodyHTML))"
                tell application "Notes"
                    set targetFolder to my findFolderInAccounts(requestedFolderID)
                    if targetFolder is missing value then error "Folder not found" number 10001
                    set newNote to make new note at targetFolder with properties {body:requestedBody}
                    return {id of newNote as text}
                end tell
                """
        )
        return try requiredString(in: descriptor, at: 1, field: "created note id")
    }

    func updateNote(
        withID noteID: String,
        inFolderID folderID: String,
        bodyHTML: String
    ) throws {
        _ = try execute(
            Self.noteSelectionHandlers
                + "\n"
                + """
                set requestedFolderID to "\(appleScriptLiteral(folderID))"
                set requestedNoteID to "\(appleScriptLiteral(noteID))"
                set requestedBody to "\(appleScriptLiteral(bodyHTML))"
                tell application "Notes"
                    set targetFolder to my findFolderInAccounts(requestedFolderID)
                    if targetFolder is missing value then error "Folder not found" number 10001
                    repeat with noteItem in notes of targetFolder
                        set noteItem to contents of noteItem
                        if (id of noteItem as text) is requestedNoteID then
                            set body of noteItem to requestedBody
                            return {id of noteItem as text}
                        end if
                    end repeat
                    error "Note not found" number 10002
                end tell
                """
        )
    }

    /// Moves a note to the Recently Deleted folder. Notes keeps trashed notes
    /// recoverable for 30 days, so this never destroys content outright.
    func trashNote(withID noteID: String, inFolderID folderID: String) throws {
        _ = try execute(
            Self.noteSelectionHandlers
                + "\n"
                + """
                set requestedFolderID to "\(appleScriptLiteral(folderID))"
                set requestedNoteID to "\(appleScriptLiteral(noteID))"
                tell application "Notes"
                    set targetFolder to my findFolderInAccounts(requestedFolderID)
                    if targetFolder is missing value then error "Folder not found" number 10001
                    repeat with noteItem in notes of targetFolder
                        set noteItem to contents of noteItem
                        if (id of noteItem as text) is requestedNoteID then
                            delete noteItem
                            return {"trashed"}
                        end if
                    end repeat
                    error "Note not found" number 10002
                end tell
                """
        )
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw AppleNotesStoreError.scriptCreationFailed
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            if number == 10001 {
                throw AppleNotesStoreError.folderNotFound("selected")
            }
            if number == 10002 {
                throw AppleNotesStoreError.noteNotFound("selected")
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? errorInfo[NSAppleScript.errorBriefMessage] as? String
                ?? "Unknown AppleScript error"
            throw AppleNotesStoreError.automationFailed(message)
        }
        return result
    }

    private func rows(in descriptor: NSAppleEventDescriptor) throws -> [NSAppleEventDescriptor] {
        guard descriptor.numberOfItems > 0 else {
            return []
        }
        return (1 ... descriptor.numberOfItems).compactMap { descriptor.atIndex($0) }
    }

    private func requiredString(
        in row: NSAppleEventDescriptor,
        at index: Int,
        field: String
    ) throws -> String {
        guard let value = row.atIndex(index)?.stringValue else {
            throw AppleNotesStoreError.malformedResponse("Missing \(field).")
        }
        return value
    }

    private func requiredBoolean(
        in row: NSAppleEventDescriptor,
        at index: Int,
        field: String
    ) throws -> Bool {
        guard let value = row.atIndex(index) else {
            throw AppleNotesStoreError.malformedResponse("Missing \(field).")
        }
        return value.booleanValue
    }

    private func requiredInteger(
        in row: NSAppleEventDescriptor,
        at index: Int,
        field: String
    ) throws -> Int {
        guard let value = row.atIndex(index) else {
            throw AppleNotesStoreError.malformedResponse("Missing \(field).")
        }
        return Int(value.int32Value)
    }

    private func optionalDate(in row: NSAppleEventDescriptor, at index: Int) -> Date? {
        row.atIndex(index)?.dateValue
    }

    private func appleScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    static let noteSelectionHandlers = """
    on findFolder(folderItems, requestedFolderID)
        tell application "Notes"
            repeat with folderItem in folderItems
                set folderItem to contents of folderItem
                if (id of folderItem as text) is requestedFolderID then return folderItem
                set nestedResult to my findFolder(folders of folderItem, requestedFolderID)
                if nestedResult is not missing value then return nestedResult
            end repeat
        end tell
        return missing value
    end findFolder

    on findFolderInAccounts(requestedFolderID)
        tell application "Notes"
            repeat with accountItem in accounts
                set accountItem to contents of accountItem
                set folderResult to my findFolder(folders of accountItem, requestedFolderID)
                if folderResult is not missing value then return folderResult
            end repeat
        end tell
        return missing value
    end findFolderInAccounts
    """

    static let folderEnumerationScript = """
    on collectFolders(folderItems, accountIdentifier, parentIdentifier, resultRows)
        tell application "Notes"
            repeat with folderItem in folderItems
                set folderItem to contents of folderItem
                set folderIdentifier to id of folderItem as text
                set end of resultRows to {folderIdentifier, name of folderItem as text, accountIdentifier, parentIdentifier, shared of folderItem}
                set resultRows to my collectFolders(folders of folderItem, accountIdentifier, folderIdentifier, resultRows)
            end repeat
        end tell
        return resultRows
    end collectFolders

    tell application "Notes"
        set resultRows to {}
        repeat with accountItem in accounts
            set accountItem to contents of accountItem
            set accountIdentifier to id of accountItem as text
            set resultRows to my collectFolders(folders of accountItem, accountIdentifier, "", resultRows)
        end repeat
        return resultRows
    end tell
    """
}
