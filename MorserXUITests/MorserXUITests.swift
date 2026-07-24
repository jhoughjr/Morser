//
//  MorserXUITests.swift
//  MorserXUITests
//
//  A launch-and-drive smoke test.
//
//  196 unit tests prove the arithmetic — encoding, the fist decoder, the mix —
//  but none of them can tell whether the window comes up, the practice sheet
//  opens, or a drill can be selected without the view tree falling over. That's
//  the class of breakage these cover: not "is the answer right" but "does it run
//  at all", across every practice mode, which no unit test sees.
//

import XCTest

final class MorserXUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesToAWindow() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "no window appeared on launch")
    }

    /// Typing produces morse. The whole app is downstream of this one edge —
    /// it's the bug this session started on — so it's worth a UI-level guard.
    @MainActor
    func testTypingProducesMorse() throws {
        let app = XCUIApplication()
        app.launch()

        let field = app.textFields["inputField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "input field missing")

        field.click()
        field.typeKey("a", modifierFlags: .command)   // select all
        field.typeText("sos")

        // The encoded string is shown beneath the field; "..." is S.
        let morse = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "...", "...")
        ).firstMatch
        XCTAssertTrue(morse.waitForExistence(timeout: 5),
                      "typing text produced no morse on screen")
    }

    /// The practice sheet opens and every drill can be selected. A broken view
    /// tree for any one mode would crash here rather than in front of someone.
    @MainActor
    func testEveryPracticeModeSelectable() throws {
        let app = XCUIApplication()
        app.launch()

        let practice = app.buttons["practiceButton"]
        XCTAssertTrue(practice.waitForExistence(timeout: 10), "practice button missing")
        practice.click()

        // Anchor on the sheet's own control, not the picker — a segmented picker's
        // element type varies, but if the sheet is up at all, Done is there.
        XCTAssertTrue(app.buttons["practiceDone"].waitForExistence(timeout: 5),
                      "practice sheet didn't open")

        // A macOS segmented picker exposes its options as radio buttons. Walk
        // whichever segments are found and confirm each opens its section without
        // tearing the sheet down — that's the per-mode view breakage a unit test
        // can't see. Finding none is itself a failure: the walk would be vacuous.
        var walked = 0
        for mode in ["Koch", "Character set", "Callsigns", "QSO", "Words",
                     "Head copy", "Instant", "Sending", "ABC song", "Pileup", "My text"] {
            let segment = app.radioButtons[mode].exists ? app.radioButtons[mode] : app.buttons[mode]
            guard segment.exists else { continue }
            walked += 1
            // The currently-selected segment reports not-hittable; its section is
            // already on screen, so a click isn't needed to have exercised it.
            guard segment.isHittable else { continue }
            segment.click()
            XCTAssertTrue(app.buttons["practiceDone"].waitForExistence(timeout: 2),
                          "\(mode) tore the sheet down")
        }
        // All eleven drills should be present as segments, not just reachable.
        XCTAssertEqual(walked, 11, "expected 11 drill segments, found \(walked)")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
