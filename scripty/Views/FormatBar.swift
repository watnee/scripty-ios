//
//  FormatBar.swift
//  scripty
//
//  Character formatting for the focused element — bold / italic / underline,
//  alignment and typeface — in the same capsule-chip language as
//  ElementTypeBar, which it sits directly above. Every chip reflects the
//  block's current server state, so the bar doubles as an indicator.
//
//  Shown only when the block advertises an `update` link.
//

import SwiftUI

struct FormatBar: View {
    let model: ScriptModel
    let block: Block

    private var align: TextAlign { TextAlign(serverValue: block.textAlign) ?? .left }
    /// nil is a real state here — the element carries no font override and so
    /// prints in the default typeface. The menu shows "Default" for it.
    private var font: ScriptFont? { ScriptFont(serverValue: block.font) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                styleChips
                divider
                alignChips
                divider
                fontMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Bold / italic / underline

    @ViewBuilder
    private var styleChips: some View {
        chip("bold", isOn: block.textBold ?? false, label: "Bold") {
            Task { await model.toggleBold(block) }
        }
        chip("italic", isOn: block.textItalic ?? false, label: "Italic") {
            Task { await model.toggleItalic(block) }
        }
        chip("underline", isOn: block.textUnderline ?? false, label: "Underline") {
            Task { await model.toggleUnderline(block) }
        }
    }

    // MARK: - Alignment

    @ViewBuilder
    private var alignChips: some View {
        ForEach(TextAlign.allCases) { option in
            chip(option.systemImage, isOn: option == align, label: option.label) {
                Task { await model.setAlign(block, to: option) }
            }
        }
    }

    // MARK: - Typeface

    private var fontMenu: some View {
        Menu {
            // "Default" resets the override, matching the web Format menu's
            // "Font: Default". It clears through the bulk endpoint's `clearFont`
            // flag, since the per-block PUT can only set a named font — a blank
            // one there is treated as "leave alone", not "reset".
            fontOption(nil, label: "Default")
            ForEach(ScriptFont.allCases) { option in
                fontOption(option, label: option.label)
            }
        } label: {
            HStack(spacing: 5) {
                Text(font?.label ?? "Default")
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
        .accessibilityLabel("Font")
    }

    @ViewBuilder
    private func fontOption(_ option: ScriptFont?, label: String) -> some View {
        Button {
            Task {
                if let option {
                    await model.setFont(block, to: option)
                } else {
                    await model.bulkClearFont([block.id])
                }
            }
        } label: {
            if option == font {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    // MARK: - Chip

    private func chip(_ systemImage: String, isOn: Bool, label: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.medium))
                .frame(minWidth: 18)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .background(Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }
}
