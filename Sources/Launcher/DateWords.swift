import Foundation

/// How the panel says when something happened, in English like the rest of the copy: the tile's "opened today at
/// 14:05" and "copied yesterday", and a clip's age at the end of its row.
enum DateWords {
    /// "today at 14:05", "yesterday", "Tuesday" within the week, else "Nov 3", or "Nov 3, 2025" in another year.
    static func day(of date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time.string(from: date))" }
        let days = days(from: date, to: now, in: calendar)
        if days == 1 { return "yesterday" }
        if (2..<7).contains(days) { return weekday.string(from: date) }
        return Self.date(date, now: now, in: calendar)
    }

    /// "Nov 3", or "Nov 3, 2025" when it isn't this year: a clip kept a year would read as this year's.
    static func date(_ date: Date, now: Date, in calendar: Calendar) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? monthDay.string(from: date) : monthDayYear.string(from: date)
    }

    /// Calendar days from `date` to `now`: 0 the same day, 1 the day before.
    static func days(from date: Date, to now: Date, in calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
            ?? .max
    }

    /// The time as the user's settings write it: "14:05" or "2:05 PM".
    static let time: DateFormatter = {
        let format = DateFormatter()
        format.timeStyle = .short
        format.dateStyle = .none
        return format
    }()
    static let weekday = english("EEEE")
    static let shortWeekday = english("EEE")
    static let monthDay = english("MMMd")
    static let monthDayYear = english("yMMMd")

    private static func english(_ template: String) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en")
        format.setLocalizedDateFormatFromTemplate(template)
        return format
    }
}
