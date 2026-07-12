import Foundation
import Combine

/// The app's UI language. `system` follows macOS (Danish if the Mac is Danish, else English).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case danish
    var id: String { rawValue }

    @MainActor var displayName: String {
        switch self {
        case .system: return L("Følg macOS")
        case .english: return "English"
        case .danish: return "Dansk"
        }
    }
}

/// Runtime localization. Danish is the base (keys are the Danish source strings); English is a
/// translation table. The language is user-selectable in Settings and defaults to the macOS
/// language on first launch (English unless the Mac is Danish). Views switch live because the app
/// root is re-created when `effectiveCode` changes.
@MainActor
final class Localizer: ObservableObject {
    static let shared = Localizer()
    private static let defaultsKey = "app.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let stored = AppLanguage(rawValue: raw) {
            language = stored
        } else {
            language = .system   // first launch → follow macOS
        }
    }

    /// Resolved language code ("en" or "da"), following macOS when set to `.system`.
    var effectiveCode: String {
        switch language {
        case .english: return "en"
        case .danish: return "da"
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("da") ? "da" : "en"
        }
    }

    /// Danish keys are the source text; for English we look up a translation, else fall back.
    func localized(_ key: String) -> String {
        guard effectiveCode == "en" else { return key }
        return Translations.english[key] ?? key
    }
}

/// Localizes a Danish source string. Wrap every user-facing literal in this.
@MainActor
func L(_ key: String) -> String {
    Localizer.shared.localized(key)
}

/// Localizes a format key (e.g. "Kører på %d tegn") with arguments.
@MainActor
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.localized(key), arguments: args)
}
