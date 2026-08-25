import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case polish = "pl"
    case italian = "it"
    case spanish = "es"
    case bulgarian = "bg"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .polish: return "Polski"
        case .italian: return "Italiano"
        case .spanish: return "Español"
        case .bulgarian: return "Български"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

enum L10n {
    private static let resourceBundle: Bundle = {
        let bundleName = "OpenFlow_OpenFlow.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        return .module
    }()

    static func keys(language: AppLanguage) -> Set<String> {
        guard let path = resourceBundle.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path),
              let stringsPath = bundle.path(forResource: "Localizable", ofType: "strings"),
              let values = NSDictionary(contentsOfFile: stringsPath) as? [String: String]
        else { return [] }
        return Set(values.keys)
    }

    static func text(
        _ key: String,
        language: AppLanguage,
        _ arguments: CVarArg...
    ) -> String {
        text(key, language: language, arguments: arguments)
    }

    static func text(
        _ key: String,
        language: AppLanguage,
        arguments: [CVarArg]
    ) -> String {
        let path = resourceBundle.path(forResource: language.rawValue, ofType: "lproj")
        let localizedBundle = path.flatMap(Bundle.init(path:)) ?? resourceBundle
        let format = localizedBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }
}
