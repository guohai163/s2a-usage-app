import Foundation

// MARK: - Codex 用量与节点推荐服务

/// 负责读取本机 Codex 配置、请求用量接口，并生成节点推荐结果。
///
/// 这个服务不持有任何 AppKit 状态；所有 UI 更新都通过 completion 交回调用方处理。
final class UsageService {
    private static let endpointCacheKey = "CodexUsage.EndpointCandidatesCache.v1"
    private let authPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/config.toml")

    /// 读取 API Key/base URL 后，请求 `/v1/usage` 并解析成统一快照。
    func loadUsage(completion: @escaping (Result<UsageSnapshot, UsageError>) -> Void) {
        do {
            let apiKey = try loadAPIKey()
            let baseURL = try loadBaseURL()
            try fetchUsage(baseURL: baseURL, apiKey: apiKey, completion: completion)
        } catch let error as UsageError {
            completion(.failure(error))
        } catch {
            completion(.failure(.network(error.localizedDescription)))
        }
    }

    /// 从公共设置读取 custom_endpoints，并用 traceroute 给出本机网络视角下的推荐。
    ///
    /// 如果公共设置不可用，会回退到上一次成功解析出的节点缓存继续探测。
    func loadEndpointRecommendation(completion: @escaping (Result<EndpointRecommendation, UsageError>) -> Void) {
        do {
            let baseURL = try loadBaseURL()
            let apiKey = try? loadAPIKey()
            try fetchPublicSettings(baseURL: baseURL, apiKey: apiKey) { [weak self] result in
                guard let self else {
                    return
                }
                switch result {
                case .success(let recommendation):
                    completion(.success(recommendation))
                case .failure(let error):
                    self.completeWithCachedEndpoints(
                        fallbackReason: error.localizedDescription,
                        fallbackError: error,
                        completion: completion
                    )
                }
            }
        } catch let error as UsageError {
            completeWithCachedEndpoints(
                fallbackReason: error.localizedDescription,
                fallbackError: error,
                completion: completion
            )
        } catch {
            let usageError = UsageError.network(error.localizedDescription)
            completeWithCachedEndpoints(
                fallbackReason: usageError.localizedDescription,
                fallbackError: usageError,
                completion: completion
            )
        }
    }

    /// 从 `~/.codex/auth.json` 中读取顶层 `OPENAI_API_KEY`。
    private func loadAPIKey() throws -> String {
        guard FileManager.default.fileExists(atPath: authPath.path) else {
            throw UsageError.missingFile(authPath.path)
        }

        do {
            let data = try Data(contentsOf: authPath)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let payload = object as? [String: Any],
                  let value = payload["OPENAI_API_KEY"] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UsageError.missingAPIKey
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.invalidJSON(error.localizedDescription)
        }
    }

    /// 从 `~/.codex/config.toml` 中读取 `[model_providers.OpenAI].base_url`。
    private func loadBaseURL() throws -> String {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw UsageError.missingFile(configPath.path)
        }

        do {
            let text = try String(contentsOf: configPath, encoding: .utf8)
            if let value = parseOpenAIBaseURL(from: text) {
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            throw UsageError.missingBaseURL
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.invalidTOML(error.localizedDescription)
        }
    }

    private func parseOpenAIBaseURL(from text: String) -> String? {
        var inOpenAIProvider = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inOpenAIProvider = line == "[model_providers.OpenAI]"
                continue
            }
            guard inOpenAIProvider else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == "base_url" else {
                continue
            }

