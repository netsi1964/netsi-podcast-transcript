import Foundation
import CryptoKit

/// Reads `.md` prompt files into `Prompt` values and validates their frontmatter
/// (PRD-FEAT-006 / PRD-FEAT-007). Pure logic — no filesystem watching here.
enum PromptLoader {

    /// Parses one prompt file's raw text. `id`/`fileModifiedAt` come from the caller since
    /// they depend on the file itself.
    static func makePrompt(fromContents text: String, filePath: String, modifiedAt: Date) -> Prompt {
        let doc = FrontmatterParser.parse(text)
        let title = doc.fields["title"] ?? deriveTitle(fromPath: filePath)
        let id = doc.fields["id"] ?? stableID(forPath: filePath)
        let (status, message) = validate(doc: doc)

        return Prompt(
            id: id,
            filePath: filePath,
            title: title,
            description: doc.fields["description"],
            version: doc.fields["version"] ?? "0",
            preferredProvider: doc.fields["preferredprovider"],
            preferredModel: doc.fields["preferredmodel"],
            outputType: doc.fields["outputtype"],
            bodyMarkdown: doc.body,
            validationStatus: status,
            validationMessage: message
        , fileModifiedAt: modifiedAt)
    }

    /// A prompt is `invalid` if it has no usable body or no frontmatter at all; `warning`
    /// if recommended metadata is missing; otherwise `valid` (PRD-FEAT-007 acceptance).
    /// A prompt only needs instruction text — a plain `.md` file works, with the title taken from
    /// the filename. Frontmatter is optional polish, so its absence is at most a gentle warning,
    /// never `invalid` (only an empty file is invalid).
    static func validate(doc: FrontmatterDocument) -> (PromptValidationStatus, String?) {
        if doc.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (.invalid, "Prompten er tom – skriv din instruktion i filen.")
        }
        if !doc.hadFrontmatter {
            // Perfectly usable; title comes from the filename. Just a hint, not a problem.
            return (.warning, "Ingen frontmatter – titel tages fra filnavnet.")
        }
        if (doc.fields["title"] ?? "").isEmpty {
            return (.warning, "Mangler anbefalet metadata: title.")
        }
        return (.valid, nil)
    }

    private static func deriveTitle(fromPath path: String) -> String {
        (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Deterministic id from the file path, so a prompt keeps its identity across restarts
    /// even without an explicit `id:` field.
    private static func stableID(forPath path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return "prompt-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
