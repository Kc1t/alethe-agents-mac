import XCTest

@MainActor
final class ProjectCloneTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func testClonesALocalBareRepository() {
        let (app, root) = launchAlethe(arguments: ["-AletheUITestSeed", "clone"])
        XCTAssertTrue(element(app, "sidebar.project.repo").waitForExistence(timeout: 10))
        app.typeKey("n", modifierFlags: .command)
        let source = element(app, "editor.project.source")
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.radioButtons["Clone from GitHub"].click()

        let url = element(app, "editor.project.cloneURL")
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.click()
        paste(root.appending(path: "origin.git").path, into: app)
        let folder = element(app, "editor.project.folder")
        folder.click()
        paste(root.appending(path: "clones").path, into: app)

        let confirm = app.buttons["editor.confirm"]
        XCTAssertTrue(eventually { confirm.isEnabled })
        confirm.click()
        XCTAssertTrue(element(app, "sidebar.project.origin").waitForExistence(timeout: 20), "the clone is added as a project")
        app.terminate()
    }

    func testFolderWithoutRepositoryOffersInitializeGit() {
        let (app, root) = launchAlethe(arguments: ["-AletheUITestSeed", "clone"])
        XCTAssertTrue(element(app, "sidebar.project.repo").waitForExistence(timeout: 10))
        app.typeKey("n", modifierFlags: .command)
        let folder = element(app, "editor.project.folder")
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.click()
        paste(root.path, into: app)
        let initialize = element(app, "editor.project.initGit")
        XCTAssertTrue(initialize.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "editor.project.stack").exists)
        app.buttons["editor.cancel"].click()
        app.terminate()
    }
}
