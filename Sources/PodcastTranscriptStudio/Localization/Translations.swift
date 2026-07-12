import Foundation

/// Danish source string → English translation. Missing entries fall back to the Danish key, so
/// the app is fully usable in Danish even before a string is translated.
enum Translations {
    static let english: [String: String] = [
        // App menu / windows
        "Om Podcast Transcript Studio": "About Podcast Transcript Studio",
        "Følg macOS": "Follow macOS",

        // Settings — tabs
        "Generelt": "General",
        "LLM-providere": "LLM providers",
        "Prompts": "Prompts",
        "Data": "Data",
        "Sprog": "Language",
        "Vælg sprog for appen. \"Følg macOS\" bruger dit systemsprog (engelsk, hvis din Mac ikke er på dansk).":
            "Choose the app language. \"Follow macOS\" uses your system language (English unless your Mac is Danish).",

        // Settings — providers
        "Base-URL": "Base URL",
        "Standardmodel": "Default model",
        "API key (Keychain)": "API key (Keychain)",
        "gemmes i Keychain": "stored in Keychain",
        "Aktiv": "Enabled",
        "Gem": "Save",
        "Gemt": "Saved",
        "Test tilgængelighed": "Test availability",
        "Tester…": "Testing…",
        "✅ Tilgængelig": "✅ Available",
        "⚠️ Ikke tilgængelig": "⚠️ Unavailable",
        "base URL": "base URL",
        "model": "model",
        "model-id": "model id",
        "Vælg fra liste": "Choose from list",
        "Egen…": "Custom…",
        "Hent modeller fra provideren": "Fetch models from the provider",

        // Settings — prompts
        "Prompt-folder": "Prompt folder",
        "Åbn folder": "Open folder",
        "Genindlæs prompts": "Reload prompts",
        "%d prompts indlæst · %d med problemer": "%d prompts loaded · %d with problems",

        // Settings — data
        "Eksport & import": "Export & import",
        "API keys eksporteres ikke — de bliver i Keychain.": "API keys are not exported — they stay in the Keychain.",
        "Eksportér alle transcripts (Markdown)": "Export all transcripts (Markdown)",
        "Lav backup-pakke (database + prompts)": "Create backup package (database + prompts)",
        "Importér backup": "Import backup",
        "Database:": "Database:",

        // About
        "Version %@ · lokal-first macOS-app": "Version %@ · local-first macOS app",
        "Lavet med **Claude Code** af **Sten Hougaard** (netsi1964).":
            "Made with **Claude Code** by **Sten Hougaard** (netsi1964).",
        "Om Sten": "About Sten",
        "Softwareudvikler og AI-specialist med 20+ års erfaring, baseret i Aarhus. Arbejder med LLM-baserede assistenter, prompt engineering, MCP-servere og AI-integrerede løsninger — med fokus på bæredygtig, etisk og menneske-centreret AI.":
            "Software developer and AI specialist with 20+ years of experience, based in Aarhus. Works on LLM-based assistants, prompt engineering, MCP servers and AI-integrated solutions — with a focus on sustainable, ethical and human-centered AI.",
        "Buy me a coffee": "Buy me a coffee",
        "Støt udvikleren på Buy Me a Coffee": "Support the developer on Buy Me a Coffee",
        "GitHub-repo": "GitHub repo",

        // Library / navigation
        "Bibliotek": "Library",
        "Chat med arkivet": "Chat with the archive",
        "Importér episode": "Import episode",
        "Importér episode via link": "Import episode via link",
        "Søg i Apple Podcasts": "Search Apple Podcasts",
        "Sortér": "Sort",
        "Senest opdateret": "Recently updated",
        "Titel": "Title",
        "Podcast": "Podcast",
        "Status": "Status",
        "Søg i titel, podcast, transcript, output": "Search title, podcast, transcript, output",
        "Indlæs transcript igen": "Reload transcript",
        "Slet episode": "Delete episode",
        "Slet podcast og alle episoder": "Delete podcast and all episodes",

        // Transcript status labels
        "Ikke hentet": "Not loaded",
        "Hentet": "Loaded",
        "Fejlet": "Failed",
        "Ikke fundet": "Not found",
        "Henter…": "Loading…",
        "Findes hos Apple": "Available at Apple",

        // Welcome
        "Podcast Transcript Studio": "Podcast Transcript Studio",
        "Indsæt et Apple Podcasts episode-link for at hente og arbejde med transcriptet.":
            "Paste an Apple Podcasts episode link to fetch and work with the transcript.",

        // Common
        "Luk": "Close",
        "Annullér": "Cancel",
        "OK": "OK",
        "Der opstod en fejl": "An error occurred",
        "Kopiér": "Copy",
        "Kopiér som tekst": "Copy as text",
        "Kopiér som Markdown": "Copy as Markdown",
        "Kopiér fejlbesked": "Copy error message",
        "Importér": "Import",
        "Importeret": "Imported",
        "Igen": "Again",
        "Slet": "Delete",

        // AI output
        "AI-svar": "AI answer",
        "AI-output": "AI output",
        "Slet dette AI-svar": "Delete this AI answer",
        "Slet dette AI-svar?": "Delete this AI answer?",
    ]
}
