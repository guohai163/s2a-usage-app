import Foundation

// MARK: - 动态菜单 DSL 模型

/// JSON DSL 的根对象，描述菜单栏状态项、弹层、展示数据和可触发动作。
struct MenuRenderSpec: Codable {
    var schema: String
    var statusItem: StatusItemSpec
    var panel: PanelSpec
    var data: JSONValue
    var actions: [String: ActionSpec]
}

struct StatusItemSpec: Codable {
    var icon: StatusIconSpec?
    var title: StatusTitleSpec?
    var tooltip: String?
}

struct StatusIconSpec: Codable {
    var type: String
    var name: String
}

struct StatusTitleSpec: Codable {
    var text: String
    var font: String?
}

struct PanelSpec: Codable {
    var size: PanelSizeSpec
    var chrome: PanelChromeSpec?
    var padding: PanelPaddingSpec?
    var root: RenderNode
}

struct PanelSizeSpec: Codable {
    var mode: String
    var width: Double?
    var height: Double?
    var minWidth: Double?
    var minHeight: Double?
    var maxWidth: Double?
    var maxHeight: Double?
}

struct PanelChromeSpec: Codable {
    var type: String
    var cornerRadius: Double?
}

struct PanelPaddingSpec: Codable {
    var top: Double?
    var horizontal: Double?
    var bottom: Double?
}

/// 允许 JSON 描述的受控组件集合。
indirect enum RenderNode: Codable {
    case stack(StackNode)
    case text(TextNode)
    case button(ButtonNode)
    case separator
    case meter(MeterNode)
    case list(ListNode)
    case footerBar(FooterBarNode)
    case forEach(ForEachNode)
    case unsupported(String)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "vstack", "hstack":
            self = .stack(try StackNode(from: decoder, type: type))
        case "text":
            self = .text(try TextNode(from: decoder))
        case "button":
            self = .button(try ButtonNode(from: decoder))
        case "separator":
            self = .separator
        case "meter":
            self = .meter(try MeterNode(from: decoder))
        case "list":
            self = .list(try ListNode(from: decoder))
        case "footerBar":
            self = .footerBar(try FooterBarNode(from: decoder))
        case "forEach":
            self = .forEach(try ForEachNode(from: decoder))
        default:
            self = .unsupported(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .stack(let node):
            try node.encode(to: encoder)
        case .text(let node):
            try node.encode(to: encoder)
        case .button(let node):
            try node.encode(to: encoder)
        case .separator:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("separator", forKey: .type)
        case .meter(let node):
            try node.encode(to: encoder)
        case .list(let node):
            try node.encode(to: encoder)
        case .footerBar(let node):
            try node.encode(to: encoder)
        case .forEach(let node):
            try node.encode(to: encoder)
        case .unsupported(let type):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
        }
    }
}

struct StackNode: Codable {
    var type: String
    var spacing: Double?
    var distribution: String?
    var alignment: String?
    var children: [RenderNode]

    private enum CodingKeys: String, CodingKey {
        case type
        case spacing
        case distribution
        case alignment
        case children
    }

    init(from decoder: Decoder, type: String) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = type
        spacing = try container.decodeIfPresent(Double.self, forKey: .spacing)
        distribution = try container.decodeIfPresent(String.self, forKey: .distribution)
        alignment = try container.decodeIfPresent(String.self, forKey: .alignment)
        children = try container.decodeIfPresent([RenderNode].self, forKey: .children) ?? []
    }
}

struct TextNode: Codable {
    var type = "text"
    var text: String
    var style: String?
    var visible: JSONValue?
    var selectable: Bool?
}

struct ButtonNode: Codable {
    var type = "button"
    var icon: String
    var tooltip: String?
    var action: String
    var enabled: JSONValue?
}

struct MeterNode: Codable {
    var type = "meter"
    var title: String
    var icon: String
    var progress: JSONValue
    var percent: String
    var amount: String
    var color: String?
}

struct ListNode: Codable {
    var type = "list"
    var items: String
    var limit: Int?
    var style: String?
}

struct FooterBarNode: Codable {
    var type = "footerBar"
    var height: Double?
    var left: FooterTextSpec
    var right: FooterTextSpec
}

struct FooterTextSpec: Codable {
    var text: String
    var style: String?
}

struct ForEachNode: Codable {
    var type = "forEach"
    var items: String
    var template: RenderNode
}

struct ActionSpec: Codable {
    var type: String
    var value: String?
    var feedback: String?
    var url: String?
    var page: String?
    var params: [String: JSONValue]?
}

/// 小型 JSON 值类型，用于承载 DSL 中的动态数据。
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    static func array(_ values: [[String: JSONValue]]) -> JSONValue {
        .array(values.map { .object($0) })
    }

    init(_ value: String) {
        self = .string(value)
    }

    init(_ value: Double) {
        self = .number(value)
    }

    init(_ value: Int) {
        self = .number(Double(value))
    }

    init(_ value: Bool) {
        self = .bool(value)
    }

    var displayString: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object, .array:
            return ""
        case .null:
            return ""
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "1"].contains(normalized) {
                return true
            }
            if ["false", "no", "0"].contains(normalized) {
                return false
            }
            return nil
        case .number(let value):
            return value != 0
        case .object, .array, .null:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        case .bool(let value):
            return value ? 1 : 0
        case .object, .array, .null:
            return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let values) = self {
            return values
        }
        return nil
    }
}
