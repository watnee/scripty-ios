//
//  Fountain detection checks
//
//  `FountainDetector.detect` retypes an element from its text; the client runs
//  it two ways, and the split is the whole point of `liveDetect`:
//
//    - On Return (`detect`) every rule fires — force markers *and* the
//      heuristics (INT./TO:/ALL-CAPS cue), so a finished "INT. HOUSE" line
//      becomes a scene heading when the writer moves on.
//    - Live, per keystroke (`liveDetect`) only the force markers fire, so a
//      half-typed "INT" never flips an action line to a scene mid-word.
//
//  Getting that boundary wrong is invisible in a test that only exercises one
//  of the two, so this pins both — especially that `liveDetect` stays silent
//  on the heuristic-only text `detect` happily retypes.
//
//  Run via Tests/run.sh.
//

import Foundation

var failures = 0

func check(_ label: String, _ actual: some Equatable, _ expected: some Equatable) {
    if "\(actual)" == "\(expected)" {
        print("  PASS  \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label) — expected \(expected), got \(actual)")
    }
}

/// "<type>|<content>" for a detection, or "nil" — so one `check` covers both
/// halves of the result without stringifying a struct's synthesised form.
func shape(_ detection: FountainDetection?) -> String {
    guard let detection else { return "nil" }
    return "\(detection.type)|\(detection.content)"
}

print("Force markers reflow live")
do {
    check("scene",       shape(FountainDetector.liveDetect(".INT. HOUSE")), "scene|INT. HOUSE")
    check("character",   shape(FountainDetector.liveDetect("@bob")),        "character|BOB")
    check("dual cue",    shape(FountainDetector.liveDetect("@bob ^")),      "dualDialogue|BOB")
    check("transition",  shape(FountainDetector.liveDetect(">FADE OUT")),   "transition|FADE OUT")
    check("lyrics",      shape(FountainDetector.liveDetect("~la la la")),   "lyrics|la la la")
    check("section",     shape(FountainDetector.liveDetect("# Act One")),   "section|Act One")
    check("synopsis",    shape(FountainDetector.liveDetect("= she leaves")), "synopsis|she leaves")
    check("page break",  shape(FountainDetector.liveDetect("===")),         "pageBreak|===")
    check("note",        shape(FountainDetector.liveDetect("[[remember]]")), "note|remember")
}

print("Heuristics wait for Return — liveDetect stays silent")
do {
    // The crux: text that `detect` retypes on Return but `liveDetect` must not
    // touch while typing, because the writer may still be mid-word.
    check("INT. heading detect",  shape(FountainDetector.detect("INT. HOUSE")),     "scene|INT. HOUSE")
    check("INT. heading live",    shape(FountainDetector.liveDetect("INT. HOUSE")), "nil")

    check("TO: transition detect", shape(FountainDetector.detect("CUT TO:")),     "transition|CUT TO:")
    check("TO: transition live",   shape(FountainDetector.liveDetect("CUT TO:")), "nil")

    check("ALL-CAPS cue detect",  shape(FountainDetector.detect("MAYA")),     "character|MAYA")
    check("ALL-CAPS cue live",    shape(FountainDetector.liveDetect("MAYA")), "nil")
}

print("liveDetect ignores plain text")
do {
    check("prose",         shape(FountainDetector.liveDetect("She opens the door.")), "nil")
    check("empty",         shape(FountainDetector.liveDetect("")),                     "nil")
    check("whitespace",    shape(FountainDetector.liveDetect("   \n ")),               "nil")
    // "==" is not a page break (needs three) and not a synopsis (that rules out
    // a leading "=="), so even though it opens with a marker char there is
    // nothing to detect — the marker gate lets it through, `detect` declines.
    check("two equals",    shape(FountainDetector.liveDetect("==")),                   "nil")
    // A leading force-marker character trims first: indentation before "." must
    // still count as a scene force, matching the web's `value.trim()`.
    check("indented scene", shape(FountainDetector.liveDetect("  .INT. CAR")),         "scene|INT. CAR")
}

if failures == 0 {
    print("All fountain detection checks passed.")
    exit(0)
} else {
    print("\(failures) fountain detection check(s) FAILED.")
    exit(1)
}
