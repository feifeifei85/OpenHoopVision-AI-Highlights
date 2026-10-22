import Foundation

/// App UI language is independent of analysis settings and iOS language preferences.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    static let preferenceKey = "app.interfaceLanguage"
    var id: String { rawValue }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
    }

    private static let localizedBundles: [String: Bundle] = {
        var bundles: [String: Bundle] = [:]
        for language in allCases where language != .system {
            if let url = Bundle.main.url(forResource: language.rawValue, withExtension: "lproj"),
               let bundle = Bundle(url: url) {
                bundles[language.rawValue] = bundle
            }
        }
        return bundles
    }()

    var bundle: Bundle {
        self == .system ? .main : Self.localizedBundles[rawValue] ?? .main
    }

    var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }

    var title: String {
        switch self {
        case .system: return String(localized: "Follow System", bundle: Self.current.bundle)
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }
}
