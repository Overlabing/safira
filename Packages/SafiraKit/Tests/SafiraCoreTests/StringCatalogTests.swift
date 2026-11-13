// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Testing

/// One String Catalog of the repository, read from its source file: keys are English, French is a translation.
struct Catalog: CustomTestStringConvertible, Sendable {
    let path: String
    let sourceLanguage: String
    let entries: [String: Entry]

    struct Entry: Sendable {
        let shouldTranslate: Bool
        /// Each French text with the English form it translates: one, or one per plural category ("" for a plain string).
        let french: [Form]
    }

    struct Form: Sendable {
        let category: String
        let english: String
        let french: String
    }

    var testDescription: String { path }

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Every catalog Safira ships: the app's and each package module's.
    static let all: [Catalog] = {
        let folders = ["App", "Packages/SafiraKit/Sources"].map { root.appending(path: $0) }
        let files = folders.flatMap { folder in
            (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                .filter { $0.pathExtension == "xcstrings" }
        }
        return files.map(load).sorted { $0.path < $1.path }
    }()

    static func load(_ url: URL) -> Catalog {
        let path = String(url.path.dropFirst(root.path.count + 1))
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: [String: Any]] else {
            return Catalog(path: path, sourceLanguage: "unreadable", entries: [:])
        }
        let entries = strings.mapValues { entry in
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let english = texts(localizations["en"])
            let french = texts(localizations["fr"])
            let forms = french.map { category, text in Form(category: category, english: english[category] ?? "", french: text) }
            return Entry(shouldTranslate: entry["shouldTranslate"] as? Bool ?? true, french: forms)
        }
        return Catalog(path: path, sourceLanguage: json["sourceLanguage"] as? String ?? "", entries: entries)
    }

    /// The texts of one localization by plural category; "" for a plain string.
    private static func texts(_ localization: Any?) -> [String: String] {
        guard let localization = localization as? [String: Any] else { return [:] }
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return ["": value]
        }
        let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        return plural.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
    }
}

/// Words of French UI copy that English UI copy never uses, so a key holding one was written in French.
private let frenchWords: Set<String> = [
    "le", "la", "les", "des", "du", "une", "et", "ou", "pour", "avec", "dans", "sur", "sans", "vous", "votre", "vos",
    "est", "pas", "aucun", "aucune", "onglet", "onglets", "fenêtre", "espace", "espaces", "profil", "profils",
    "dossier", "réglages", "annuler", "ouvrir", "fermer", "supprimer", "enregistrer", "créer", "nouveau", "nouvel",
    "nouvelle", "rechercher", "afficher", "masquer", "choisir", "continuer", "terminer", "lien", "liens", "règle",
    "règles", "oui", "toujours", "jamais", "rien", "téléchargements", "barre", "privée", "défaut",
]

private func words(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter }.map(String.init)
}

/// `%@`, `%lld`, `%1$@`: the arguments a text takes, in kind, whatever their order.
private func specifiers(_ text: String) -> [String] {
    text.matches(of: /%(?:\d+\$)?(@|lld|ld|d|f|%)/).map { String($0.output.1) }.sorted()
}

@Test func everyModuleThatShowsTextHasItsCatalog() {
    let paths = Set(Catalog.all.map(\.path))
    for module in ["SafiraCore", "SafiraSession", "SafiraWeb", "Commands", "LinkRouting", "LinkPickerUI", "Diagnostics",
                   "Onboarding"] {
        #expect(paths.contains("Packages/SafiraKit/Sources/\(module)/Resources/\(module).xcstrings"), "\(module)")
    }
    #expect(paths.contains("App/macOS/Localizable.xcstrings"))
    #expect(paths.contains("App/macOS/InfoPlist.xcstrings"))
}

@Test(arguments: Catalog.all)
func everyKeyHasAFrenchTranslation(_ catalog: Catalog) {
    #expect(catalog.sourceLanguage == "en")
    #expect(!catalog.entries.isEmpty)
    for (key, entry) in catalog.entries where entry.shouldTranslate {
        #expect(!entry.french.isEmpty, "no French for « \(key) »")
        for form in entry.french {
            #expect(!form.french.trimmingCharacters(in: .whitespaces).isEmpty, "empty French for « \(key) »")
        }
    }
}

@Test(arguments: Catalog.all)
func frenchTakesTheSameArgumentsAsEnglish(_ catalog: Catalog) {
    for (key, entry) in catalog.entries {
        for form in entry.french {
            let english = specifiers(form.english.isEmpty ? key : form.english)
            let french = specifiers(form.french)
            if form.category == "one" {
                // A singular form may leave its count out: « Son onglet sera fermé. »
                #expect(Set(french).isSubset(of: english), "« \(key) », one")
            } else {
                #expect(french == english, "« \(key) » \(form.category)")
            }
        }
    }
}

@Test(arguments: Catalog.all)
func noKeyIsInFrench(_ catalog: Catalog) {
    for key in catalog.entries.keys {
        #expect(key.firstMatch(of: /[àâçéèêëîïôûùüÿœæÀÂÇÉÈÊËÎÏÔÛÙÜŸŒÆ]/) == nil, "accented letter in the key « \(key) »")
        let french = words(key).filter(frenchWords.contains)
        #expect(french.isEmpty, "French word \(french) in the key « \(key) »")
    }
}

@Test func theWordListCatchesAFrenchKey() {
    #expect(words("Fermer l’onglet").contains(where: frenchWords.contains))
    #expect(!words("Close the Tab of this Profile, then open a new Space").contains(where: frenchWords.contains))
}

/// The preset notes are data, so their translations are manual entries: a note edited in its file must be translated
/// again.
@Test func everyPresetNoteIsInTheCommandsCatalog() throws {
    let commands = try #require(Catalog.all.first { $0.path.hasSuffix("Commands.xcstrings") })
    let presets = Catalog.root.appending(path: "Packages/SafiraKit/Sources/Commands/Presets")
    for file in try FileManager.default.contentsOfDirectory(at: presets, includingPropertiesForKeys: nil) {
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        if let note = json["note"] as? String {
            #expect(commands.entries[note] != nil, "\(file.lastPathComponent): note missing from Commands.xcstrings")
        }
    }
}

/// The pin labels name the state, in the menu and the Tab's context menu, and the combined label is gone.
@Test func thePinLabelsNameTheStateInFrench() throws {
    let commands = try #require(Catalog.all.first { $0.path.hasSuffix("Commands.xcstrings") })
    let app = try #require(Catalog.all.first { $0.path == "App/macOS/Localizable.xcstrings" })

    #expect(commands.entries["Pin Tab"]?.french.map(\.french) == ["Épingler l’onglet"])
    #expect(app.entries["Pin Tab"]?.french.map(\.french) == ["Épingler l’onglet"])
    #expect(app.entries["Unpin Tab"]?.french.map(\.french) == ["Désépingler l’onglet"])
    for catalog in Catalog.all {
        #expect(!catalog.entries.keys.contains { $0.contains("Pin or Unpin") }, "\(catalog.path)")
        #expect(!catalog.entries.values.contains { $0.french.contains { $0.french.contains("ou désépingler") } },
                "\(catalog.path)")
    }
}
