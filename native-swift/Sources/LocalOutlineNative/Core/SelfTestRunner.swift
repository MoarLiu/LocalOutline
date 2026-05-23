import Foundation

enum SelfTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

enum SelfTestRunner {
    @MainActor
    static func run() throws {
        try workspaceNormalizationRepairsEmptyWorkspace()
        try treeOperationsInsertIndentOutdent()
        try markdownRoundTripPreservesTitleAndTasks()
        try jsonWorkspaceCompatibility()
        try tagAndLinkExtraction()
        try documentUndoWorksAcrossOutlineMindMapAndMarkdown()
        try repositorySavesSnapshotsAndRestores()
        try iCloudBackupWritesLatestAndStampedFiles()
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SelfTestError.failed(message) }
    }

    private static func workspaceNormalizationRepairsEmptyWorkspace() throws {
        let workspace = TreeOperations.normalizeWorkspace(WorkspaceV1DTO(activeDocumentId: "missing", documents: []))
        try expect(workspace.version == 1, "workspace version should be 1")
        try expect(workspace.documents.count == 1, "empty workspace should get starter document")
        try expect(workspace.activeDocumentId == workspace.documents[0].id, "active document should be repaired")
        try expect(!workspace.documents[0].nodes.isEmpty, "document should contain at least one node")
    }

    private static func treeOperationsInsertIndentOutdent() throws {
        let a = OutlineNodeDTO(id: "a", text: "A")
        let b = OutlineNodeDTO(id: "b", text: "B")
        var nodes = [a, b]
        nodes = TreeOperations.indentNode(nodes, targetId: "b")
        try expect(nodes.count == 1, "indent should move node into previous sibling")
        try expect(nodes[0].children.first?.id == "b", "indented child should be b")
        nodes = TreeOperations.outdentNode(nodes, targetId: "b")
        try expect(nodes.map(\.id) == ["a", "b"], "outdent should restore sibling order")
    }

    private static func markdownRoundTripPreservesTitleAndTasks() throws {
        let markdown = """
        # Plan

        - [x] Done
          > Note
        - Next
        """
        let document = MarkdownCodec.parseDocument(markdown)
        try expect(document.title == "Plan", "markdown title should parse")
        try expect(document.nodes.first?.checked == true, "task checked state should parse")
        try expect(document.nodes.first?.note == "Note", "quote should attach as note")
        try expect(MarkdownCodec.documentMarkdown(document).contains("# Plan"), "markdown export should keep title")
    }

    private static func jsonWorkspaceCompatibility() throws {
        let workspace = SampleData.starterWorkspace()
        let data = try ImportExportCodec.exportWorkspace(workspace)
        let decoded = try ImportExportCodec.jsonDecoder.decode(WorkspaceV1DTO.self, from: data)
        try expect(decoded.version == 1, "workspace json version should be 1")
        try expect(decoded.documents.first?.title == "本地化大纲产品蓝图", "starter title should round trip")
    }

    private static func tagAndLinkExtraction() throws {
        try expect(TreeOperations.extractTags("hello #项目 #local-first") == ["项目", "local-first"], "tag extraction failed")
        try expect(TreeOperations.extractLinks("见 [[文档名]] 和 [[A#B]]") == ["文档名", "A#B"], "link extraction failed")
    }

    @MainActor
    private static func documentUndoWorksAcrossOutlineMindMapAndMarkdown() throws {
        let repository = try WorkspaceRepository(inMemory: true)
        let store = AppStore(repository: repository)
        let node = OutlineNodeDTO(id: "undo-node", text: "Undo me")
        let document = OutlineDocumentDTO(id: "undo-doc", title: "Undo", nodes: [node])
        store.workspace = WorkspaceV1DTO(activeDocumentId: document.id, documents: [document])
        store.mode = .outline
        store.activeNodeId = node.id
        let initialWorkspace = store.workspace

        store.toggleStrike(node.id)
        try expect(store.activeNode?.strike == true, "strike toggle should mark node")
        store.insertChild(node.id)
        try expect(store.activeNode?.id != node.id, "insert child should select new node")
        store.undoLastDocumentChange()
        try expect(store.activeDocument?.nodes.first?.strike == true, "first undo should restore previous outline operation")
        store.undoLastDocumentChange()
        try expect(store.workspace == initialWorkspace, "second undo should return to startup workspace")

        store.removeNode(node.id)
        try expect(TreeOperations.findNode(in: store.activeDocument?.nodes ?? [], id: node.id) == nil, "remove should delete target node")
        store.undoLastDocumentChange()
        try expect(store.activeDocument?.nodes.first?.id == node.id, "undo should restore deleted node")

        store.mode = .mindmap
        store.insertMindMapRootChild()
        try expect((store.activeDocument?.nodes.count ?? 0) == 2, "mind map root insert should add node")
        store.undoLastDocumentChange()
        try expect((store.activeDocument?.nodes.count ?? 0) == 1, "undo should restore mind map change")

        let beforeMarkdown = store.workspace
        store.mode = .markdown
        store.setMarkdownSource("# Changed\n\n- Markdown node", coalescingKey: "markdown:undo-doc")
        try expect(store.activeDocument?.title == "Changed", "markdown edit should change title")
        store.undoLastDocumentChange()
        try expect(store.workspace == beforeMarkdown, "undo should restore markdown change")

        store.toggleStrike(node.id)
        try expect(store.activeNode?.strike == true, "strike toggle should mark node after cross-mode undos")
        store.undoLastDocumentChange()
        try expect(store.activeNode?.strike != true, "undo should restore strike state")
    }

    @MainActor
    private static func repositorySavesSnapshotsAndRestores() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalOutlineSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let repository = try WorkspaceRepository(inMemory: true, baseURL: base)
        var workspace = SampleData.starterWorkspace()
        workspace.documents[0].title = "Snapshot source"
        try repository.saveWorkspace(workspace)
        try repository.createSnapshot(reason: "manual", workspace: workspace)

        workspace.documents[0].title = "Changed"
        try repository.saveWorkspace(workspace)

        let snapshots = try repository.listSnapshots()
        try expect(!snapshots.isEmpty, "snapshot list should not be empty")
        let restored = try repository.restoreSnapshot(snapshots[0], currentWorkspace: workspace)
        try expect(restored.documents[0].title == "Snapshot source", "snapshot restore should recover saved title")
        let restoredSnapshots = try repository.listSnapshots()
        try expect(restoredSnapshots.contains { $0.reason.hasPrefix("before-restore") }, "restore should create before-restore snapshot")
    }

    private static func iCloudBackupWritesLatestAndStampedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalOutlineBackupSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspace = SampleData.starterWorkspace()
        let result = ICloudBackupService.save(workspace: workspace, directory: directory)
        try expect(result.ok, "backup save should succeed")
        try expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(ICloudBackupService.latestBackupFilename).path), "latest backup should exist")
        let backups = try ICloudBackupService.listBackups(directory: directory)
        try expect(backups.count == 2, "latest and stamped backup should be listed")
        let loaded = try ICloudBackupService.load(directory: directory).get().0
        try expect(loaded == workspace, "loaded backup should match saved workspace")
    }
}
