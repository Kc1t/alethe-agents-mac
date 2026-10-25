import XCTest

@MainActor
final class HitTargetTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launchFixture(scale: Double, extra: [String] = []) -> XCUIApplication {
        launchAlethe(arguments: ["-AletheUITestFixture", "hit-targets", "-AletheUITestScale", "\(scale)"] + extra).0
    }

    private func missedControls(in app: XCUIApplication) -> [String] {
        var missed: [String] = []

        let toggle = app.checkBoxes["fixture.toggle"].firstMatch
        let toggleBefore = toggle.value as? Int
        toggle.click()
        if toggle.value as? Int == toggleBefore { missed.append("toggle") }

        let button = app.buttons["fixture.button"].firstMatch
        button.click()
        if (button.value as? String) != "1" { missed.append("button") }

        let segments = app.radioGroups["fixture.segments"].firstMatch
        let third = segments.radioButtons.element(boundBy: 2)
        third.click()
        if (third.value as? Int) != 1 { missed.append("segments") }

        let field = app.textFields["fixture.field"].firstMatch
        field.click()
        if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
            field.typeText("ok")
        }
        if (field.value as? String) != "ok" { missed.append("field") }

        let appKit = app.buttons["fixture.appkit"].firstMatch
        appKit.click()
        if (appKit.value as? String) != "1" { missed.append("appkit") }

        return missed
    }

    func testControlsReceiveClicksAtEveryUIScale() {
        for scale in [0.9, 1.0, 1.2] {
            let app = launchFixture(scale: scale)
            XCTAssertEqual(missedControls(in: app), [], "controls missed at UI scale \(scale)")
            app.terminate()
        }
    }

    func testHarnessDetectsClickSwallowingOverlay() {
        let app = launchFixture(scale: 1.0, extra: ["-AletheUITestBrokenOverlay", "YES"])
        let missed = missedControls(in: app)
        XCTAssertFalse(missed.isEmpty, "an overlay swallowing clicks must be detected")
        app.terminate()
    }

    func testScaleEffectHitTestingOnThisOS() {
        let app = launchFixture(scale: 0.8, extra: ["-AletheUITestBrokenScale", "YES"])
        XCTAssertEqual(missedControls(in: app), [])
        app.terminate()
    }
}
