//
//  BlockRowView.swift
//  scripty
//
//  Typographic rendering of one screenplay element, roughly following
//  screenplay page conventions inside a centered page column.
//

import SwiftUI

/// The writer's chosen type size, as a multiplier. Read by every element row
/// so one setting scales the whole script.
private struct ScriptTextScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var scriptTextScale: Double {
        get { self[ScriptTextScaleKey.self] }
        set { self[ScriptTextScaleKey.self] = newValue }
    }
}

extension BlockHighlight {
    /// The tints from the web app's stylesheet, so a highlighted line looks the
    /// same in either client. Each carries a light and a dark value — a
    /// paper-coloured wash would go muddy in dark mode.
    func color(for scheme: ColorScheme) -> Color {
        let light: (Double, Double, Double)
        let dark: (Double, Double, Double)
        switch self {
        case .yellow:
            light = (0.992, 0.953, 0.827); dark = (0.294, 0.235, 0.078)
        case .green:
            light = (0.875, 0.949, 0.890); dark = (0.122, 0.251, 0.161)
        case .blue:
            light = (0.859, 0.914, 0.973); dark = (0.110, 0.227, 0.333)
        case .red:
            light = (0.984, 0.878, 0.867); dark = (0.302, 0.153, 0.141)
        case .gray:
            light = (0.914, 0.925, 0.937); dark = (0.227, 0.259, 0.314)
        }
        let (r, g, b) = scheme == .dark ? dark : light
        return Color(red: r, green: g, blue: b)
    }
}

/// Paints a block's highlight tint behind its text, and nothing when it has
/// none. Shared so the read-only and editable rows tint identically.
struct BlockHighlightBackground: ViewModifier {
    let block: Block
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if let highlight = BlockHighlight(serverValue: block.highlight) {
            content
                .padding(.horizontal, 4)
                .background(highlight.color(for: colorScheme),
                            in: RoundedRectangle(cornerRadius: 3))
        } else {
            content
        }
    }
}

extension View {
    func blockHighlight(_ block: Block) -> some View {
        modifier(BlockHighlightBackground(block: block))
    }
}

/// "3 comments on this line", as a bubble and a number beside the pin and
/// bookmark badges. Draws nothing at all when the count is zero, which is most
/// elements — and is also what a server that never offered the count looks
/// like, so the row degrades to how it looked before.
///
/// Deliberately not tinted like the pin and bookmark: those are marks the
/// writer put on the line themselves, while this is other people's.
struct CommentCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Label("\(count)", systemImage: "bubble.left.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
        }
    }

    /// How the badge reads aloud, or nil when there is nothing to say. Rows
    /// hide the badges from VoiceOver and fold them into the row's own label
    /// instead, so a screen reader hears one element per line rather than
    /// several.
    static func spokenLabel(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "1 comment"
        default: return "\(count) comments"
        }
    }
}

struct BlockRowView: View {
    let block: Block
    /// How many comments sit on this element. Defaults to none so the row can
    /// still be rendered somewhere the counts aren't loaded — the bulk-action
    /// preview strip, for one.
    var commentCount: Int = 0

    @Environment(\.scriptTextScale) private var textScale

    /// The continuous column stands in for the printed six-inch text block, so
    /// the speech widths are the real screenplay proportions rather than
    /// hand-picked numbers: dialogue is 3.5in of 6in, parentheticals 2in.
    private static let pageWidth: CGFloat = 640
    private static var dialogueWidth: CGFloat {
        pageWidth * CGFloat(ScreenplayLayout.dialogueBox.widthFraction)
    }
    private static var parentheticalWidth: CGFloat {
        pageWidth * CGFloat(ScreenplayLayout.parentheticalBox.widthFraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            elementView
                .blockHighlight(block)
            tagRow
        }
        .frame(maxWidth: Self.pageWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) { badges }
        // A screenplay is carried by which *kind* of line each one is: sighted
        // readers get that from the indentation and the capitalisation, both of
        // which are purely visual. Without naming the type, VoiceOver reads a
        // scene heading, a character cue and a transition identically.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if block.blockType == .pageBreak { return "Page break" }

        var parts = [block.blockType.label]
        let content = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(content.isEmpty ? "empty" : content)

        let tags = block.tagList
        if !tags.isEmpty {
            parts.append("Tagged " + tags.joined(separator: ", "))
        }
        if block.isPinned { parts.append("Pinned") }
        if block.isBookmarked { parts.append("Bookmarked") }
        if let comments = CommentCountBadge.spokenLabel(commentCount) {
            parts.append(comments)
        }
        return parts.joined(separator: ". ")
    }

