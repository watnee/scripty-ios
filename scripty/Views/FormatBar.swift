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
    private var font: ScriptFont { ScriptFont(serverValue: block.font) ?? .courierPrime }

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
            Picker("Font", selection: fontBinding) {
                ForEach(ScriptFont.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(font.label)
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

    private var fontBinding: Binding<ScriptFont> {
        Binding(
            get: { font },
            set: { newValue in Task { await model.setFont(block, to: newValue) } })
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
