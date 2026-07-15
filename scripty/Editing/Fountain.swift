//
//  Fountain.swift
//  scripty
//
//  Fountain shorthand detection, ported from the web editor's fountain-power.js
//  so a script typed on iOS retypes itself the same way it does in the browser:
//  a leading `.` becomes a scene heading, `>` a transition, `@NAME` a character
//  cue, and — on Return — bare patterns like "INT. …", "CUT TO:", "ANGLE ON …",
//  "(beat)" and ALL-CAPS cue lines snap to their element type too.
//
//  Two entry points mirror the two moments the web runs detection:
//   - `liveDetect` fires as you type, but only for the force-marker prefixes,
//     matching the web's input handler (so plain action text is left alone).
//   - `detect` is the full rule set, run on Return, where a bare heading or
//     transition should convert even without a marker.
//

import Foundation

enum Fountain {
    struct Detection: Equatable {
        let type: BlockType
        let content: String
    }

    /// The force-marker prefixes that trigger conversion mid-typing.
    static func liveDetect(_ raw: String) -> Detection? {
        let trimmed = raw.replacingOccurrences(of: "\u{00a0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasForceMarker(trimmed) else { return nil }
        return detect(raw)
    }

    /// Whether typing this text should convert the block right now (leading
    /// `. @ > ~ # =`, or `[[`, or a `===` page break).
    static func hasForceMarker(_ trimmed: String) -> Bool {
        guard let first = trimmed.first else { return false }
        if ".@>~#=".contains(first) { return true }
        return trimmed.hasPrefix("[[")
    }

    /// The full detection rule set (markers plus bare heuristics), run on Return.
    static func detect(_ raw: String) -> Detection? {
        let text = raw.replacingOccurrences(of: "\u{00a0}", with: "")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let firstLine = String(trimmed.split(separator: "\n", omittingEmptySubsequences: false)[0])
            .trimmingCharacters(in: .whitespaces)
        let singleLine = (trimmed == firstLine)

        // === page break
        if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "=" }) {
            return Detection(type: .pageBreak, content: "===")
        }
        // [[ note ]]
        if trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") {
            let inner = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
            return Detection(type: .note, content: inner)
        }
        // # section
        if firstLine.hasPrefix("#") {
            return Detection(type: .section,
                             content: stripFirstLine(trimmed) { dropRun($0, of: "#") })
        }
        // = synopsis (but not == which reads as something else)
        if firstLine.hasPrefix("="), !firstLine.hasPrefix("==") {
            return Detection(type: .synopsis,
                             content: stripFirstLine(trimmed) { dropRun($0, of: "=") })
        }
        // ~ lyrics
        if firstLine.hasPrefix("~") {
            return Detection(type: .lyrics,
                             content: stripFirstLine(trimmed) { dropOne($0, of: "~") })
        }
        // . scene (but not .. )
        if firstLine.hasPrefix("."), !firstLine.hasPrefix("..") {
            return Detection(type: .scene,
                             content: stripFirstLine(trimmed) { dropOne($0, of: ".") })
        }
        // @ character cue
        if firstLine.hasPrefix("@") {
            let dual = endsWithCaret(firstLine)
            let cue = stripTrailingCaret(String(firstLine.dropFirst()).trimmingCharacters(in: .whitespaces))
            let content: String
            if singleLine {
                content = cue.uppercased()
            } else if let nl = trimmed.firstIndex(of: "\n") {
                content = cue.uppercased() + trimmed[nl...]
            } else {
                content = cue.uppercased()
            }
            return Detection(type: dual ? .dualDialogue : .character, content: content)
        }
        // > centered <  (single line only)
        if firstLine.hasPrefix(">"), firstLine.hasSuffix("<"), firstLine.count > 2 {
            guard singleLine else { return nil }
            let inner = String(firstLine.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            return Detection(type: .centered, content: inner)
        }
        // > transition  (single line only)
        if firstLine.hasPrefix(">") {
            guard singleLine else { return nil }
            return Detection(type: .transition,
                             content: String(firstLine.dropFirst()).trimmingCharacters(in: .whitespaces))
        }

        // Bare heuristics — single line only, so multi-line action is never
        // truncated when Return runs detection.
        guard singleLine else { return nil }

        if matches(Patterns.sceneHeading, firstLine) {
            return Detection(type: .scene, content: firstLine)
        }
        if matches(Patterns.transition, firstLine) {
            return Detection(type: .transition, content: firstLine)
        }
        if matches(Patterns.shot, firstLine) {
            return Detection(type: .shot, content: firstLine)
        }
        if firstLine.hasPrefix("(") {
            let body: String
            if firstLine.hasSuffix(")") {
                body = String(firstLine.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            } else {
                body = String(firstLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return Detection(type: .parenthetical, content: body)
        }
        if isCharacterCueLine(firstLine) {
            let dual = endsWithCaret(firstLine)
            let name = stripTrailingCaret(
                (firstLine.hasPrefix("@") ? String(firstLine.dropFirst()) : firstLine)
                    .trimmingCharacters(in: .whitespaces))
            return Detection(type: dual ? .dualDialogue : .character, content: name)
        }

        return nil
    }

    // MARK: - Character-cue heuristic

    private static func isCharacterCueLine(_ line: String) -> Bool {
        if line.isEmpty || line.count > 60 { return false }
        if let last = line.last, ".?!".contains(last) { return false }
        if matches(Patterns.sceneHeading, line)
            || matches(Patterns.transition, line)
            || matches(Patterns.shot, line) { return false }

        var core = line
        if core.hasPrefix("@") { core = String(core.dropFirst()) }
        core = stripTrailingCaret(core).trimmingCharacters(in: .whitespaces)
        if core.isEmpty { return false }

        // Allow parenthetical extensions like "JOE (V.O.)"
        let base = removingTrailingParenthetical(core).trimmingCharacters(in: .whitespaces)
        if !matches(Patterns.cueBase, base) { return false }
        if base.split(whereSeparator: { $0 == " " || $0 == "\t" }).count > 5 { return false }
        if !base.contains(where: { $0.isASCII && $0.isUppercase && $0.isLetter }) { return false }
        return base == base.uppercased()
    }

    // MARK: - String helpers

    private static func stripFirstLine(_ trimmed: String,
                                       _ transform: (String) -> String) -> String {
        if let nl = trimmed.firstIndex(of: "\n") {
            return transform(String(trimmed[..<nl])) + String(trimmed[nl...])
        }
        return transform(trimmed)
    }

    /// Drops a run of `char` from the start, then leading spaces (mirrors `^X+\s*`).
    private static func dropRun(_ s: String, of char: Character) -> String {
        var sub = Substring(s)
        while sub.first == char { sub = sub.dropFirst() }
        while let f = sub.first, f == " " || f == "\t" { sub = sub.dropFirst() }
        return String(sub)
    }

    /// Drops a single `char` from the start, then leading spaces (mirrors `^X\s*`).
    private static func dropOne(_ s: String, of char: Character) -> String {
        var sub = Substring(s)
        if sub.first == char { sub = sub.dropFirst() }
        while let f = sub.first, f == " " || f == "\t" { sub = sub.dropFirst() }
        return String(sub)
    }

    private static func endsWithCaret(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespaces).hasSuffix("^")
    }

    /// Removes a trailing `^` (with surrounding spaces), mirroring `\s*\^\s*$`.
    private static func stripTrailingCaret(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("^") { t = String(t.dropLast()) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Removes a trailing `(…)`, mirroring `\s*\([^)]*\)\s*$`.
    private static func removingTrailingParenthetical(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasSuffix(")"), let open = t.lastIndex(of: "(") else { return t }
        // Only strip when the parentheses are a clean trailing group.
        let inside = t[t.index(after: open)..<t.index(before: t.endIndex)]
        if inside.contains(")") { return t }
        return String(t[..<open])
    }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // MARK: - Regex patterns (ported verbatim from fountain-power.js)

    private enum Patterns {
        static let sceneHeading = make(
            #"^(?:INT\.?|EXT\.?|EST\.?|INT\.?/EXT\.?|I/E\.?)\s+.+"#, caseInsensitive: true)
        static let transition = make(
            #"^[A-Z][A-Z0-9 ]+ TO:$"#, caseInsensitive: false)
        static let shot = make(
            #"^(?:ANGLE ON|ANOTHER ANGLE|CLOSE ON|CLOSE UP|CLOSEUP|C\.U\.?|CU|POV|INSERT|BACK TO SCENE|BACK TO|TIGHT ON|WIDER(?: SHOT)?|TRACKING|CRANE|AERIAL|ESTABLISHING|FAVOR ON|REVERSE ANGLE)\b.*"#,
            caseInsensitive: true)
        static let cueBase = make(
            #"^[A-Z0-9][A-Z0-9 \-'.]*$"#, caseInsensitive: false)

        private static func make(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression {
            let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
            // Patterns are fixed literals; a failure here is a programmer error.
            return try! NSRegularExpression(pattern: pattern, options: options)
        }
    }
}
