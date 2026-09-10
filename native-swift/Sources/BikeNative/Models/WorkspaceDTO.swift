import Foundation

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case outline
    case mindmap
    case presentation
    case markdown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .outline: "大纲"
        case .mindmap: "脑图"
        case .presentation: "演示"
        case .markdown: "Markdown"
        }
    }

    var systemImage: String {
        switch self {
        case .outline: "list.bullet.indent"
        case .mindmap: "brain.head.profile"
        case .presentation: "rectangle.on.rectangle"
        case .markdown: "doc.plaintext"
        }
    }
}

enum MarkdownPaneMode: String, Codable, CaseIterable, Identifiable {
    case edit
    case preview
    case split

    var id: String { rawValue }
    var title: String {
        switch self {
        case .edit: "编辑"
        case .preview: "预览"
        case .split: "分栏"
        }
    }
}

enum OutlineColor: String, Codable, CaseIterable, Identifiable {
    case plain
    case blue
    case green
    case amber
    case rose

    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain: "默认"
        case .blue: "蓝"
        case .green: "绿"
        case .amber: "黄"
        case .rose: "红"
        }
    }

    static func normalize(_ value: String?) -> String {
        guard let value, Self(rawValue: value) != nil else { return Self.plain.rawValue }
        return value
    }
}

struct WorkspaceV1DTO: Codable, Equatable, Sendable {
    var version: Int
    var activeDocumentId: String
    var documents: [OutlineDocumentDTO]
    var additionalFields: [String: JSONValue]

    init(version: Int = 1, activeDocumentId: String, documents: [OutlineDocumentDTO], additionalFields: [String: JSONValue] = [:]) {
        self.version = version
        self.activeDocumentId = activeDocumentId
        self.documents = documents
        self.additionalFields = additionalFields
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, activeDocumentId, documents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        activeDocumentId = try container.decode(String.self, forKey: .activeDocumentId)
        documents = try container.decode([OutlineDocumentDTO].self, forKey: .documents)
        additionalFields = try decoder.additionalFields(excluding: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(activeDocumentId, forKey: .activeDocumentId)
        try container.encode(documents, forKey: .documents)
        try encoder.encodeAdditionalFields(additionalFields, excluding: CodingKeys.self)
    }
}

struct OutlineDocumentDTO: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var createdAt: String
    var updatedAt: String
    var markdownSource: String?
    var markdownUpdatedAt: String?
    var nodes: [OutlineNodeDTO]
    var isShortcut: Bool?
    var additionalFields: [String: JSONValue]

    init(
        id: String = UUID().uuidString,
        title: String = Defaults.documentTitle,
        createdAt: String = Date.isoNow,
        updatedAt: String = Date.isoNow,
        markdownSource: String? = nil,
        markdownUpdatedAt: String? = nil,
        nodes: [OutlineNodeDTO] = [OutlineNodeDTO(text: Defaults.nodeText)],
        isShortcut: Bool? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.markdownSource = markdownSource
        self.markdownUpdatedAt = markdownUpdatedAt
        self.nodes = nodes
        self.isShortcut = isShortcut
        self.additionalFields = additionalFields
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, createdAt, updatedAt, markdownSource, markdownUpdatedAt, nodes, isShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        markdownSource = try container.decodeIfPresent(String.self, forKey: .markdownSource)
        markdownUpdatedAt = try container.decodeIfPresent(String.self, forKey: .markdownUpdatedAt)
        nodes = try container.decode([OutlineNodeDTO].self, forKey: .nodes)
        isShortcut = try container.decodeIfPresent(Bool.self, forKey: .isShortcut)
        additionalFields = try decoder.additionalFields(excluding: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(markdownSource, forKey: .markdownSource)
        try container.encodeIfPresent(markdownUpdatedAt, forKey: .markdownUpdatedAt)
        try container.encode(nodes, forKey: .nodes)
        try container.encodeIfPresent(isShortcut, forKey: .isShortcut)
        try encoder.encodeAdditionalFields(additionalFields, excluding: CodingKeys.self)
    }
}

struct OutlineNodeDTO: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var note: String
    var checked: Bool
    var collapsed: Bool
    var color: String
    var headingLevel: Int?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strike: Bool?
    var highlight: Bool?
    var icon: String?
    var imageName: String?
    var imageAlt: String?
    var table: [[String]]?
    var codeBlock: String?
    var codeLanguage: String?
    var isTodo: Bool?
    var children: [OutlineNodeDTO]
    var additionalFields: [String: JSONValue]

