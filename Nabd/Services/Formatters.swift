import Foundation

enum Num {
    private static let grouped: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let oneDecimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    /// 936,173,282
    static func full(_ value: Int64) -> String {
        grouped.string(from: NSNumber(value: value)) ?? "0"
    }

    /// 936.2 مليون
    static func compact(_ value: Int64) -> String {
        let absValue = abs(Double(value))
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...:
            return sign + trimmed(absValue / 1_000_000_000) + " مليار"
        case 1_000_000...:
            return sign + trimmed(absValue / 1_000_000) + " مليون"
        case 10_000...:
            return sign + trimmed(absValue / 1_000) + " ألف"
        default:
            return grouped.string(from: NSNumber(value: value)) ?? "0"
        }
    }

    /// نسخة مختصرة جداً للأماكن الضيقة: 12.4K, 93M
    static func tight(_ value: Int64) -> String {
        let absValue = abs(Double(value))
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...: return sign + trimmed(absValue / 1_000_000_000) + "B"
        case 1_000_000...: return sign + trimmed(absValue / 1_000_000) + "M"
        case 1_000...: return sign + trimmed(absValue / 1_000) + "K"
        default: return "\(value)"
        }
    }

    private static func trimmed(_ value: Double) -> String {
        let text = oneDecimal.string(from: NSNumber(value: value)) ?? "0"
        return text
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func minutes(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

enum Dates {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return isoWithFraction.date(from: value) ?? iso.date(from: value)
    }

    static func relative(_ value: String?) -> String {
        guard let date = parse(value) else { return "لم تُزامن بعد" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func short(_ value: String?) -> String {
        guard let date = parse(value) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "d MMM، HH:mm"
        return formatter.string(from: date)
    }

    static func videoDate(_ unixSeconds: Int) -> String {
        guard unixSeconds > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    static func todayArabic() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "EEEE، d MMMM"
        return formatter.string(from: Date())
    }
}
