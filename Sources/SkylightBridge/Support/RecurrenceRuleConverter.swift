import EventKit
import Foundation

/// A recurrence rule in the shape both sides of the chores sync can agree on.
/// Skylight stores RRULE strings in `recurrence_set`; EventKit wants
/// `EKRecurrenceRule`. This is the lossless middle: anything that parses into
/// it round-trips back out in a stable canonical form via `format`.
struct ParsedRecurrenceRule: Equatable, Sendable {
    enum Frequency: String, Sendable, CaseIterable {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    enum Weekday: String, Sendable, CaseIterable {
        case monday = "MO"
        case tuesday = "TU"
        case wednesday = "WE"
        case thursday = "TH"
        case friday = "FR"
        case saturday = "SA"
        case sunday = "SU"
    }

    var frequency: Frequency
    var interval: Int = 1
    var byDays: [Weekday] = []
    var byMonthDays: [Int] = []
    var byHours: [Int] = []
    var until: Date?
    var count: Int?
}

/// Converts between RRULE strings and `EKRecurrenceRule`. Parsing is strict:
/// any component this type does not understand throws instead of being
/// dropped, because a silently narrowed rule would be written back to the
/// other side and destroy the original schedule.
enum RecurrenceRuleConverter {
    enum ConversionError: Error, Equatable {
        case malformed(String)
        case unsupportedFrequency(String)
        case unsupportedComponent(String)
    }

    // MARK: - RRULE string <-> ParsedRecurrenceRule

    static func parse(_ rrule: String) throws -> ParsedRecurrenceRule {
        var body = rrule.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.uppercased().hasPrefix("RRULE:") {
            body = String(body.dropFirst("RRULE:".count))
        }
        guard !body.isEmpty else { throw ConversionError.malformed(rrule) }

        var frequency: ParsedRecurrenceRule.Frequency?
        var interval = 1
        var byDays: [ParsedRecurrenceRule.Weekday] = []
        var byMonthDays: [Int] = []
        var byHours: [Int] = []
        var until: Date?
        var count: Int?

        for pair in body.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { throw ConversionError.malformed(String(pair)) }
            let key = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces).uppercased()

            switch key {
            case "FREQ":
                guard let parsed = ParsedRecurrenceRule.Frequency(rawValue: value) else {
                    throw ConversionError.unsupportedFrequency(value)
                }
                frequency = parsed
            case "INTERVAL":
                guard let parsed = Int(value), parsed >= 1 else {
                    throw ConversionError.malformed(String(pair))
                }
                interval = parsed
            case "BYDAY":
                for token in value.split(separator: ",") {
                    guard let day = ParsedRecurrenceRule.Weekday(rawValue: String(token)) else {
                        // Ordinal prefixes like "2TU" or "-1FR" land here; they
                        // are representable in EventKit but out of scope for v1.
                        throw ConversionError.unsupportedComponent("BYDAY=\(token)")
                    }
                    byDays.append(day)
                }
            case "BYMONTHDAY":
                for token in value.split(separator: ",") {
                    guard let day = Int(token), (1...31).contains(abs(day)), day != 0 else {
                        throw ConversionError.malformed(String(pair))
                    }
                    byMonthDays.append(day)
                }
            case "BYHOUR":
                for token in value.split(separator: ",") {
                    guard let hour = Int(token), (0...23).contains(hour) else {
                        throw ConversionError.malformed(String(pair))
                    }
                    byHours.append(hour)
                }
            case "UNTIL":
                guard let parsed = parseUntilDate(value) else {
                    throw ConversionError.malformed(String(pair))
                }
                until = parsed
            case "COUNT":
                guard let parsed = Int(value), parsed >= 1 else {
                    throw ConversionError.malformed(String(pair))
                }
                count = parsed
            default:
                throw ConversionError.unsupportedComponent(key)
            }
        }

