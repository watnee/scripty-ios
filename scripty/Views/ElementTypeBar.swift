//
//  ElementTypeBar.swift
//  scripty
//
//  The element bar above the keyboard: retype the element you are in, the way
//  the web app's element toolbar does. When that element is a character cue, it
//  offers the project's cast instead, so a name is one tap rather than a
//  re-typing.
//

import SwiftUI

struct ElementTypeBar: View {
    let block: Block
    let characters: [Person]

    let onSelect: (BlockType) -> Void
    let onPickCharacter: (Person) -> Void
    let onDone: () -> Void

    private var type: BlockType { block.blockType }

    /// The classic seven get a button each; the rest live behind the menu.
    private var overflow: [BlockType] {
        BlockType.allCases.filter { !BlockType.tabCycle.contains($0) }
    }

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if type.isCharacterCue, !characters.isEmpty {
                        castButtons
                        Divider().frame(height: 20)
                    }
                    ForEach(BlockType.tabCycle) { candidate in
                        typeButton(candidate)
                    }
                    overflowMenu
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            Divider().frame(height: 20)

            Button("Done", action: onDone)
                .font(.body.weight(.semibold))
        }
    }

    private var castButtons: some View {
        ForEach(characters) { person in
            Button {
                onPickCharacter(person)
            } label: {
                Text(person.displayName.uppercased())
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    private func typeButton(_ candidate: BlockType) -> some View {
        Button {
            onSelect(candidate)
        } label: {
            Text(candidate.label)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(candidate == type ? .accentColor : .secondary)
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(overflow) { candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    // A check marks the current element when it lives in here.
                    Label(candidate.label,
                          systemImage: candidate == type ? "checkmark" : "textformat")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(overflow.contains(type) ? .accentColor : .secondary)
    }
}
