import Foundation
import XCTest
@testable import BikeNative

private struct ResponseStep: Sendable {
    var path: String
    var method: String
    var status: Int
    var data: Data
    var beforeResponse: (@MainActor @Sendable () throws -> Void)?

    init(_ path: String, method: String = "GET", status: Int = 200, body: [String: Any], beforeResponse: (@MainActor @Sendable () throws -> Void)? = nil) throws {
        self.path = path
        self.method = method
        self.status = status
        self.data = try JSONSerialization.data(withJSONObject: body)
        self.beforeResponse = beforeResponse
    }
}

private final class ResponseQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [ResponseStep] = []
    func reset(_ steps: [ResponseStep]) { lock.withLock { self.steps = steps } }
    var isEmpty: Bool { lock.withLock { steps.isEmpty } }
    func take(_ request: URLRequest) throws -> ResponseStep {
        try lock.withLock {
            guard let step = steps.first, request.url?.path == step.path, request.httpMethod == step.method else {
                throw URLError(.badServerResponse)
            }
            steps.removeFirst()
            return step
        }
    }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let queue = ResponseQueue()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let step = try FixtureProtocol.queue.take(request)
            if let action = step.beforeResponse {
                if Thread.isMainThread {
                    try MainActor.assumeIsolated { try action() }
                } else {
                    try DispatchQueue.main.sync { try action() }
                }
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: step.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

@MainActor
private final class Fixture {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("BikeSyncTests-\(UUID().uuidString)")
    let suite = "BikeSyncTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let repository: WorkspaceRepository
    let session: URLSession
    let store: AppStore
    let config = SyncConfig(serverUrl: "http://fixture.invalid", token: "fixture", autoSync: false, autoSyncIntervalSeconds: 60)

    init(documents: [OutlineDocumentDTO]) throws {
        defaults = UserDefaults(suiteName: suite)!
        repository = try WorkspaceRepository(inMemory: true, baseURL: base)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        session = URLSession(configuration: configuration)
        store = AppStore(repository: repository, syncSession: session, syncDefaults: defaults)
        store.syncConfig = config
        store.syncState = .empty(serverUrl: config.serverUrl)
        store.workspace = WorkspaceV1DTO(activeDocumentId: documents[0].id, documents: documents)
        store.loadState = .loaded
        FixtureProtocol.queue.reset([])
    }

    var service: SyncService { SyncService(config: config, session: session) }
    var savedState: SyncState { SyncPreferences.loadState(serverUrl: config.serverUrl, defaults: defaults) }
    func cleanup() {
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: base)
    }
}

@MainActor
final class SyncSafetyTests: XCTestCase {
    private func document(_ id: String, title: String? = nil) -> OutlineDocumentDTO {
        OutlineDocumentDTO(id: id, title: title ?? id, createdAt: "2026-09-01T00:00:00.000Z", updatedAt: "2026-09-01T00:00:00.000Z", nodes: [OutlineNodeDTO(id: id + "-node", text: id)])
    }

    private func manifest(_ documents: [OutlineDocumentDTO], revision: Int = 1) -> [String: Any] {
        ["workspaceRevision": 1, "activeDocumentId": documents.first?.id ?? "", "documentOrder": documents.map(\.id), "documents": documents.map {
            ["id": $0.id, "title": $0.title, "revision": revision, "updatedAt": $0.updatedAt, "deletedAt": NSNull()] as [String: Any]
        }]
    }

    private func response(_ document: OutlineDocumentDTO, revision: Int = 1) throws -> [String: Any] {
        ["revision": revision, "document": try JSONSerialization.jsonObject(with: ImportExportCodec.jsonEncoder.encode(document))]
    }

