import BikeCore
import Foundation

private struct SyncFixtureStep: Sendable {
    let path: String
    let method: String
    let status: Int
    let body: Data

    init(_ path: String, method: String = "GET", status: Int = 200, payload: [String: Any]) throws {
        self.path = path
        self.method = method
        self.status = status
        self.body = try JSONSerialization.data(withJSONObject: payload)
    }
}

private final class SyncFixtureQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [SyncFixtureStep] = []

    func reset(_ steps: [SyncFixtureStep]) {
        lock.withLock { self.steps = steps }
    }

    func take(_ request: URLRequest) throws -> SyncFixtureStep {
        try lock.withLock {
            guard let next = steps.first,
                  next.path == request.url?.path,
                  next.method == request.httpMethod else {
                throw URLError(.badServerResponse)
            }
            steps.removeFirst()
            return next
        }
    }

    var isEmpty: Bool { lock.withLock { steps.isEmpty } }
}

private final class SyncFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let queue = SyncFixtureQueue()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let step = try Self.queue.take(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: step.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

private struct SyncCheckFailure: Error {}

@MainActor
private final class SyncCheckpointCapture {
    var states: [SyncState] = []
}

func checkSyncCheckpoints() async throws {
    let date = "2026-09-01T00:00:00.000Z"
    let a = OutlineDocument(id: "A", title: "Remote", createdAt: date, updatedAt: date, nodes: [OutlineNode(id: "a-node", text: "Remote")])
    let b = OutlineDocument(id: "B", title: "Local", createdAt: date, updatedAt: date, nodes: [OutlineNode(id: "b-node", text: "Local")])
    let c = OutlineDocument(id: "C", title: "Later", createdAt: date, updatedAt: date, nodes: [OutlineNode(id: "c-node", text: "Later")])
    let workspace = Workspace(activeDocumentId: b.id, documents: [b, c])
    let config = SyncConfig(serverUrl: "http://fixture.invalid", token: "fixture")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyncFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let service = SyncService(config: config, session: session)
    let capture = await MainActor.run { SyncCheckpointCapture() }

    func manifest(_ documents: [OutlineDocument]) -> [String: Any] {
        [
            "workspaceRevision": 3,
            "activeDocumentId": "A",
            "documentOrder": documents.map(\.id),
            "documents": documents.map { ["id": $0.id, "title": $0.title, "revision": 1, "updatedAt": date, "deletedAt": NSNull()] as [String: Any] }
        ]
    }
    func response(_ document: OutlineDocument) throws -> [String: Any] {
        ["revision": 1, "document": try JSONSerialization.jsonObject(with: WorkspaceJSON.encoder.encode(document))]
    }

    SyncFixtureProtocol.queue.reset(try [
        SyncFixtureStep("/api/sync/manifest", payload: manifest([a])),
        SyncFixtureStep("/api/documents/A", payload: response(a)),
        SyncFixtureStep("/api/documents/B", method: "PUT", payload: response(b)),
        SyncFixtureStep("/api/documents/C", method: "PUT", status: 503, payload: ["message": "injected failure"])
    ])
    do {
        _ = try await service.syncWorkspace(workspace, previousState: .empty(serverUrl: config.serverUrl)) { capture.states.append($0) }
        throw SyncCheckFailure()
    } catch SyncServiceError.requestFailed(let status, _, _) where status == 503 {
        // The first upload succeeded, but the downloaded workspace was never applied.
    }
    let checkpoints = await MainActor.run { capture.states }
    guard checkpoints.count == 1,
          let checkpoint = checkpoints.last,
          checkpoint.documentRevisions["A"] == nil,
          checkpoint.documentRevisions["B"] == 1 else { throw SyncCheckFailure() }

    SyncFixtureProtocol.queue.reset(try [
        SyncFixtureStep("/api/sync/manifest", payload: manifest([a, b])),
        SyncFixtureStep("/api/documents/A", payload: response(a)),
        SyncFixtureStep("/api/documents/C", method: "PUT", payload: response(c)),
        SyncFixtureStep("/api/sync/manifest", payload: manifest([a, b, c])),
        SyncFixtureStep("/api/sync/manifest", method: "PATCH", payload: manifest([a, b, c]))
    ])
    let retried = try await service.syncWorkspace(workspace, previousState: checkpoint)
    guard retried.workspace.documents.contains(where: { $0.id == "A" }),
          retried.summary.deleted == 0,
          retried.summary.conflicts.isEmpty,
          SyncFixtureProtocol.queue.isEmpty else { throw SyncCheckFailure() }
}
