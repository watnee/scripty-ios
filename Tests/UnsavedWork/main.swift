//
//  main.swift
//  Tests/UnsavedWork
//
//  What happens to the writer's words when a save doesn't land.
//
//  Every case here drives a real ScriptModel against a real APIClient pointed
//  at a closed port, so the failures are genuine transport failures travelling
//  the genuine error path — no stubbed-out client, no injected error. The
//  question each one asks is the same: after the write fails, is what the
//  writer typed still there?
//

import Foundation

// MARK: - Harness

var failures = 0

func check(_ label: String, _ condition: Bool) {
    print(condition ? "  PASS  \(label)" : "  FAIL  \(label)")
    if !condition { failures += 1 }
}

func checkEqual<T: Equatable>(_ label: String, _ actual: T, _ expected: T) {
    let ok = actual == expected
    print(ok ? "  PASS  \(label)" : "  FAIL  \(label)\n          expected: \(expected)\n          actual:   \(actual)")
    if !ok { failures += 1 }
}

func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
    try! JSONDecoder().decode(T.self, from: Data(json.utf8))
}

/// A project with no links: nothing this suite drives needs one, and their
/// absence keeps the model from reaching for endpoints the test doesn't care
/// about (undo/redo status, sync polling).
let project: Project = decode(Project.self, #"{"id": 1, "title": "Test Script"}"#)

/// Two adjacent editable elements, each advertising the update and delete
/// links the editing paths gate on. The hrefs point at the closed port, so
/// following one fails the way a lost connection does.
func twoBlockCollection() -> HALCollection<Block> {
    decode(HALCollection<Block>.self, """
    {
      "_embedded": {
        "blockResourceList": [
          {
            "id": 10, "order": 1, "type": "ACTION", "content": "First line.",
            "_links": {
              "update": {"href": "/api/blocks/10"},
              "delete": {"href": "/api/blocks/10"},
              "createBelow": {"href": "/api/blocks/10/below"}
            }
          },
          {
            "id": 11, "order": 2, "type": "ACTION", "content": "Second line.",
            "_links": {
              "update": {"href": "/api/blocks/11"},
              "delete": {"href": "/api/blocks/11"},
              "createBelow": {"href": "/api/blocks/11/below"}
            }
          }
        ]
      },
      "_links": {"self": {"href": "/api/projects/1/blocks"}}
    }
    """)
}

@MainActor
func makeModel() -> ScriptModel {
    let model = ScriptModel(app: AppModel(), project: project)
    model.adopt(twoBlockCollection())
    return model
}

@MainActor
func blocks(_ model: ScriptModel) -> (first: Block, second: Block) {
    (model.blocks[0], model.blocks[1])
}

// MARK: - Cases

@MainActor
func run() async {
    // Point every APIClient at a port nothing is listening on. Connecting is
    // refused immediately, which is the transport failure the retry and
    // hold-the-text logic exists for.
    UserDefaults.standard.set("http://127.0.0.1:1", forKey: AppConfig.baseURLOverrideKey)

    print("== A failed commit keeps the typing ==")
    do {
        let model = makeModel()
        let (first, _) = blocks(model)

        model.liveEdit(first, text: "First line, rewritten.")
        await model.blur(first)

        checkEqual("the rewritten text is still on screen",
                   model.currentText(model.blocks[0]), "First line, rewritten.")
        check("the block is flagged unsaved", model.unsavedBlockIds.contains(first.id))
        check("the model reports unsaved work", model.hasUnsavedChanges)
    }

    print()
    print("== A failed split leaves the line whole ==")
    do {
        let model = makeModel()
        let (first, _) = blocks(model)

        model.liveEdit(first, text: "Before and after.")
        // Return pressed between "Before" and " and after."
        await model.splitBlock(model.blocks[0], caret: 6)

        checkEqual("no new element was created", model.blocks.count, 2)
        checkEqual("the whole line survives in the original block",
                   model.currentText(model.blocks[0]), "Before and after.")
        check("the block is flagged unsaved", model.unsavedBlockIds.contains(first.id))
    }

    print()
    print("== A failed merge leaves both elements alone ==")
    do {
        let model = makeModel()
        let (first, second) = blocks(model)

        await model.mergeIntoPrevious(second)

        checkEqual("both elements are still there", model.blocks.count, 2)
        checkEqual("the first keeps its own text",
                   model.currentText(model.blocks[0]), "First line.")
        checkEqual("the second keeps its own text",
                   model.currentText(model.blocks[1]), "Second line.")
        check("neither shows the merged text twice",
              !model.currentText(model.blocks[0]).contains("Second line."))
        check("nothing is left flagged unsaved", !model.unsavedBlockIds.contains(first.id))
    }

    print()
    print("== A failed retype keeps the typing ==")
    do {
        let model = makeModel()
        let (first, _) = blocks(model)

        model.liveEdit(first, text: "INT. KITCHEN - DAY")
        await model.changeType(model.blocks[0], to: .scene)

        checkEqual("the text survives the failed type change",
                   model.currentText(model.blocks[0]), "INT. KITCHEN - DAY")
        check("the block is flagged unsaved", model.unsavedBlockIds.contains(first.id))
    }

    print()
    print("== Transport failures are named, not leaked ==")
    do {
        checkEqual("a refused connection reads as offline",
                   APIError.from(transportError: URLError(.cannotConnectToHost)),
                   APIError.offline)
        checkEqual("a dropped connection reads as offline",
                   APIError.from(transportError: URLError(.networkConnectionLost)),
                   APIError.offline)
        check("offline is worth retrying", APIError.offline.isRetryable)
        check("a timeout is worth retrying", APIError.timedOut.isRetryable)
        check("a 503 is worth retrying", APIError.server(status: 503).isRetryable)
        check("a 403 is not", !APIError.forbidden.isRetryable)
        check("a validation failure is not", !APIError.validation([:]).isRetryable)
        check("an unusable link is not", !APIError.invalidLink("nope").isRetryable)
        check("the offline message mentions the work is kept",
              APIError.offline.errorDescription?.contains("kept on this device") == true)
    }

    print()
    if failures == 0 {
        print("ALL CHECKS PASSED")
    } else {
        print("\(failures) CHECK(S) FAILED")
    }
}

await run()
exit(failures == 0 ? 0 : 1)

// `APIError` carries associated values, so equality for the assertions above
// is spelled out rather than synthesised.
extension APIError: Equatable {
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized), (.forbidden, .forbidden),
             (.notFound, .notFound), (.offline, .offline), (.timedOut, .timedOut):
            return true
        case (.validation(let a), .validation(let b)): return a == b
        case (.server(let a), .server(let b)): return a == b
        case (.invalidLink(let a), .invalidLink(let b)): return a == b
        case (.transport(let a), .transport(let b)): return a == b
        default: return false
        }
    }
}
