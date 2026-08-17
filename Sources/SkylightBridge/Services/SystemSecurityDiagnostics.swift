import Foundation

/// Detects boot configurations under which macOS cannot present privacy
/// consent prompts. Tahoe refuses every Developer ID consent request while
/// Apple Mobile File Integrity is disabled, without showing a dialog or
/// recording a decision, so permission requests appear to do nothing.
enum SystemSecurityDiagnostics {
    /// Boot-argument names that disable AMFI or code-signing enforcement.
    private static let amfiDisablingArgumentNames: Set<String> = [
        "amfi",
        "amfi_get_out_of_my_way",
        "amfi_allow_any_signature",
        "amfi_unrestrict_task_for_pid",
        "cs_enforcement_disable"
    ]

    /// The boot-argument tokens in `bootArguments` that disable AMFI,
    /// preserving their original order and `name=value` spelling.
    static func amfiDisablingBootArguments(in bootArguments: String) -> [String] {
        bootArguments
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                let name = token.split(separator: "=", maxSplits: 1)[0]
                return amfiDisablingArgumentNames.contains(String(name))
            }
    }

    /// The live kernel boot arguments, empty when none are set.
    static func currentBootArguments() -> String {
        var size = 0
        guard sysctlbyname("kern.bootargs", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootargs", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: buffer)
    }

    /// A user-facing explanation when consent prompts cannot appear, or nil
    /// when the boot configuration allows them.
    static func blockedConsentPromptExplanation(
        bootArguments: String? = nil
    ) -> String? {
        let offenders = amfiDisablingBootArguments(
            in: bootArguments ?? currentBootArguments()
        )
        guard !offenders.isEmpty else { return nil }
        let list = offenders.joined(separator: ", ")
        return "macOS did not show a permission prompt. A boot argument on this "
            + "Mac disables Apple Mobile File Integrity (\(list)), and macOS "
            + "suppresses privacy consent dialogs for non-Apple apps while it is "
            + "disabled. Remove that boot argument and restart the Mac to restore "
            + "prompts, or grant Skylight Bridge access another way."
    }

    /// A self-contained shell script the user can run in Terminal to grant the
    /// Apple privacy permissions macOS refused to prompt for. The app never
    /// writes the privacy database itself: doing so is a TCC bypass that only
    /// works where SIP is disabled and that Apple treats as malware, so the
    /// decision and the action stay with the user in their own shell. Paths and
    /// identifiers are resolved at runtime so the script matches this install.
    static func permissionGrantScript(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
        bundlePath: String = Bundle.main.bundleURL.path
    ) -> String {
        """
        #!/bin/bash
        # Grant Skylight Bridge its Apple privacy permissions on a Mac where a
        # boot argument disables Apple Mobile File Integrity and macOS therefore
        # suppresses consent dialogs. This edits your own privacy database, so it
        # only works while System Integrity Protection is disabled. Review before
        # running.
        set -e
        APP="\(bundlePath)"
        DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

        requirement() { codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'; }
        blob() { printf '%s' "$1" | csreq -r- -b "$2" && xxd -p "$2" | tr -d '\\n'; }

        CHEX=$(blob "$(requirement "$APP")" /tmp/sb_client.csreq)
        NHEX=$(blob "$(requirement /System/Applications/Notes.app)" /tmp/sb_notes.csreq)

        for SVC in kTCCServiceReminders kTCCServicePhotos; do
          sqlite3 "$DB" "INSERT OR REPLACE INTO access \\
        (service,client,client_type,auth_value,auth_reason,auth_version,csreq,flags,last_modified) \\
        VALUES('$SVC','\(bundleIdentifier)',0,2,2,1,X'$CHEX',0,strftime('%s','now'));"
        done

        sqlite3 "$DB" "INSERT OR REPLACE INTO access \\
        (service,client,client_type,auth_value,auth_reason,auth_version,csreq,\\
        indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \\
        VALUES('kTCCServiceAppleEvents','\(bundleIdentifier)',0,2,2,1,X'$CHEX',\\
        0,'com.apple.Notes',X'$NHEX',0,strftime('%s','now'));"

        rm -f /tmp/sb_client.csreq /tmp/sb_notes.csreq
        killall tccd
        echo "Done. Reopen Skylight Bridge and click Refresh."
        """
    }

    /// Writes the grant script next to the app's own support files and returns
    /// its URL. The script used to go on the pasteboard whole, but an
    /// interactive zsh expands the `!` in its `#!/bin/bash` line as a history
    /// event and refuses the paste ("event not found: /bin/bash"), so the user
    /// saw the fix fail before it ran. A file the user runs by path has no
    /// such shell parsing, and it stays reviewable before it executes.
    static func writePermissionGrantScript(
        to directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = try directory ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("SkylightBridge", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let scriptURL = root.appendingPathComponent("grant-skylight-bridge-access.sh")
        try Data(permissionGrantScript().utf8).write(to: scriptURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    /// The single line to paste in Terminal to run the saved script. It carries
    /// no comment marker and no `!`, so every common shell takes it verbatim.
    static func permissionGrantCommand(forScriptAt scriptURL: URL) -> String {
        "bash '\(scriptURL.path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