            let rawValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let unquoted = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return unquoted.isEmpty ? nil : unquoted
        }

        return nil
    }

    private func stripComment(_ line: String) -> String {
        var result = ""
        var quote: Character?

        for character in line {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }
            if character == "#", quote == nil {
                break
            }
            result.append(character)
        }

        return result
    }

    /// 请求 Codex 用量接口，并兼容官方 subscription 与代理聚合格式。
    private func fetchUsage(
        baseURL: String,
        apiKey: String,
        completion: @escaping (Result<UsageSnapshot, UsageError>) -> Void
    ) throws {
        let endpoint = "\(baseURL)/v1/usage"
        guard let url = URL(string: endpoint) else {
            throw UsageError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            if let http = response as? HTTPURLResponse,
               http.statusCode < 200 || http.statusCode >= 300 {
                completion(.failure(.httpStatus(http.statusCode)))
                return
            }
            guard let data else {
                completion(.failure(.network("响应为空")))
                return
            }

            do {
                let object = try JSONSerialization.jsonObject(with: data)
                let snapshot = try Self.parseSnapshot(from: object)
                completion(.success(snapshot))
            } catch let usageError as UsageError {
                completion(.failure(usageError))
            } catch {
                completion(.failure(.invalidJSON(error.localizedDescription)))
            }
        }.resume()
    }

    /// 请求同源公共设置，提取候选节点后在后台队列运行 traceroute。
    private func fetchPublicSettings(
        baseURL: String,
        apiKey: String?,
        completion: @escaping (Result<EndpointRecommendation, UsageError>) -> Void
    ) throws {
        let url = try publicSettingsURL(from: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            if let http = response as? HTTPURLResponse,
               http.statusCode < 200 || http.statusCode >= 300 {
                completion(.failure(.publicSettingsStatus(http.statusCode)))
                return
            }
            guard let data else {
                completion(.failure(.network("公共设置响应为空")))
                return
            }

            do {
                let object = try JSONSerialization.jsonObject(with: data)
                let candidates = try Self.parseEndpointCandidates(from: object)
                DispatchQueue.global(qos: .utility).async {
                    let recommendation = self.probeEndpoints(candidates, isFromCache: false, fallbackReason: nil)
                    self.saveEndpointCache(from: recommendation.results.map(\.candidate))
                    completion(.success(recommendation))
                }
            } catch let usageError as UsageError {
                completion(.failure(usageError))
            } catch {
                completion(.failure(.invalidJSON(error.localizedDescription)))
            }
        }.resume()
    }

    /// 公共设置不可用时，使用上一次成功获取的节点缓存继续完成推荐流程。
    private func completeWithCachedEndpoints(
        fallbackReason: String,
        fallbackError: UsageError,
        completion: @escaping (Result<EndpointRecommendation, UsageError>) -> Void
    ) {
        let candidates = loadEndpointCache()
        guard !candidates.isEmpty else {
            completion(.failure(fallbackError))
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let recommendation = self.probeEndpoints(
                candidates,
                isFromCache: true,
                fallbackReason: fallbackReason
            )
            completion(.success(recommendation))
        }
    }

    /// 将配置中的 base URL 规范化为 `/api/v1/settings/public` 地址。
    private func publicSettingsURL(from baseURL: String) throws -> URL {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("//") {
            normalized = "https:\(normalized)"
        } else if !normalized.contains("://") {
            normalized = "https://\(normalized)"
        }

        guard var components = URLComponents(string: normalized),
              components.host?.isEmpty == false else {
            throw UsageError.invalidURL(baseURL)
        }

        components.path = "/api/v1/settings/public"
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw UsageError.invalidURL(baseURL)
        }
        return url
    }

    /// 并发探测最多 4 个节点，避免菜单栏应用刷新时阻塞过久。
    private func probeEndpoints(
        _ candidates: [EndpointCandidate],
        isFromCache: Bool,
        fallbackReason: String?
    ) -> EndpointRecommendation {
        let limitedCandidates = Array(candidates.prefix(4))
        let group = DispatchGroup()
        let lock = NSLock()
        var indexedResults: [(Int, EndpointProbeResult)] = []

        for (index, candidate) in limitedCandidates.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let result = self.runTraceroute(for: candidate)
                lock.lock()
                indexedResults.append((index, result))
                lock.unlock()
                group.leave()
            }
        }

        group.wait()
        return EndpointRecommendation(
            results: indexedResults
                .sorted { $0.0 < $1.0 }
                .map { $0.1 },
            isFromCache: isFromCache,
            fallbackReason: fallbackReason
        )
    }

    private func saveEndpointCache(from candidates: [EndpointCandidate]) {
        var uniqueCandidates: [EndpointCandidate] = []
        var seenHosts = Set<String>()

        for candidate in candidates {
            let key = candidate.host.lowercased()
            guard !seenHosts.contains(key) else {
                continue
            }
            seenHosts.insert(key)
            uniqueCandidates.append(candidate)
        }

        guard !uniqueCandidates.isEmpty,
              let data = try? JSONEncoder().encode(uniqueCandidates) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.endpointCacheKey)
    }

    private func loadEndpointCache() -> [EndpointCandidate] {
        guard let data = UserDefaults.standard.data(forKey: Self.endpointCacheKey),
              let candidates = try? JSONDecoder().decode([EndpointCandidate].self, from: data) else {
            return []
        }

        return candidates.filter {
            !$0.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 调用系统 traceroute 并把输出解析成节点评分输入。
    private func runTraceroute(for candidate: EndpointCandidate) -> EndpointProbeResult {
        guard let traceroutePath = Self.traceroutePath() else {
            return EndpointProbeResult(
                candidate: candidate,
                hopCount: 0,
                timeoutHops: 0,
                lastLatencyMs: nil,
                averageLatencyMs: nil,
                timedOut: false,
                errorMessage: "未找到 traceroute"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: traceroutePath)
        process.arguments = ["-n", "-q", "1", "-m", "16", "-w", "1", candidate.host]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return EndpointProbeResult(
                candidate: candidate,
                hopCount: 0,
                timeoutHops: 0,
                lastLatencyMs: nil,
                averageLatencyMs: nil,
                timedOut: false,
                errorMessage: error.localizedDescription
            )
        }

        var timedOut = false
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            timedOut = true
            process.terminate()
        }
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return Self.parseTracerouteOutput(
            output,
            candidate: candidate,
            timedOut: timedOut,
            terminationStatus: process.terminationStatus
        )
    }

    private static func traceroutePath() -> String? {
        ["/usr/sbin/traceroute", "/sbin/traceroute", "/usr/bin/traceroute"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 在公共设置响应中递归查找 custom_endpoints，并去重为候选节点。
    private static func parseEndpointCandidates(from object: Any) throws -> [EndpointCandidate] {
        guard let customEndpoints = findCustomEndpoints(in: object) else {
            throw UsageError.missingCustomEndpoints
        }

        let candidates = endpointCandidates(from: customEndpoints, fallbackName: nil)
        var uniqueCandidates: [EndpointCandidate] = []
        var seenHosts = Set<String>()

        for candidate in candidates {
            let key = candidate.host.lowercased()
            guard !seenHosts.contains(key) else {
                continue
            }
            seenHosts.insert(key)
            uniqueCandidates.append(candidate)
        }

        guard !uniqueCandidates.isEmpty else {
            throw UsageError.missingCustomEndpoints
        }
        return uniqueCandidates
    }

    private static func findCustomEndpoints(in object: Any) -> Any? {
        if let payload = object as? [String: Any] {
            if let value = payload["custom_endpoints"] ?? payload["customEndpoints"] {
                return value
            }
            for key in payload.keys.sorted() {
                guard let value = payload[key] else {
                    continue
                }
                if let found = findCustomEndpoints(in: value) {
                    return found
                }
            }
        }

        if let array = object as? [Any] {
            for item in array {
                if let found = findCustomEndpoints(in: item) {
                    return found
                }
            }
        }

        return nil
    }

    private static func endpointCandidates(from value: Any, fallbackName: String?) -> [EndpointCandidate] {
        if let payload = value as? [String: Any] {
            if let endpoint = firstText(in: payload, keys: endpointValueKeys),
               let candidate = makeEndpointCandidate(
                    name: firstText(in: payload, keys: endpointNameKeys) ?? fallbackName ?? endpoint,
                    endpoint: endpoint
               ) {
                return [candidate]
            }

            return payload.keys.sorted().flatMap { key -> [EndpointCandidate] in
                guard let value = payload[key] else {
                    return []
                }
                return endpointCandidates(from: value, fallbackName: displayName(fromKey: key))
            }
        }

        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, item in
                endpointCandidates(from: item, fallbackName: fallbackName ?? "节点 \(index + 1)")
            }
        }

        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
                return endpointCandidates(from: json, fallbackName: fallbackName)
            }

            if let candidate = makeEndpointCandidate(name: fallbackName ?? trimmed, endpoint: trimmed) {
                return [candidate]
            }
        }

        return []
    }

    private static let endpointNameKeys = [
        "name",
        "label",
        "title",
        "display_name",
        "displayName",
        "region"
    ]

    private static let endpointValueKeys = [
        "url",
        "base_url",
        "baseURL",
        "endpoint",
        "api_base",
        "apiBase",
        "value",
        "host",
        "domain"
    ]

    private static func firstText(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = payload[key] as? String else {
                continue
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func makeEndpointCandidate(name: String, endpoint: String) -> EndpointCandidate? {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = host(from: trimmedEndpoint) else {
            return nil
        }
        return EndpointCandidate(name: name, endpoint: trimmedEndpoint, host: host)
    }

    private static func host(from endpoint: String) -> String? {
        var normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        if normalized.hasPrefix("//") {
            normalized = "https:\(normalized)"
        } else if !normalized.contains("://") {
            normalized = "https://\(normalized)"
        }

        if let host = URLComponents(string: normalized)?.host,
           !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return host
        }

        let withoutScheme = endpoint
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        let hostPart = withoutScheme
            .split(separator: "/")
            .first?
            .split(separator: ":")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return hostPart?.isEmpty == false ? hostPart : nil
    }

    private static func displayName(fromKey key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTracerouteOutput(
        _ output: String,
        candidate: EndpointCandidate,
        timedOut: Bool,
        terminationStatus: Int32
    ) -> EndpointProbeResult {
        var hopCount = 0
        var timeoutHops = 0
        var latencies: [Double] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let firstToken = trimmed.split(separator: " ").first,
                  let hopNumber = Int(firstToken) else {
                continue
            }

            hopCount = max(hopCount, hopNumber)
            if trimmed.contains("*") {
                timeoutHops += 1
            }
            latencies.append(contentsOf: latencyValues(in: trimmed))
        }

        let averageLatency = latencies.isEmpty
            ? nil
            : latencies.reduce(0, +) / Double(latencies.count)
        let lastLatency = latencies.last
        let errorMessage = latencies.isEmpty && terminationStatus != 0
            ? firstUsefulLine(in: output) ?? "traceroute 未返回可用数据"
            : nil

        return EndpointProbeResult(
            candidate: candidate,
            hopCount: hopCount,
            timeoutHops: timeoutHops,
            lastLatencyMs: lastLatency,
            averageLatencyMs: averageLatency,
            timedOut: timedOut,
            errorMessage: errorMessage
        )
    }

    private static func latencyValues(in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(
            pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*ms",
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return Double(text[valueRange])
        }
    }

    private static func firstUsefulLine(in output: String) -> String? {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// 把用量响应转换为 UI 使用的统一快照。
    private static func parseSnapshot(from object: Any) throws -> UsageSnapshot {
        guard let payload = object as? [String: Any] else {
            throw UsageError.missingUsageSchema
        }

        if let subscription = payload["subscription"] as? [String: Any] {
            return try parseSubscriptionSnapshot(subscription)
        }

        if payload["daily_usage"] != nil || payload["usage"] != nil {
            return try parseProxyUsageSnapshot(payload)
        }

        throw UsageError.missingUsageSchema
    }

    private static func parseSubscriptionSnapshot(_ subscription: [String: Any]) throws -> UsageSnapshot {
        let dailyLimit = try requireNumber(subscription, "daily_limit_usd")
        let weeklyLimit = try requireNumber(subscription, "weekly_limit_usd")
        let monthlyLimit = try requireNumber(subscription, "monthly_limit_usd")
        guard dailyLimit > 0, weeklyLimit > 0, monthlyLimit > 0 else {
            throw UsageError.invalidLimit
        }

        return UsageSnapshot(
            dailyUsage: try requireNumber(subscription, "daily_usage_usd"),
            dailyLimit: dailyLimit,
            weeklyUsage: try requireNumber(subscription, "weekly_usage_usd"),
            weeklyLimit: weeklyLimit,
            monthlyUsage: try requireNumber(subscription, "monthly_usage_usd"),
            monthlyLimit: monthlyLimit,
            expiresAt: try requireText(subscription, "expires_at"),
            remaining: nil,
            schemaLabel: "Subscription",
            note: nil
        )
    }

    private static func parseProxyUsageSnapshot(_ payload: [String: Any]) throws -> UsageSnapshot {
        let usage = payload["usage"] as? [String: Any]
        let today = usage?["today"] as? [String: Any]
        let total = usage?["total"] as? [String: Any]
        let rows = payload["daily_usage"] as? [[String: Any]] ?? []

        let dailyUsage = optionalCost(today) ?? currentDayCost(from: rows)
        let weeklyUsage = periodCost(from: rows, matching: .weekOfYear)
        let monthlyUsage = periodCost(from: rows, matching: .month)
        let totalUsage = optionalCost(total) ?? rows.reduce(0) { $0 + cost(from: $1) }
        let remaining = optionalNumber(payload, "remaining") ?? optionalNumber(payload, "balance") ?? 0
        let budget = max(remaining + max(monthlyUsage, totalUsage), monthlyUsage, weeklyUsage, dailyUsage, 1)
        let planName = (payload["planName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteParts = [
            "代理用量格式",
            planName?.isEmpty == false ? "套餐: \(planName!)" : nil,
            "Remaining: \(amount(remaining)) USD"
        ].compactMap { $0 }

        return UsageSnapshot(
            dailyUsage: dailyUsage,
            dailyLimit: budget,
            weeklyUsage: weeklyUsage,
            weeklyLimit: budget,
            monthlyUsage: monthlyUsage,
            monthlyLimit: budget,
            expiresAt: "-",
            remaining: remaining,
            schemaLabel: "代理用量格式",
            note: noteParts.joined(separator: " · ")
        )
    }

    private static func requireNumber(_ payload: [String: Any], _ field: String) throws -> Double {
        if let value = payload[field] as? Double {
            return value
        }
        if let value = payload[field] as? Int {
            return Double(value)
        }
        throw UsageError.missingNumber(field)
    }

    private static func optionalNumber(_ payload: [String: Any]?, _ field: String) -> Double? {
        if let value = payload?[field] as? Double {
            return value
        }
        if let value = payload?[field] as? Int {
            return Double(value)
        }
        return nil
    }

    private static func requireText(_ payload: [String: Any], _ field: String) throws -> String {
        guard let value = payload[field] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageError.missingText(field)
        }
        return value
    }

    private static func optionalCost(_ payload: [String: Any]?) -> Double? {
        optionalNumber(payload, "actual_cost") ?? optionalNumber(payload, "cost")
    }

    private static func cost(from payload: [String: Any]) -> Double {
        optionalCost(payload) ?? 0
    }

    private static func currentDayCost(from rows: [[String: Any]]) -> Double {
        let calendar = Calendar.current
        return rows.reduce(0) { total, row in
            guard let date = date(from: row), calendar.isDateInToday(date) else {
                return total
            }
            return total + cost(from: row)
        }
    }

    private enum PeriodComponent {
        case weekOfYear
        case month
    }

    private static func periodCost(from rows: [[String: Any]], matching component: PeriodComponent) -> Double {
        let calendar = Calendar.current
        let now = Date()

        return rows.reduce(0) { total, row in
            guard let date = date(from: row) else {
                return total
            }

            let matches: Bool
            switch component {
            case .weekOfYear:
                matches = calendar.component(.weekOfYear, from: date) == calendar.component(.weekOfYear, from: now)
                    && calendar.component(.yearForWeekOfYear, from: date) == calendar.component(.yearForWeekOfYear, from: now)
            case .month:
                matches = calendar.component(.month, from: date) == calendar.component(.month, from: now)
                    && calendar.component(.year, from: date) == calendar.component(.year, from: now)
            }

            return matches ? total + cost(from: row) : total
        }
    }

    private static func date(from payload: [String: Any]) -> Date? {
        guard let value = payload["date"] as? String else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func amount(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
