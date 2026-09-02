import Foundation

enum AppLocalization {
    static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(
            format: String(localized: key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
