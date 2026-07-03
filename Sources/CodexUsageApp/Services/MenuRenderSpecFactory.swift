import Foundation

// MARK: - 当前业务数据到菜单 DSL 的适配

enum MenuUsageState {
    case idle
    case loading
    case loaded(UsageSnapshot)
    case failed(String)
}

enum MenuEndpointState {
    case idle
    case loading
    case loaded(EndpointRecommendation)
    case failed(String)
}

struct MenuPresentationState {
    var usage: MenuUsageState
    var endpoint: MenuEndpointState
    var isRefreshing: Bool
    var feedbackText: String?
}

/// 生成当前菜单使用的默认 JSON 模板，并把业务结果填入 `data`。
enum MenuRenderSpecFactory {
    static func makeSpec(for state: MenuPresentationState) -> MenuRenderSpec {
        var spec = baseTemplate
        spec.data = makeData(for: state)
        return spec
    }

    static func makeInitialSpec() -> MenuRenderSpec {
        makeSpec(
            for: MenuPresentationState(
                usage: .idle,
                endpoint: .idle,
                isRefreshing: false,
                feedbackText: nil
            )
        )
    }

    private static let baseTemplate: MenuRenderSpec = {
        do {
            return try JSONDecoder().decode(MenuRenderSpec.self, from: loadDefaultTemplateData())
        } catch {
            fatalError("默认菜单渲染 JSON 加载失败: \(error.localizedDescription)")
        }
    }()