    init(
        id: String = "node_\(UUID().uuidString)",
        text: String = "",
        note: String = "",
        checked: Bool = false,
        collapsed: Bool = false,
        color: String = OutlineColor.plain.rawValue,
        headingLevel: Int? = 0,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strike: Bool? = nil,
        highlight: Bool? = nil,
        icon: String? = nil,
        imageName: String? = nil,
        imageAlt: String? = nil,
        table: [[String]]? = nil,
        codeBlock: String? = nil,
        codeLanguage: String? = nil,
        isTodo: Bool? = nil,
        children: [OutlineNodeDTO] = [],
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.text = text
        self.note = note
        self.checked = checked
        self.collapsed = collapsed
        self.color = OutlineColor.normalize(color)
        self.headingLevel = headingLevel
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strike = strike
        self.highlight = highlight
        self.icon = icon
        self.imageName = imageName
        self.imageAlt = imageAlt
        self.table = table
        self.codeBlock = Self.normalizeCodeBlock(codeBlock)
        self.codeLanguage = Self.normalizeCodeLanguage(codeLanguage)
        self.isTodo = isTodo
        self.children = children
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, text, note, checked, collapsed, color, headingLevel
        case bold, italic, underline, strike, highlight, icon, imageName, imageAlt, table, codeBlock, codeLanguage, isTodo, children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "node_\(UUID().uuidString)"
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? Defaults.nodeText
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        color = OutlineColor.normalize(try container.decodeIfPresent(String.self, forKey: .color))
        let rawHeading = try container.decodeIfPresent(Int.self, forKey: .headingLevel) ?? 0
        headingLevel = [0, 1, 2, 3].contains(rawHeading) ? rawHeading : 0
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold)
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic)
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline)
        strike = try container.decodeIfPresent(Bool.self, forKey: .strike)
        highlight = try container.decodeIfPresent(Bool.self, forKey: .highlight)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        imageAlt = try container.decodeIfPresent(String.self, forKey: .imageAlt)
        table = try container.decodeIfPresent([[String]].self, forKey: .table)
        codeBlock = Self.normalizeCodeBlock(try container.decodeIfPresent(String.self, forKey: .codeBlock))
        codeLanguage = Self.normalizeCodeLanguage(try container.decodeIfPresent(String.self, forKey: .codeLanguage))
        isTodo = try container.decodeIfPresent(Bool.self, forKey: .isTodo)
        children = try container.decodeIfPresent([OutlineNodeDTO].self, forKey: .children) ?? []
        additionalFields = try decoder.additionalFields(excluding: CodingKeys.self)
    }


    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(note, forKey: .note)
        try container.encode(checked, forKey: .checked)
        try container.encode(collapsed, forKey: .collapsed)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(headingLevel, forKey: .headingLevel)
        try container.encodeIfPresent(bold, forKey: .bold)
        try container.encodeIfPresent(italic, forKey: .italic)
        try container.encodeIfPresent(underline, forKey: .underline)
        try container.encodeIfPresent(strike, forKey: .strike)
        try container.encodeIfPresent(highlight, forKey: .highlight)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(imageName, forKey: .imageName)
        try container.encodeIfPresent(imageAlt, forKey: .imageAlt)
        try container.encodeIfPresent(table, forKey: .table)
        try container.encodeIfPresent(codeBlock, forKey: .codeBlock)
        try container.encodeIfPresent(codeLanguage, forKey: .codeLanguage)
        try container.encodeIfPresent(isTodo, forKey: .isTodo)
        try container.encode(children, forKey: .children)
        try encoder.encodeAdditionalFields(additionalFields, excluding: CodingKeys.self)
    }

    private static func normalizeCodeBlock(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func normalizeCodeLanguage(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(80))
    }
}

struct FlatNode: Identifiable, Equatable {
    var id: String { node.id }
    var node: OutlineNodeDTO
    var depth: Int
    var parentId: String?
    var path: [Int]
}

enum Defaults {
    static let documentTitle = "未命名文档"
    static let nodeText = "未命名主题"
}

extension Date {
    static var isoNow: String {
        ISO8601DateFormatter.bike.string(from: Date())
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let bike: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
