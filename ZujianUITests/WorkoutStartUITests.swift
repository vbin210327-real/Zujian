import XCTest

final class WorkoutStartUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStartWorkoutAlwaysShowsOutcome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let startButton = app.buttons["开始训练"]
        scrollToElement(startButton, in: app)
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), app.debugDescription)
        startButton.tap()

        let continueButton = app.buttons["继续"]
        if continueButton.waitForExistence(timeout: 2) {
            continueButton.tap()
        }

        let watchSystem = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        if watchSystem.wait(for: .runningForeground, timeout: 3) {
            completeHealthAuthorization(in: watchSystem)
        }

        let waitingText = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "等待第")
        ).firstMatch
        let issueText = app.staticTexts["训练还没开始"]
        let healthAccessTitle = app.staticTexts["开始前，确认健康权限"]

        let outcomeAppeared = waitingText.waitForExistence(timeout: 12)
            || issueText.waitForExistence(timeout: 1)
            || healthAccessTitle.waitForExistence(timeout: 1)
        XCTAssertTrue(
            outcomeAppeared,
            "点击开始后既没有进入等待状态，也没有显示错误。\n\(app.debugDescription)"
        )

        if waitingText.exists {
            let manualRestButton = app.buttons["手动开始休息"]
            XCTAssertFalse(manualRestButton.exists)
            XCTAssertFalse(app.staticTexts["开始动作即可"].exists)
            let waitingStatus = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "等待动作"))
                .firstMatch
            XCTAssertTrue(waitingStatus.exists)
        }
    }

    func testPausedScreenUsesMascotAndSingleStatusLabel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-paused"]
        app.launch()

        let pausedStatus = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "已暂停"))
            .firstMatch
        XCTAssertTrue(pausedStatus.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["训练已暂停"].exists)
        XCTAssertTrue(app.buttons["继续"].exists)
        XCTAssertTrue(app.buttons["结束训练"].exists)

        let pausedScreenshot = XCTAttachment(screenshot: app.screenshot())
        pausedScreenshot.name = "Paused phase with mascot"
        pausedScreenshot.lifetime = .keepAlways
        add(pausedScreenshot)
    }

    func testDiagnosticCaptureCanMarkAndSaveAMissedSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-waiting"]
        app.launch()

        let beginButton = app.buttons["记录下一组"]
        XCTAssertTrue(beginButton.waitForExistence(timeout: 3), app.debugDescription)
        beginButton.tap()

        let missedButton = app.buttons["这组未识别"]
        XCTAssertTrue(missedButton.waitForExistence(timeout: 2), app.debugDescription)
        missedButton.tap()

        let savedMessage = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "已保存：失败组")
        ).firstMatch
        XCTAssertTrue(savedMessage.waitForExistence(timeout: 5), app.debugDescription)
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.exists {
            app.swipeUp()
        }
    }

    private func completeHealthAuthorization(in system: XCUIApplication) {
        // Carousel is the watchOS shell and can report itself foreground even
        // when no permission sheet is visible. No Review button means this is
        // the already-authorized path, so there is nothing to complete.
        guard tapControl(named: "检查", in: system, waiting: 3) else { return }

        for _ in 0..<10 {
            sleep(1)

            let firstSwitch = system.switches.firstMatch
            if firstSwitch.exists, (firstSwitch.value as? String) != "1" {
                firstSwitch.tap()
            }

            if tapControl(named: "下一步", in: system) {
                continue
            }

            if tapControl(named: "允许", in: system)
                || tapControl(named: "完成", in: system) {
                return
            }

            system.swipeUp()

            // Health's watch authorization sheet exposes its footer action as
            // a Cell rather than a Button. Query every element type after the
            // scroll so this test follows the same path a person sees.
            if tapControl(named: "下一步", in: system) {
                continue
            }

            if tapControl(named: "允许", in: system)
                || tapControl(named: "完成", in: system) {
                return
            }
        }

        XCTFail("未能完成系统健康授权。\n\(system.debugDescription)")
    }

    @discardableResult
    private func tapControl(
        named label: String,
        in application: XCUIApplication,
        waiting timeout: TimeInterval = 0
    ) -> Bool {
        let exactLabel = NSPredicate(format: "label == %@", label)
        let element = application.descendants(matching: .any)
            .matching(exactLabel)
            .firstMatch

        let exists = timeout > 0
            ? element.waitForExistence(timeout: timeout)
            : element.exists
        guard exists else { return false }

        element.tap()
        return true
    }
}