    /// Tags sit under the element as small badges, the way the web row shows
    /// them. Nothing is drawn when a block has none.
    @ViewBuilder
    private var tagRow: some View {
        let tags = block.tagList
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var elementView: some View {
        switch block.blockType {
        case .scene:
            styledText(displayContent.uppercased())
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.top, 18)

        case .character, .dualDialogue:
            styledText(displayContent.uppercased())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)

        case .dialogue:
            styledText(displayContent)
                .frame(maxWidth: Self.dialogueWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)

        case .parenthetical:
            styledText(parenthesized(displayContent))
                .italic()
                .frame(maxWidth: Self.parentheticalWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)

        case .transition:
            styledText(displayContent.uppercased())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 10)

        case .shot:
            styledText(displayContent.uppercased())
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.top, 10)

        case .centered:
            styledText(displayContent)
                .frame(maxWidth: .infinity, alignment: .center)

        case .lyrics:
            styledText(displayContent)
                .italic()
                .frame(maxWidth: Self.dialogueWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)

        case .section:
            styledText(displayContent)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)

        case .synopsis:
            styledText(displayContent)
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .note:
            styledText(displayContent)
                .font(.callout)
                .padding(8)
                .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .pageBreak:
            HStack(spacing: 12) {
                line
                Text("PAGE BREAK")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                line
            }
            .padding(.vertical, 8)

        case .action, .text:
            styledText(displayContent)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private var line: some View {
        Rectangle()
            .fill(.tertiary)
            .frame(height: 1)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            // The writer's own marks share one tint; the comment badge brings
            // its own, since it is other people's.
            HStack(spacing: 4) {
                if block.isPinned {
                    Image(systemName: "pin.fill")
                }
                if block.isBookmarked {
                    Image(systemName: "bookmark.fill")
                }
            }
            .foregroundStyle(.orange)
            CommentCountBadge(count: commentCount)
        }
        .font(.caption2)
    }

    /// Character cues carry the speaker name as content; fall back to the
    /// linked character when the content is empty.
    private var displayContent: String {
        let content = block.content ?? ""
        if content.isEmpty, block.blockType.isCharacterCue, let name = block.personName {
            return name
        }
        return content
    }

    private func parenthesized(_ text: String) -> String {
        text.hasPrefix("(") ? text : "(\(text))"
    }

    private var alignment: Alignment {
        switch TextAlign(serverValue: block.textAlign) {
        case .center: return .center
        case .right: return .trailing
        case .left, .none: return .leading
        }
    }

    private func styledText(_ string: String) -> Text {
        var text = Text(string.isEmpty ? " " : string)
            .font(baseFont)
        if block.textBold ?? false { text = text.bold() }
        if block.textItalic ?? false { text = text.italic() }
        if block.textUnderline ?? false { text = text.underline() }
        return text
    }

    private var baseFont: Font {
        let size = 16 * textScale
        switch ScriptFont(serverValue: block.font) {
        case .arial:
            return .custom("Helvetica", size: size)
        case .timesNewRoman:
            return .custom("Times New Roman", size: size)
        case .courierPrime, .none:
            // Screenplay convention: Courier-style monospace.
            return .system(size: size, design: .monospaced)
        }
    }
}
