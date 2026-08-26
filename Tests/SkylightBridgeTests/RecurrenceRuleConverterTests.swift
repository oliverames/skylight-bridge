import EventKit
import Foundation
import Testing
@testable import SkylightBridge

struct RecurrenceRuleConverterTests {
    @Test("RRULE parsing is case insensitive and accepts the prefix")
    func parsesPrefixedRule() throws {
        let rule = try RecurrenceRuleConverter.parse("rrule:freq=weekly;interval=2;byday=mo,we,fr")
        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 2)
        #expect(rule.byDays == [.monday, .wednesday, .friday])
        #expect(RecurrenceRuleConverter.format(rule) == "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR")
    }

    @Test("Daily rules default to an interval of one")
    func defaultsInterval() throws {
        let rule = try RecurrenceRuleConverter.parse("FREQ=DAILY")
        #expect(rule.interval == 1)
        #expect(RecurrenceRuleConverter.format(rule) == "FREQ=DAILY;INTERVAL=1")
    }

    @Test("Monthly day lists round trip")
    func roundTripsMonthDays() throws {
        let parsed = try RecurrenceRuleConverter.parse("FREQ=MONTHLY;BYMONTHDAY=1,15,-1")
        let formatted = RecurrenceRuleConverter.format(parsed)
        #expect(try RecurrenceRuleConverter.parse(formatted) == parsed)
    }

    @Test("UTC and date-only UNTIL values parse")
    func parsesUntilForms() throws {
        let dateOnly = try RecurrenceRuleConverter.parse("FREQ=DAILY;UNTIL=20260731")
        let timestamp = try RecurrenceRuleConverter.parse("FREQ=DAILY;UNTIL=20260731T235959Z")
        #expect(dateOnly.until != nil)
        #expect(timestamp.until != nil)
    }

    @Test("Occurrence counts round trip through EventKit")
    func eventKitCountRoundTrip() throws {
        let parsed = try RecurrenceRuleConverter.parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=TU;COUNT=8")
        let eventKit = RecurrenceRuleConverter.ekRecurrenceRule(from: parsed)
        #expect(try RecurrenceRuleConverter.parsedRule(from: eventKit) == parsed)
    }

    @Test("A date-only UNTIL covers its whole final day in local time")
    func dateOnlyUntilCoversFinalDay() throws {
        let rule = try RecurrenceRuleConverter.parse("FREQ=DAILY;UNTIL=20260731")
        let until = try #require(rule.until)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: until
        )
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 31)
        #expect(components.hour == 23)
        #expect(components.minute == 59)
    }

    @Test("COUNT together with UNTIL is rejected instead of dropping COUNT")
    func rejectsCountWithUntil() {
        #expect(throws: RecurrenceRuleConverter.ConversionError.self) {
            try RecurrenceRuleConverter.parse("FREQ=WEEKLY;COUNT=8;UNTIL=20260731T235959Z")
        }
    }

    @Test("Skylight chore time slots parse and format without loss")
    func roundTripsByHour() throws {
        let parsed = try RecurrenceRuleConverter.parse(
            "RRULE:FREQ=DAILY;INTERVAL=1;BYHOUR=14"
        )
        #expect(parsed.byHours == [14])
        #expect(RecurrenceRuleConverter.format(parsed)
            == "FREQ=DAILY;INTERVAL=1;BYHOUR=14")
    }

    @Test("Unknown components throw instead of narrowing the schedule")
    func rejectsUnknownComponents() {
        #expect(throws: RecurrenceRuleConverter.ConversionError.self) {
            try RecurrenceRuleConverter.parse("FREQ=MONTHLY;BYSETPOS=1")
        }
    }

    @Test("Ordinal weekdays are rejected")
    func rejectsOrdinalWeekdays() {
        #expect(throws: RecurrenceRuleConverter.ConversionError.self) {
            try RecurrenceRuleConverter.parse("FREQ=MONTHLY;BYDAY=2TU")
        }
    }
}