    func testFailedMergeKeepsOnlyCompletedUploadsAndRetryDoesNotDeleteDownloads() async throws {
        let a = document("A"), b = document("B"), c = document("C")
        let f = try Fixture(documents: [b, c]); defer { f.cleanup() }
        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([a])),
            ResponseStep("/api/documents/A", body: response(a)),
            ResponseStep("/api/documents/B", method: "PUT", body: response(b)),
            ResponseStep("/api/documents/C", method: "PUT", status: 503, body: ["message": "injected failure"]),
        ])
        let original = f.store.workspace
        await f.store.runSync(.merge)
        XCTAssertEqual(f.store.workspace, original)
        XCTAssertNil(f.savedState.documentRevisions["A"])
        XCTAssertEqual(f.savedState.documentRevisions["B"], 1)
        XCTAssertFalse(f.store.isSyncing)
        XCTAssertTrue(FixtureProtocol.queue.isEmpty)

        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([a, b])),
            ResponseStep("/api/documents/A", body: response(a)),
            ResponseStep("/api/documents/C", method: "PUT", body: response(c)),
            ResponseStep("/api/sync/manifest", body: manifest([a, b, c])),
            ResponseStep("/api/sync/manifest", method: "PATCH", body: manifest([a, b, c])),
        ])
        await f.store.runSync(.merge)
        XCTAssertEqual(Set(f.store.workspace.documents.map(\.id)), ["A", "B", "C"])
        XCTAssertEqual(f.savedState.documentRevisions["A"], 1)
        XCTAssertTrue(FixtureProtocol.queue.isEmpty)
        XCTAssertTrue(try f.repository.loadWorkspace().documents.contains { $0.id == "A" })
    }

    func testDeleteCheckpointExcludesAnEarlierDownload() async throws {
        let a = document("A"), b = document("B"), c = document("C")
        let f = try Fixture(documents: [c]); defer { f.cleanup() }
        f.store.syncState.documentRevisions["B"] = 1
        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([a, b])),
            ResponseStep("/api/documents/A", body: response(a)),
            ResponseStep("/api/documents/B", method: "DELETE", body: ["id": "B", "revision": 2, "deletedAt": "2026-09-01T00:00:00.000Z"]),
            ResponseStep("/api/documents/C", method: "PUT", status: 503, body: ["message": "injected failure"]),
        ])
        await f.store.runSync(.merge)
        XCTAssertNil(f.savedState.documentRevisions["A"])
        XCTAssertEqual(f.savedState.deletedDocumentRevisions["B"], 2)
        XCTAssertTrue(FixtureProtocol.queue.isEmpty)
    }

    func testPartialPushRetainsCompletedUpload() async throws {
        let b = document("B"), c = document("C")
        let f = try Fixture(documents: [b, c]); defer { f.cleanup() }
        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([])),
            ResponseStep("/api/documents/B", method: "PUT", body: response(b)),
            ResponseStep("/api/documents/C", method: "PUT", status: 503, body: ["message": "injected failure"]),
        ])
        await f.store.runSync(.push)
        XCTAssertEqual(f.savedState.documentRevisions, ["B": 1])
        XCTAssertFalse(f.store.isSyncing)
    }

    func testPullSaveFailureKeepsPreviousWorkspaceAndBaseline() async throws {
        let local = document("local"), remote = document("remote", title: "Blocked")
        let f = try Fixture(documents: [local]); defer { f.cleanup() }
        f.store.syncState.documentRevisions["local"] = 7
        SyncPreferences.saveState(f.store.syncState, defaults: f.defaults)
        let previousState = f.savedState
        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([remote])),
            ResponseStep("/api/documents/remote", body: response(remote), beforeResponse: {
                try FileManager.default.createDirectory(at: f.base.appendingPathComponent("Blocked.md"), withIntermediateDirectories: true)
            }),
        ])
        await f.store.runSync(.pull)
        XCTAssertEqual(f.savedState, previousState)
        XCTAssertEqual(f.store.workspace.documents, [local])
        XCTAssertTrue(f.store.notice?.contains("同步失败") == true)
        XCTAssertFalse(f.store.isSyncing)
        XCTAssertFalse(try f.repository.listSnapshots().isEmpty)
    }

    func testEmptyPullDoesNotResetBaseline() async throws {
        let f = try Fixture(documents: [document("local")]); defer { f.cleanup() }
        f.store.syncState.documentRevisions["local"] = 4
        SyncPreferences.saveState(f.store.syncState, defaults: f.defaults)
        FixtureProtocol.queue.reset(try [ResponseStep("/api/sync/manifest", body: manifest([]))])
        await f.store.runSync(.pull)
        XCTAssertEqual(f.savedState.documentRevisions, ["local": 4])
        XCTAssertEqual(f.store.workspace.documents.count, 1)
    }

    func testPullRetainsWorkspaceChangedWhileWaiting() async throws {
        let local = document("local"), remote = document("remote")
        let f = try Fixture(documents: [local]); defer { f.cleanup() }
        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([remote])),
            ResponseStep("/api/documents/remote", body: response(remote), beforeResponse: {
                f.store.workspace.documents[0].title = "newer local change"
            }),
        ])
        await f.store.runSync(.pull)
        XCTAssertEqual(f.store.workspace.documents[0].title, "newer local change")
        XCTAssertTrue(f.savedState.documentRevisions.isEmpty)
    }

    func testSuccessfulPullPersistsWorkspaceBeforeRevision() async throws {
        let remote = document("remote")
        let f = try Fixture(documents: [document("local")]); defer { f.cleanup() }
        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([remote])),
            ResponseStep("/api/documents/remote", body: response(remote)),
        ])
        await f.store.runSync(.pull)
        XCTAssertEqual(f.savedState.documentRevisions["remote"], 1)
        XCTAssertEqual(try f.repository.loadWorkspace().documents[0].id, "remote")
    }

    func testMergeRetainsLateChangesAndOnlyAcknowledgesItsUpload() async throws {
        let a = document("A"), b = document("B")
        let f = try Fixture(documents: [b]); defer { f.cleanup() }
        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([a])),
            ResponseStep("/api/documents/A", body: response(a), beforeResponse: {
                f.store.workspace.documents[0].title = "late local edit"
            }),
            ResponseStep("/api/documents/B", method: "PUT", body: response(b)),
            ResponseStep("/api/sync/manifest", body: manifest([a, b])),
            ResponseStep("/api/sync/manifest", method: "PATCH", body: manifest([a, b])),
        ])
        await f.store.runSync(.merge)
        XCTAssertEqual(f.store.workspace.documents.count, 1)
        XCTAssertEqual(f.store.workspace.documents[0].title, "late local edit")
        XCTAssertEqual(f.savedState.documentRevisions, ["B": 1])
        XCTAssertTrue(FixtureProtocol.queue.isEmpty)
    }

    func testInitialSaveFailureDoesNotStartRemoteRequests() async throws {
        let f = try Fixture(documents: [document("Blocked")]); defer { f.cleanup() }
        try FileManager.default.createDirectory(at: f.base.appendingPathComponent("Blocked.md"), withIntermediateDirectories: true)
        FixtureProtocol.queue.reset(try [ResponseStep("/api/sync/manifest", body: manifest([]))])
        await f.store.runSync(.merge)
        XCTAssertFalse(FixtureProtocol.queue.isEmpty)
        XCTAssertTrue(f.savedState.documentRevisions.isEmpty)
        XCTAssertFalse(f.store.isSyncing)
        XCTAssertTrue(f.store.notice?.contains("同步失败") == true)
    }

    func testShortcutAndExtensionsSurviveMarkdownReloadAndSyncUpload() async throws {
        var doc = document("A")
        doc.isShortcut = true
        doc.additionalFields = ["extension": .object(["large": .number(Decimal(string: "9007199254740993")!), "null": .null])]
        doc.nodes[0].additionalFields = ["extension": .array([.string("keep"), .bool(true)])]
        let encoded = try ImportExportCodec.jsonEncoder.encode(doc)
        let decoded = try ImportExportCodec.jsonDecoder.decode(OutlineDocumentDTO.self, from: encoded)
        XCTAssertEqual(decoded, doc)
        let f = try Fixture(documents: [decoded]); defer { f.cleanup() }
        f.store.workspace.additionalFields = ["extension": .string("workspace")]
        try f.repository.saveWorkspace(f.store.workspace)
        var loaded = try f.repository.loadWorkspace()
        XCTAssertEqual(loaded.additionalFields, f.store.workspace.additionalFields)
        XCTAssertEqual(loaded.documents[0].isShortcut, true)
        XCTAssertEqual(loaded.documents[0].additionalFields, doc.additionalFields)
        XCTAssertEqual(loaded.documents[0].nodes[0].additionalFields, doc.nodes[0].additionalFields)
        loaded.documents[0].title = "Desktop edit"
        loaded.documents[0].markdownSource = nil
        FixtureProtocol.queue.reset(try [
            ResponseStep("/api/sync/manifest", body: manifest([])),
            ResponseStep("/api/documents/A", method: "PUT", body: response(loaded.documents[0])),
            ResponseStep("/api/sync/manifest", body: manifest(loaded.documents)),
            ResponseStep("/api/sync/manifest", method: "PATCH", body: manifest(loaded.documents)),
        ])
        let result = try await f.service.syncWorkspace(loaded, previousState: .empty(serverUrl: f.config.serverUrl))
        XCTAssertEqual(result.workspace.additionalFields, loaded.additionalFields)
        XCTAssertEqual(result.workspace.documents[0].isShortcut, true)
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: ImportExportCodec.jsonEncoder.encode(result.workspace.documents[0])) as? [String: Any])
        XCTAssertEqual(output["isShortcut"] as? Bool, true)
        XCTAssertNotNil(output["extension"])
        XCTAssertNil(output["additionalFields"])
    }

    func testDuplicateMarkdownDocumentUsesNewTitle() throws {
        let f = try Fixture(documents: [document("A")]); defer { f.cleanup() }
        f.store.workspace.documents[0].markdownSource = "# A\n\n- A"
        f.store.workspace.documents[0].markdownUpdatedAt = f.store.workspace.documents[0].updatedAt
        f.store.duplicateDocument()
        XCTAssertNil(f.store.activeDocument?.markdownSource)
        XCTAssertNil(f.store.activeDocument?.markdownUpdatedAt)
        XCTAssertTrue(MarkdownCodec.documentMarkdown(f.store.activeDocument!).contains("A 副本"))
        f.store.flushSaveNow()
    }
}
