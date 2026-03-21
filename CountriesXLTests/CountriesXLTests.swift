//
//  CountriesXLTests.swift
//  CountriesXLTests
//
//  Created by Tyler Austin on 9/29/25.
//

import Testing
import Foundation
@testable import CountriesXL

struct CountriesXLTests {

    @MainActor
    @Test func prepareCreatesImmediatePlaceholder() async throws {
        let manager = DownloadManagerV2.shared
        manager.resetForTesting()

        let id = 1001
        manager.prepareDownload(id: id, title: "Test Resource")

        #expect(manager.knownDownloadIDs.contains(id))
        #expect(manager.isPreparing(id: id))
        #expect(manager.statusText(for: id) == "Preparing")
        #expect(manager.canStartQueuedDownload(id: id) == false)
    }

    @MainActor
    @Test func configureAfterCancelDoesNotRecreateDownload() async throws {
        let manager = DownloadManagerV2.shared
        manager.resetForTesting()

        let id = 1002
        manager.prepareDownload(id: id, title: "Cancelled Resource")
        manager.cancelDownload(id: id)

        var request = URLRequest(url: URL(string: "https://example.com/cancelled.zip")!)
        request.httpMethod = "GET"
        manager.configurePreparedDownload(id: id, request: request, displayURL: request.url)

        #expect(manager.knownDownloadIDs.contains(id) == false)
        #expect(manager.isPreparing(id: id) == false)
        #expect(manager.canStartQueuedDownload(id: id) == false)
    }

    @MainActor
    @Test func repeatedPrepareReusesSingleEntry() async throws {
        let manager = DownloadManagerV2.shared
        manager.resetForTesting()

        let id = 1003
        manager.prepareDownload(id: id, title: "Repeated Resource")
        manager.prepareDownload(id: id, title: "Repeated Resource")

        let matches = manager.knownDownloadIDs.filter { $0 == id }
        #expect(matches.count == 1)
        #expect(manager.isPreparing(id: id))
    }

    @MainActor
    @Test func configureTransitionsPreparingToQueued() async throws {
        let manager = DownloadManagerV2.shared
        manager.resetForTesting()

        let id = 1004
        manager.prepareDownload(id: id, title: "Queued Resource")

        var request = URLRequest(url: URL(string: "https://example.com/queued.zip")!)
        request.httpMethod = "GET"
        manager.configurePreparedDownload(id: id, request: request, displayURL: request.url)

        #expect(manager.isPreparing(id: id) == false)
        #expect(manager.isQueued(id: id))
        #expect(manager.canStartQueuedDownload(id: id))
        #expect(manager.statusText(for: id) == "Ready to save")
    }

}
