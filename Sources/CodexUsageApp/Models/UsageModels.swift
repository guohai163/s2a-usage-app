import Foundation

// MARK: - 用量与节点数据模型

/// 用量接口解析后的 UI 展示快照。
///
/// 应用同时兼容官方 subscription 格式和代理服务的聚合格式，
/// 因此这里保存的是界面真正需要的统一字段，而不是原始响应结构。
struct UsageSnapshot {
    /// 今日已使用额度与今日上限，单位为 USD。
    let dailyUsage: Double
    let dailyLimit: Double
    /// 本周已使用额度与本周上限，单位为 USD。
    let weeklyUsage: Double
    let weeklyLimit: Double
    /// 本月已使用额度与本月上限，单位为 USD。
    let monthlyUsage: Double
    let monthlyLimit: Double
    /// 订阅过期时间；代理格式没有该字段时使用占位值。
    let expiresAt: String
    /// 代理格式中的剩余额度；官方 subscription 格式可能为空。
    let remaining: Double?
    /// 标记当前快照来自哪种响应格式。
    let schemaLabel: String
    /// 展示给用户的补充说明，例如套餐名或剩余额度。
    let note: String?
}

/// 从 public settings 中解析出的可探测节点。
struct EndpointCandidate: Codable {
    let name: String
    let endpoint: String
    let host: String

    /// 优先展示配置中的名称；名称为空或等于 host 时直接展示域名。
    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.caseInsensitiveCompare(host) == .orderedSame {
            return host
        }
        return trimmedName
    }
}

/// 单个节点的 traceroute 探测结果。
struct EndpointProbeResult {
    let candidate: EndpointCandidate
    let hopCount: Int
    let timeoutHops: Int
    let lastLatencyMs: Double?
    let averageLatencyMs: Double?
    let timedOut: Bool
    let errorMessage: String?

    /// 综合 RTT、跳数、超时跳数和截断状态得到的排序分数，分数越低越推荐。
    var score: Double? {
        guard let latency = lastLatencyMs ?? averageLatencyMs else {
            return nil
        }

        return latency
            + Double(hopCount) * 2.5
            + Double(timeoutHops) * 35
            + (timedOut ? 160 : 0)
    }

    /// 展示在 UI 中的单行探测摘要。
    var summaryText: String {
        if let errorMessage, score == nil {
            return errorMessage
        }

        var parts = [latencyText, "\(hopCount) 跳"]
        if timeoutHops > 0 {
            parts.append("\(timeoutHops) 个超时跳")
        }
        if timedOut {
            parts.append("已截断")
        }
        return parts.joined(separator: " · ")
    }

    private var latencyText: String {
        guard let latency = lastLatencyMs ?? averageLatencyMs else {
            return "无 RTT"
        }
        if latency.rounded() == latency {
            return "\(Int(latency)) ms"
        }
        return String(format: "%.1f ms", latency)
    }
}

/// 多个节点探测后的推荐结果。
struct EndpointRecommendation {
    let results: [EndpointProbeResult]
    let isFromCache: Bool
    let fallbackReason: String?

    /// 根据 score 选出的最佳节点。
    var recommended: EndpointProbeResult? {
        results
            .compactMap { result -> (EndpointProbeResult, Double)? in
                guard let score = result.score else {
                    return nil
                }
                return (result, score)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    var recommendedHost: String? {
        recommended?.candidate.host
    }

    /// 结果来源标记：网络实时获取或本地缓存兜底。
    var sourceLabel: String {
        isFromCache ? "CACHE" : "NETWORK"
    }

    private var rankedResults: [EndpointProbeResult] {
        results.enumerated()
            .sorted { left, right in
                let leftScore = left.element.score ?? Double.greatestFiniteMagnitude
                let rightScore = right.element.score ?? Double.greatestFiniteMagnitude
                if leftScore == rightScore {
                    return left.offset < right.offset
                }
                return leftScore < rightScore
            }
            .map(\.element)
    }

    /// 弹层和主窗口顶部展示的推荐标题。
    var headline: String {
        guard let recommended else {
            return "节点推荐 暂不可用"
        }
        return "推荐 \(recommended.candidate.displayName)"
    }

    var detail: String {
        detailLines.joined(separator: "\n")
    }

    /// 适合菜单栏弹层逐行展示的详情。
    var detailLines: [String] {
        guard let recommended else {
            let failed = results.map { "\($0.candidate.displayName): \($0.summaryText)" }
            return failed.isEmpty ? ["没有可探测的 custom_endpoints 节点。"] : failed
        }

        let heading = isFromCache ? "缓存节点 traceroute" : "全部节点 traceroute"
        let lines = rankedResults.map { result in
            let marker = result.candidate.host == recommended.candidate.host ? "推荐 " : ""
            return "\(marker)\(result.candidate.displayName): \(result.summaryText)"
        }
        return [heading] + lines
    }
}

/// 业务层统一抛出的错误，直接面向中文 UI 文案。
enum UsageError: LocalizedError {
    case missingFile(String)
    case invalidJSON(String)
    case invalidTOML(String)
    case missingAPIKey
    case missingBaseURL
    case invalidURL(String)
    case httpStatus(Int)
    case publicSettingsStatus(Int)
    case network(String)
    case missingUsageSchema
    case missingCustomEndpoints
    case missingNumber(String)
    case missingText(String)
    case invalidLimit

    var errorDescription: String? {
        switch self {
        case .missingFile(let path):
            return "未找到文件: \(path)"
        case .invalidJSON(let detail):
            return "JSON 格式不正确: \(detail)"
        case .invalidTOML(let detail):
            return "TOML 格式不正确: \(detail)"
        case .missingAPIKey:
            return "auth.json 缺少有效的 OPENAI_API_KEY。"
        case .missingBaseURL:
            return "config.toml 缺少有效的 [model_providers.OpenAI].base_url。"
        case .invalidURL(let url):
            return "接口地址无效: \(url)"
        case .httpStatus(let status):
            return "请求用量接口失败，HTTP 状态码: \(status)"
        case .publicSettingsStatus(let status):
            return "请求公共设置失败，HTTP 状态码: \(status)"
        case .network(let detail):
            return "网络请求失败: \(detail)"
        case .missingUsageSchema:
            return "响应中没有 subscription，也不是可识别的代理用量格式。"
        case .missingCustomEndpoints:
            return "公共设置中没有可识别的 custom_endpoints 节点。"
        case .missingNumber(let field):
            return "subscription.\(field) 缺失或不是数字。"
        case .missingText(let field):
            return "subscription.\(field) 缺失或不是有效字符串。"
        case .invalidLimit:
            return "subscription 中存在 limit 为 0 或负数，无法计算进度。"
        }
    }
}
