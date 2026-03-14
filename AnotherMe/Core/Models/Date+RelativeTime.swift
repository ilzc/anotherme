import Foundation

extension Date {
    /// Converts a date to a human-readable relative time string.
    /// e.g. "Just now", "3 min ago", "2 hr ago", "4 days ago"
    var relativeTimeString: String {
        let interval = Date.now.timeIntervalSince(self)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        if hours < 24 { return "\(hours) hr ago" }
        if days < 7 { return "\(days) day\(days == 1 ? "" : "s") ago" }
        let weeks = days / 7
        if days < 30 { return "\(weeks) week\(weeks == 1 ? "" : "s") ago" }
        let months = days / 30
        if days < 365 { return "\(months) month\(months == 1 ? "" : "s") ago" }
        let years = days / 365
        return "\(years) year\(years == 1 ? "" : "s") ago"
    }
}
