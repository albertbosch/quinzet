import Foundation

/// Idioma de la interfície: català o anglès, segons l'idioma del sistema (o de l'app, a
/// Configuració del Sistema › General › Idioma i regió › Aplicacions).
/// Les claus de traducció són els textos en català; l'anglès és a Resources/en.lproj.
enum Lang {
    static let isEnglish: Bool = {
        let code = Bundle.main.preferredLocalizations.first ?? "ca"
        return code.hasPrefix("en")
    }()
}

/// Text localitzat per a valors de tipus `String` (els literals de SwiftUI ja es tradueixen sols).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
