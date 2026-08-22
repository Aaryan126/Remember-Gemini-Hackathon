import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProjectMemoryExportDocument: FileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static var readableContentTypes: [UTType] { [markdownType, .plainText] }

    let content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let content = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.content = content
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}

nonisolated enum ProjectMemoryMarkdownRenderer {
    static func render(
        pages: [WikiPageSnapshot],
        history: [ProjectMemoryRunSnapshot],
        generatedAt: Date = Date()
    ) -> String {
        let program = ProjectMemoryProgram.current
        var lines = [
            "---",
            "format: remember-project-memory",
            "format_version: 1",
            "program: \(yaml(program.name))",
            "program_version: \(yaml(program.version))",
            "generated_at: \(generatedAt.formatted(.iso8601))",
            "privacy: local-export",
            "---",
            "",
            "# Project Memory",
            "",
            program.objective,
            "",
            "> This is a portable Markdown projection. Original images, PDFs, audio, and the private SQLite vault are not embedded.",
            "",
            "## Index",
            "",
        ]

        for kind in program.pageKinds {
            let matchingPages = pages.filter { $0.page.kind == kind }
            guard !matchingPages.isEmpty else { continue }
            lines.append("### \(kind.label)")
            lines.append("")
            for snapshot in matchingPages.sorted(by: { $0.page.title.localizedCaseInsensitiveCompare($1.page.title) == .orderedAscending }) {
                lines.append("- [\(markdown(snapshot.page.title))](#\(anchor(snapshot.page.title)))")
            }
            lines.append("")
        }

        lines += ["## Pages", ""]
        for snapshot in pages.sorted(by: pageSort) {
            let page = snapshot.page
            lines += [
                "### \(markdown(page.title))",
                "",
                "- **Type:** \(page.kind.singularLabel)",
                "- **Page ID:** `\(page.id.uuidString)`",
                "- **Version:** \(page.revisionNumber)",
                "- **Updated:** \(page.updatedAt.formatted(.iso8601))",
            ]
            if !page.aliases.isEmpty {
                lines.append("- **Aliases:** \(page.aliases.map(markdown).joined(separator: ", "))")
            }
            lines += ["", page.summary, ""]

            if !snapshot.linkedPages.isEmpty {
                lines += ["#### Connections", ""]
                for link in snapshot.linkedPages {
                    lines.append("- **\(markdown(link.page.title))** — \(markdown(link.rationale))")
                }
                lines.append("")
            }

            lines += ["#### Sources", ""]
            if snapshot.evidence.isEmpty {
                lines += ["- Source memory no longer exists.", ""]
            } else {
                for source in snapshot.evidence {
                    lines.append("- `\(source.memory.id.uuidString)` — **\(markdown(source.memory.displayTitle))** (\(source.memory.createdAt.formatted(.iso8601))); \(source.evidence.effect.label): \(markdown(source.evidence.rationale))")
                }
                lines.append("")
            }

            lines += ["#### Revision history", ""]
            for revision in snapshot.revisions.sorted(by: { $0.revisionNumber < $1.revisionNumber }) {
                lines.append("- **v\(revision.revisionNumber) · \(revision.effect.label)** — \(revision.createdAt.formatted(.iso8601)); model `\(markdown(revision.modelVersion))`; \(markdown(revision.rationale))")
                if let previous = revision.previousSummary, previous != revision.newSummary {
                    lines.append("  - Before: \(markdown(previous))")
                    lines.append("  - After: \(markdown(revision.newSummary))")
                }
            }
            lines += ["", "---", ""]
        }

        lines += ["## Research History", ""]
        if history.isEmpty {
            lines += ["No project-memory operations have been recorded yet.", ""]
        } else {
            for snapshot in history.sorted(by: { $0.run.startedAt > $1.run.startedAt }) {
                let run = snapshot.run
                lines += [
                    "### \(run.operation.label) · \(run.status.label)",
                    "",
                    "- **Run ID:** `\(run.id.uuidString)`",
                    "- **Started:** \(run.startedAt.formatted(.iso8601))",
                    "- **Program:** `\(markdown(run.programVersion))`",
                    "- **Prompt:** `\(markdown(run.promptVersion))`",
                    "- **Model:** `\(markdown(run.modelVersion))`",
                ]
                if let memoryTitle = snapshot.memoryTitle {
                    lines.append("- **Source:** \(markdown(memoryTitle))")
                }
                lines += [
                    "- **Result:** \(run.acceptedPageCount) of \(run.proposedPageCount) proposed page changes kept",
                    "",
                    markdown(run.rationale),
                    "",
                ]
                if !snapshot.checks.isEmpty {
                    lines += ["#### Checks", ""]
                    for check in snapshot.checks {
                        lines.append("- \(check.passed ? "[x]" : "[ ]") **\(markdown(check.label))** (`\(check.severity.rawValue)`) — \(markdown(check.message))")
                    }
                    lines.append("")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func pageSort(_ left: WikiPageSnapshot, _ right: WikiPageSnapshot) -> Bool {
        let kinds = ProjectMemoryProgram.current.pageKinds
        let leftIndex = kinds.firstIndex(of: left.page.kind) ?? kinds.endIndex
        let rightIndex = kinds.firstIndex(of: right.page.kind) ?? kinds.endIndex
        if leftIndex != rightIndex { return leftIndex < rightIndex }
        return left.page.title.localizedCaseInsensitiveCompare(right.page.title) == .orderedAscending
    }

    private static func markdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func anchor(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    private static func yaml(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
