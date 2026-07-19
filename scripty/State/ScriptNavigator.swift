//
//  ScriptNavigator.swift
//  scripty
//
//  The one piece of shared state between the navigation surfaces (outline,
//  search, stats) and the scrolling script page. A view that wants to send the
//  reader somewhere sets `pendingScrollTarget`; ScriptView's ScrollViewReader
//  observes it, scrolls, and clears it back to nil so the same block can be
//  targeted twice in a row.
//

import Foundation
import Observation

@Observable @MainActor
final class ScriptNavigator {
    /// The block id the script page should scroll to, or nil when there is
    /// nothing pending. ScriptView clears this once it has scrolled.
    var pendingScrollTarget: Int?

    /// Ask the script page to bring `blockId` into view.
    func jump(to blockId: Int) {
        pendingScrollTarget = blockId
    }

    /// Called by the script page after the scroll has been performed.
    func consumeScrollTarget() {
        pendingScrollTarget = nil
    }
}