    private static func loadDefaultTemplateData() throws -> Data {
        if let url = Bundle.main.url(forResource: "default-menu-render", withExtension: "json") {
            return try Data(contentsOf: url)
        }

        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/default-menu-render.json")
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return try Data(contentsOf: sourceURL)
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private static func makeData(for state: MenuPresentationState) -> JSONValue {
        .object([
            "statusItem": .object([
                "title": JSONValue(statusItemTitle(from: state.usage))
            ]),
            "controls": .object([
                "canRefresh": JSONValue(!state.isRefreshing)
            ]),
            "summary": summaryData(from: state.usage),
            "usageRows": usageRowsData(from: state.usage),
            "endpoint": endpointData(from: state.endpoint),
            "footer": footerData(from: state.usage),
            "status": statusData(from: state)
        ])
    }

    private static func statusItemTitle(from state: MenuUsageState) -> String {
        guard case .loaded(let snapshot) = state,
              snapshot.dailyLimit > 0 else {
            return " --"
        }

        let remaining = max(0, min(100, 100 - snapshot.dailyUsage / snapshot.dailyLimit * 100))
        return " \(Int(remaining.rounded()))%"
    }

    private static func summaryData(from state: MenuUsageState) -> JSONValue {
        guard case .loaded(let snapshot) = state,
              let remaining = snapshot.remaining else {
            return .object([
                "value": JSONValue("-"),
                "caption": JSONValue("REMAINING")
            ])
        }

        return .object([
            "value": JSONValue("$\(amount(remaining, fractionDigits: 2))"),
            "caption": JSONValue("REMAINING")
        ])
    }

    private static func usageRowsData(from state: MenuUsageState) -> JSONValue {
        let rows: [[String: JSONValue]]
        if case .loaded(let snapshot) = state {
            rows = [
                usageRow(
                    title: "Daily",
                    icon: "clock",
                    usage: snapshot.dailyUsage,
                    limit: snapshot.dailyLimit,
                    color: "systemBlue"
                ),
                usageRow(
                    title: "Weekly",
                    icon: "calendar",
                    usage: snapshot.weeklyUsage,
                    limit: snapshot.weeklyLimit,
                    color: "systemIndigo"
                ),
                usageRow(
                    title: "Monthly",
                    icon: "chart.bar",
                    usage: snapshot.monthlyUsage,
                    limit: snapshot.monthlyLimit,
                    color: "systemPurple"
                )
            ]
        } else {
            rows = [
                emptyUsageRow(title: "Daily", icon: "clock", color: "systemBlue"),
                emptyUsageRow(title: "Weekly", icon: "calendar", color: "systemIndigo"),
                emptyUsageRow(title: "Monthly", icon: "chart.bar", color: "systemPurple")
            ]
        }

        return .array(rows)
    }

    private static func usageRow(
        title: String,
        icon: String,
        usage: Double,
        limit: Double,
        color: String
    ) -> [String: JSONValue] {
        let progress = limit > 0 ? max(0, min(usage / limit, 1)) : 0
        let percentage = limit > 0 ? usage / limit * 100 : 0
        return [
            "title": JSONValue(title),
            "icon": JSONValue(icon),
            "progress": JSONValue(progress),
            "percent": JSONValue(String(format: "%.1f%%", percentage)),
            "amount": JSONValue("$\(amount(usage, fractionDigits: 1)) / $\(amount(limit, fractionDigits: 1))"),
            "color": JSONValue(color)
        ]
    }

    private static func emptyUsageRow(title: String, icon: String, color: String) -> [String: JSONValue] {
        [
            "title": JSONValue(title),
            "icon": JSONValue(icon),
            "progress": JSONValue(0),
            "percent": JSONValue("0.0%"),
            "amount": JSONValue("$0 / $1"),
            "color": JSONValue(color)
        ]
    }

    private static func endpointData(from state: MenuEndpointState) -> JSONValue {
        switch state {
        case .idle:
            return .object([
                "title": JSONValue("节点推荐 -"),
                "source": JSONValue("NETWORK"),
                "host": JSONValue(""),
                "hostText": JSONValue("域名 -"),
                "canCopy": JSONValue(false),
                "lineStyle": JSONValue("detailLine"),
                "lines": .array([JSONValue("等待探测")])
            ])
        case .loading:
            return .object([
                "title": JSONValue("节点推荐 探测中"),
                "source": JSONValue("NETWORK"),
                "host": JSONValue(""),
                "hostText": JSONValue("域名 -"),
                "canCopy": JSONValue(false),
                "lineStyle": JSONValue("detailLine"),
                "lines": .array([JSONValue("正在读取公共设置并运行 traceroute")])
            ])
        case .loaded(let recommendation):
            let host = recommendation.recommendedHost ?? ""
            return .object([
                "title": JSONValue(recommendation.headline),
                "source": JSONValue(recommendation.sourceLabel),
                "host": JSONValue(host),
                "hostText": JSONValue(host.isEmpty ? "域名 -" : host),
                "canCopy": JSONValue(!host.isEmpty),
                "lineStyle": JSONValue("detailLine"),
                "lines": .array(recommendation.detailLines.map(JSONValue.init))
            ])
        case .failed(let message):
            return .object([
                "title": JSONValue("节点推荐 暂不可用"),
                "source": JSONValue("NETWORK"),
                "host": JSONValue(""),
                "hostText": JSONValue("域名 -"),
                "canCopy": JSONValue(false),
                "lineStyle": JSONValue("error"),
                "lines": .array([JSONValue(message)])
            ])
        }
    }

    private static func footerData(from state: MenuUsageState) -> JSONValue {
        guard case .loaded(let snapshot) = state else {
            return .object([
                "left": JSONValue("Expires: -"),
                "right": JSONValue("等待刷新")
            ])
        }

        let expires = snapshot.expiresAt == "-" ? "Never" : snapshot.expiresAt
        return .object([
            "left": JSONValue("Expires: \(expires)"),
            "right": JSONValue(snapshot.schemaLabel)
        ])
    }

    private static func statusData(from state: MenuPresentationState) -> JSONValue {
        if let feedbackText = state.feedbackText {
            return .object([
                "visible": JSONValue(true),
                "text": JSONValue(feedbackText),
                "style": JSONValue("secondary")
            ])
        }

        switch state.usage {
        case .loading:
            return .object([
                "visible": JSONValue(true),
                "text": JSONValue("正在刷新..."),
                "style": JSONValue("secondary")
            ])
        case .failed(let message):
            return .object([
                "visible": JSONValue(true),
                "text": JSONValue("错误: \(message)"),
                "style": JSONValue("error")
            ])
        case .idle, .loaded:
            return .object([
                "visible": JSONValue(false),
                "text": JSONValue(""),
                "style": JSONValue("secondary")
            ])
        }
    }

    private static func amount(_ value: Double, fractionDigits: Int) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.\(fractionDigits)f", value)
    }

}
