import Foundation

/// A parsed Markdown document with optional YAML frontmatter.
struct FrontmatterDocument {
    var fields: [String: String]
    var body: String
    /// True when the document actually opened with a `---` fence.
    var hadFrontmatter: Bool
}

/// Minimal YAML-frontmatter reader: supports the flat `key: value` subset that prompt files
/// use (PRD-FEAT-006.1). Not a general YAML parser — nesting/lists are intentionally out of scope.
enum FrontmatterParser {
    static func parse(_ text: String) -> FrontmatterDocument {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return FrontmatterDocument(fields: [:], body: text, hadFrontmatter: false)
        }

        var fields: [String: String] = [:]
        var bodyStart = lines.count
        var foundClosing = false
        for index in 1..<lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                bodyStart = index + 1
                foundClosing = true
                break
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty { fields[key] = value }
        }

        // No closing "---" ⇒ the leading "---" was a horizontal rule, not frontmatter. Treat the
        // whole file as the prompt body so a plain Markdown prompt still works.
        guard foundClosing else {
            return FrontmatterDocument(fields: [:], body: text, hadFrontmatter: false)
        }

        let body = lines[bodyStart...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return FrontmatterDocument(fields: fields, body: body, hadFrontmatter: true)
    }

    /// Serialises fields + body back into a `.md` file for the guided fix flow (PRD-FEAT-007).
    static func render(fields: [(String, String)], body: String) -> String {
        var lines = ["---"]
        for (key, value) in fields where !value.isEmpty {
            lines.append("\(key): \(value)")
        }
        lines.append("---")
        lines.append("")
        lines.append(body)
        return lines.joined(separator: "\n")
    }
}
