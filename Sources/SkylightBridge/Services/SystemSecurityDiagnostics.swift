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
        return "macOS cannot show permission prompts on this Mac because a boot "
            + "argument disables Apple Mobile File Integrity (\(list)). "
            + "Remove it from the boot arguments (sudo nvram boot-args=…), "
            + "restart the Mac, then request access again."
    }
}