        guard let frequency else { throw ConversionError.malformed(rrule) }
        return ParsedRecurrenceRule(
            frequency: frequency,
            interval: interval,
            byDays: byDays,
            byMonthDays: byMonthDays,
            byHours: byHours,
            until: until,
            count: count
        )
    }

    /// Canonical form: fixed component order, no "RRULE:" prefix, INTERVAL
    /// always present. Used for fingerprints, so it must be deterministic.
    static func format(_ rule: ParsedRecurrenceRule) -> String {
        var components = [
            "FREQ=\(rule.frequency.rawValue)",
            "INTERVAL=\(rule.interval)"
        ]
        if !rule.byDays.isEmpty {
            components.append("BYDAY=\(rule.byDays.map(\.rawValue).joined(separator: ","))")
        }
        if !rule.byMonthDays.isEmpty {
            components.append("BYMONTHDAY=\(rule.byMonthDays.map(String.init).joined(separator: ","))")
        }
        if !rule.byHours.isEmpty {
            components.append("BYHOUR=\(rule.byHours.map(String.init).joined(separator: ","))")
        }
        if let until = rule.until {
            components.append("UNTIL=\(formatUntilDate(until))")
        }
        if let count = rule.count {
            components.append("COUNT=\(count)")
        }
        return components.joined(separator: ";")
    }

    // MARK: - ParsedRecurrenceRule <-> EKRecurrenceRule

    static func ekRecurrenceRule(from rule: ParsedRecurrenceRule) -> EKRecurrenceRule {
        let end: EKRecurrenceEnd? = if let until = rule.until {
            EKRecurrenceEnd(end: until)
        } else if let count = rule.count {
            EKRecurrenceEnd(occurrenceCount: count)
        } else {
            nil
        }
        return EKRecurrenceRule(
            recurrenceWith: ekFrequency(rule.frequency),
            interval: rule.interval,
            daysOfTheWeek: rule.byDays.isEmpty
                ? nil
                : rule.byDays.map { EKRecurrenceDayOfWeek(ekWeekday($0)) },
            daysOfTheMonth: rule.byMonthDays.isEmpty
                ? nil
                : rule.byMonthDays.map { NSNumber(value: $0) },
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    static func parsedRule(from ek: EKRecurrenceRule) throws -> ParsedRecurrenceRule {
        let frequency: ParsedRecurrenceRule.Frequency
        switch ek.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default:
            throw ConversionError.unsupportedFrequency("\(ek.frequency.rawValue)")
        }

        var byDays: [ParsedRecurrenceRule.Weekday] = []
        for dayOfWeek in ek.daysOfTheWeek ?? [] {
            guard dayOfWeek.weekNumber == 0 else {
                throw ConversionError.unsupportedComponent(
                    "ordinal weekday \(dayOfWeek.weekNumber)"
                )
            }
            byDays.append(parsedWeekday(dayOfWeek.dayOfTheWeek))
        }

        if ek.monthsOfTheYear?.isEmpty == false
            || ek.weeksOfTheYear?.isEmpty == false
            || ek.daysOfTheYear?.isEmpty == false
            || ek.setPositions?.isEmpty == false {
            throw ConversionError.unsupportedComponent("beyond FREQ/BYDAY/BYMONTHDAY")
        }

        return ParsedRecurrenceRule(
            frequency: frequency,
            interval: max(ek.interval, 1),
            byDays: byDays,
            byMonthDays: (ek.daysOfTheMonth ?? []).map(\.intValue),
            byHours: [],
            until: ek.recurrenceEnd?.endDate,
            count: ek.recurrenceEnd.flatMap {
                $0.occurrenceCount > 0 ? $0.occurrenceCount : nil
            }
        )
    }

    // MARK: - Helpers

    private static func ekFrequency(
        _ frequency: ParsedRecurrenceRule.Frequency
    ) -> EKRecurrenceFrequency {
        switch frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }

    private static func ekWeekday(_ weekday: ParsedRecurrenceRule.Weekday) -> EKWeekday {
        switch weekday {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }

    private static func parsedWeekday(_ weekday: EKWeekday) -> ParsedRecurrenceRule.Weekday {
        switch weekday {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }

    /// UNTIL appears both as a bare date ("20260731") and as a UTC timestamp
    /// ("20260731T235959Z") in the wild; accept both.
    private static func parseUntilDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = value.contains("T") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd"
        return formatter.date(from: value)
    }

    private static func formatUntilDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
