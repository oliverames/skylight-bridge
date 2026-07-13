@preconcurrency import Foundation

enum AppleNotesStoreError: Error, LocalizedError, Sendable {
    case scriptCreationFailed
    case automationFailed(String)
    case malformedResponse(String)
    case folderNotFound(String)
    case noteNotFound(String)

    var errorDescription: String? {
        switch self {
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

actor AppleNotesStore {
    func accounts() throws -> [AppleNotesAccountSnapshot] {
        let descriptor = try execute(
            """
            tell application "Notes"
                set resultRows to {}
                repeat with accountItem in accounts
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
                        if (id of noteItem as text) is requestedNoteID then
                            set attachmentRows to {}
                            repeat with attachmentItem in attachments of noteItem
                                set attachmentURL to ""
                                try
                                    set attachmentURL to URL of attachmentItem as text
                                end try
                                set attachmentContentID to ""
                                try
                                    set attachmentContentID to content identifier of attachmentItem as text
                                end try
                                set end of attachmentRows to {id of attachmentItem as text, name of attachmentItem as text, attachmentContentID, attachmentURL, creation date of attachmentItem, modification date of attachmentItem, shared of attachmentItem}
                            end repeat
                            return {id of noteItem as text, id of targetFolder as text, name of noteItem as text, body of noteItem as text, plaintext of noteItem as text, creation date of noteItem, modification date of noteItem, password protected of noteItem, shared of noteItem, attachmentRows}
                        end if
                    end repeat
                    error "Note not found" number 10002
                end tell
                """
        )

        let attachmentsDescriptor = try requiredDescriptor(
            in: descriptor,
            at: 10,
            field: "note attachments"
        )
        let attachments = try rows(in: attachmentsDescriptor).map { row in
            let urlString = try requiredString(in: row, at: 4, field: "attachment URL")
            return AppleNoteAttachmentSnapshot(
                id: try requiredString(in: row, at: 1, field: "attachment id"),
                name: try requiredString(in: row, at: 2, field: "attachment name"),
                contentIdentifier: try requiredString(
                    in: row,
                    at: 3,
                    field: "attachment content id"
                ),
                url: urlString.isEmpty ? nil : URL(string: urlString),
                creationDate: optionalDate(in: row, at: 5),
                modificationDate: optionalDate(in: row, at: 6),
                isShared: try requiredBoolean(in: row, at: 7, field: "attachment shared state")
            )
        }

        return AppleNoteSnapshot(
            id: try requiredString(in: descriptor, at: 1, field: "note id"),
            folderID: try requiredString(in: descriptor, at: 2, field: "note folder id"),
            title: try requiredString(in: descriptor, at: 3, field: "note title"),
            bodyHTML: try requiredString(in: descriptor, at: 4, field: "note body"),
            plaintext: try requiredString(in: descriptor, at: 5, field: "note plaintext"),
            creationDate: optionalDate(in: descriptor, at: 6),
            modificationDate: optionalDate(in: descriptor, at: 7),
            isPasswordProtected: try requiredBoolean(
                in: descriptor,
                at: 8,
                field: "note password state"
            ),
            isShared: try requiredBoolean(in: descriptor, at: 9, field: "note shared state"),
            attachments: attachments
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

    private func requiredDescriptor(
        in row: NSAppleEventDescriptor,
        at index: Int,
        field: String
    ) throws -> NSAppleEventDescriptor {
        guard let value = row.atIndex(index) else {
            throw AppleNotesStoreError.malformedResponse("Missing \(field).")
        }
        return value
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

    private static let noteSelectionHandlers = """
    on findFolder(folderItems, requestedFolderID)
        tell application "Notes"
            repeat with folderItem in folderItems
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
                set folderResult to my findFolder(folders of accountItem, requestedFolderID)
                if folderResult is not missing value then return folderResult
            end repeat
        end tell
        return missing value
    end findFolderInAccounts
    """

    private static let folderEnumerationScript = """
    on collectFolders(folderItems, accountIdentifier, parentIdentifier, resultRows)
        tell application "Notes"
            repeat with folderItem in folderItems
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
            set accountIdentifier to id of accountItem as text
            set resultRows to my collectFolders(folders of accountItem, accountIdentifier, "", resultRows)
        end repeat
        return resultRows
    end tell
    """
}
