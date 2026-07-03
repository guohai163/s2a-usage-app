import Foundation

// MARK: - 菜单 JSON 绑定解析

/// 解析 DSL 中的 `{{path.to.value}}` 绑定，支持根 data 和 forEach 里的 item。
struct MenuBindingResolver {
    let data: JSONValue
    let item: JSONValue?

    init(data: JSONValue, item: JSONValue? = nil) {
        self.data = data
        self.item = item
    }

    func child(item: JSONValue?) -> MenuBindingResolver {
        MenuBindingResolver(data: data, item: item)
    }

    func resolveString(_ template: String?) -> String {
        guard let template else {
            return ""
        }

        if let path = Self.wholeBindingPath(in: template) {
            return value(at: path)?.displayString ?? "-"
        }

        var result = template
        for match in Self.bindingMatches(in: template).reversed() {
            let replacement = value(at: match.path)?.displayString ?? "-"
            result.replaceSubrange(match.range, with: replacement)
        }
        return result
    }

    func resolveBool(_ value: JSONValue?, default defaultValue: Bool) -> Bool {
        guard let resolved = resolveValue(value) else {
            return defaultValue
        }
        return resolved.boolValue ?? defaultValue
    }

    func resolveDouble(_ value: JSONValue?, default defaultValue: Double) -> Double {
        guard let resolved = resolveValue(value) else {
            return defaultValue
        }
        return resolved.doubleValue ?? defaultValue
    }

    func resolveArray(_ binding: String) -> [JSONValue] {
        guard let path = Self.wholeBindingPath(in: binding),
              let values = value(at: path)?.arrayValue else {
            return []
        }
        return values
    }

    func resolveValue(_ value: JSONValue?) -> JSONValue? {
        guard let value else {
            return nil
        }

        if case .string(let template) = value,
           let path = Self.wholeBindingPath(in: template) {
            return self.value(at: path)
        }
        return value
    }

    func value(at path: String) -> JSONValue? {
        let components = path
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !components.isEmpty else {
            return nil
        }

        let root: JSONValue?
        let remaining: ArraySlice<String>
        if components.first == "item" {
            root = item
            remaining = components.dropFirst()
        } else {
            root = data
            remaining = components[...]
        }

        guard let root else {
            return nil
        }
        return remaining.reduce(Optional(root)) { partial, component in
            guard let partial else {
                return nil
            }
            return partial.descending(to: component)
        }
    }

    private static func wholeBindingPath(in template: String) -> String? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}") else {
            return nil
        }
        let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
        let end = trimmed.index(trimmed.endIndex, offsetBy: -2)
        let path = trimmed[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func bindingMatches(in template: String) -> [(range: Range<String.Index>, path: String)] {
        var matches: [(Range<String.Index>, String)] = []
        var searchStart = template.startIndex

        while let open = template.range(of: "{{", range: searchStart..<template.endIndex),
              let close = template.range(of: "}}", range: open.upperBound..<template.endIndex) {
            let path = template[open.upperBound..<close.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                matches.append((open.lowerBound..<close.upperBound, path))
            }
            searchStart = close.upperBound
        }

        return matches
    }
}

private extension JSONValue {
    func descending(to component: String) -> JSONValue? {
        switch self {
        case .object(let object):
            return object[component]
        case .array(let array):
            guard let index = Int(component), array.indices.contains(index) else {
                return nil
            }
            return array[index]
        case .string, .number, .bool, .null:
            return nil
        }
    }
}
