//
//  CountriesXLUITests.swift
//  CountriesXLUITests
//
//  Created by Tyler Austin on 9/29/25.
//

import XCTest

final class CountriesXLUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testDownloadsSheetShowsPreparingSeededItem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-seed-preparing-download"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UITest Resource"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preparing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preparing download link…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDownloadsSheetShowsQueuedSeededItem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-seed-queued-download"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UITest Queued Resource"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ready to save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save As"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDownloadsSheetShowsCompletedSeededItemActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-seed-completed-download"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UITest Completed Resource"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Run"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save As"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete File"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testResourceOverviewDownloadButtonQueuesResourceInDownloadsSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-resource-overview-download"]
        app.launch()

        let downloadButton = app.buttons["resource-overview-download-button"]
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 20))
        downloadButton.tap()

        XCTAssertTrue(app.staticTexts["Downloads"].waitForExistence(timeout: 10))
        let downloadsSheet = app.sheets.firstMatch
        XCTAssertTrue(downloadsSheet.waitForExistence(timeout: 10))
        XCTAssertTrue(downloadsSheet.staticTexts["Ready to save"].waitForExistence(timeout: 15))
        XCTAssertTrue(downloadsSheet.staticTexts["Lake City - Small Firehall"].waitForExistence(timeout: 10))
        XCTAssertTrue(downloadsSheet.buttons["download-save-328"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        let app = XCUIApplication()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            if app.state == .runningForeground {
                app.terminate()
            }
            app.launch()
        }
    }
}
