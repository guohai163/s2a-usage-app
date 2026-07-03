import AppKit
import Foundation

private let barWidth = 20
private let statusPanelSize = NSSize(width: 292, height: 386)

private func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

private func makeCodexStatusIcon() -> NSImage {
    let size = NSSize(width: 22, height: 22)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.isTemplate = true
        return image
    }

    context.saveGState()
    defer { context.restoreGState() }

    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: size.width / 100, y: -size.height / 100)
    context.setStrokeColor(NSColor.black.cgColor)
    context.setFillColor(NSColor.black.cgColor)
    context.setLineWidth(4)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    func stroke(_ build: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        build(path)
        context.addPath(path)
        context.strokePath()
    }

    func fill(_ build: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        build(path)
        context.addPath(path)
        context.fillPath()
    }

    stroke { path in
        path.move(to: CGPoint(x: 12, y: 24))
        path.addCurve(to: CGPoint(x: 50, y: 12), control1: CGPoint(x: 12, y: 24), control2: CGPoint(x: 50, y: 12))
        path.addCurve(to: CGPoint(x: 88, y: 24), control1: CGPoint(x: 50, y: 12), control2: CGPoint(x: 88, y: 24))
        path.addLine(to: CGPoint(x: 86, y: 55))
        path.addCurve(to: CGPoint(x: 50, y: 96), control1: CGPoint(x: 84, y: 78), control2: CGPoint(x: 50, y: 96))
        path.addCurve(to: CGPoint(x: 14, y: 55), control1: CGPoint(x: 50, y: 96), control2: CGPoint(x: 16, y: 78))
        path.closeSubpath()
    }

    stroke { path in
        path.move(to: CGPoint(x: 50, y: 8))
        path.addLine(to: CGPoint(x: 60, y: 45))
        path.addLine(to: CGPoint(x: 50, y: 85))
        path.addLine(to: CGPoint(x: 40, y: 45))
        path.closeSubpath()
    }

    fill { path in
        path.move(to: CGPoint(x: 66, y: 35))
        path.addQuadCurve(to: CGPoint(x: 48, y: 52), control: CGPoint(x: 66, y: 52))
        path.addQuadCurve(to: CGPoint(x: 66, y: 70), control: CGPoint(x: 66, y: 52))
        path.addQuadCurve(to: CGPoint(x: 84, y: 52), control: CGPoint(x: 66, y: 52))
        path.addQuadCurve(to: CGPoint(x: 66, y: 35), control: CGPoint(x: 66, y: 52))
        path.closeSubpath()
    }

    fill { path in
        path.move(to: CGPoint(x: 76, y: 18))
        path.addQuadCurve(to: CGPoint(x: 69, y: 25), control: CGPoint(x: 76, y: 25))
        path.addQuadCurve(to: CGPoint(x: 76, y: 32), control: CGPoint(x: 76, y: 25))
        path.addQuadCurve(to: CGPoint(x: 83, y: 25), control: CGPoint(x: 76, y: 25))
        path.addQuadCurve(to: CGPoint(x: 76, y: 18), control: CGPoint(x: 76, y: 25))
        path.closeSubpath()
    }

    stroke { path in
        path.move(to: CGPoint(x: 40, y: 22))
        path.addCurve(to: CGPoint(x: 22, y: 45), control1: CGPoint(x: 29, y: 22), control2: CGPoint(x: 22, y: 32))
    }

    stroke { path in
        path.move(to: CGPoint(x: 20, y: 38))
        path.addCurve(to: CGPoint(x: 40, y: 76), control1: CGPoint(x: 13, y: 54), control2: CGPoint(x: 22, y: 75))
        path.addLine(to: CGPoint(x: 48, y: 68))
    }

    stroke { path in
        path.move(to: CGPoint(x: 42, y: 35))
        path.addLine(to: CGPoint(x: 32, y: 35))
        path.addLine(to: CGPoint(x: 32, y: 48))
        path.addLine(to: CGPoint(x: 42, y: 48))
    }

    stroke { path in
        path.move(to: CGPoint(x: 32, y: 48))
        path.addLine(to: CGPoint(x: 32, y: 54))
        path.addLine(to: CGPoint(x: 42, y: 64))
    }

    image.isTemplate = true
    return image
}

struct UsageSnapshot {
    let dailyUsage: Double
    let dailyLimit: Double
    let weeklyUsage: Double
    let weeklyLimit: Double
    let monthlyUsage: Double
    let monthlyLimit: Double
    let expiresAt: String
    let remaining: Double?
    let schemaLabel: String
    let note: String?
}

struct EndpointCandidate: Codable {
    let name: String
    let endpoint: String
    let host: String

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.caseInsensitiveCompare(host) == .orderedSame {
            return host
        }
        return trimmedName
    }
}

struct EndpointProbeResult {
    let candidate: EndpointCandidate
    let hopCount: Int
    let timeoutHops: Int
    let lastLatencyMs: Double?
    let averageLatencyMs: Double?
    let timedOut: Bool
    let errorMessage: String?

    var score: Double? {
        guard let latency = lastLatencyMs ?? averageLatencyMs else {
            return nil
        }

        return latency
            + Double(hopCount) * 2.5
            + Double(timeoutHops) * 35
            + (timedOut ? 160 : 0)
    }

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

struct EndpointRecommendation {
    let results: [EndpointProbeResult]
    let isFromCache: Bool
    let fallbackReason: String?

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

    var headline: String {
        guard let recommended else {
            return "节点推荐 暂不可用"
        }
        return "推荐 \(recommended.candidate.displayName)"
    }

    var detail: String {
        detailLines.joined(separator: "\n")
    }

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

final class UsageService {
    private static let endpointCacheKey = "CodexUsage.EndpointCandidatesCache.v1"
    private let authPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/config.toml")

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

final class ThinProgressView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }
    var fillColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 0, dy: 2)
        let radius = trackRect.height / 2
        let trackColor = isDarkAppearance(effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.13)
            : NSColor.black.withAlphaComponent(0.075)
        trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()

        let clamped = max(0, min(progress, 1))
        let fillWidth = clamped > 0 ? max(trackRect.height + 1, trackRect.width * clamped) : 0
        guard fillWidth > 0 else { return }

        fillColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: trackRect.minX, y: trackRect.minY, width: fillWidth, height: trackRect.height),
            xRadius: radius,
            yRadius: radius
        ).fill()
    }
}

final class GlassTintView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient: NSGradient?
        if isDarkAppearance(effectiveAppearance) {
            gradient = NSGradient(colorsAndLocations:
                (NSColor(calibratedRed: 0.22, green: 0.15, blue: 0.27, alpha: 0.62), 0.0),
                (NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.18, alpha: 0.48), 0.56),
                (NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 0.42), 1.0)
            )
        } else {
            gradient = NSGradient(colorsAndLocations:
                (NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.97, alpha: 0.30), 0.0),
                (NSColor(calibratedRed: 0.96, green: 0.78, blue: 1.0, alpha: 0.22), 0.58),
                (NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.24), 1.0)
            )
        }
        gradient?.draw(in: bounds, angle: 135)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class GlassPanelView: NSView {
    private let effect = NSVisualEffectView()
    private let tint = GlassTintView()
    var onAppearanceChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false

        tint.translatesAutoresizingMaskIntoConstraints = false

        addSubview(effect)
        addSubview(tint)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
        onAppearanceChange?()
    }

    private func applyAppearance() {
        if isDarkAppearance(effectiveAppearance) {
            effect.material = .hudWindow
            effect.appearance = NSAppearance(named: .vibrantDark)
            layer?.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
        } else {
            effect.material = .popover
            effect.appearance = NSAppearance(named: .vibrantLight)
            layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
        }
        tint.needsDisplay = true
    }
}

final class FooterBarView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let fillColor = isDarkAppearance(effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.055)
            : NSColor.white.withAlphaComponent(0.12)
        fillColor.setFill()
        bounds.fill()

        let lineColor = isDarkAppearance(effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.05)
        lineColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class UsagePanelWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

final class UsageMeterView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "0.0%")
    private let progress = ThinProgressView()
    private let amountLabel = NSTextField(labelWithString: "$0 / $1")
    private let rowName: String

    init(name: String, symbolName: String, color: NSColor) {
        rowName = name
        super.init(frame: .zero)
        progress.fillColor = color

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: name)
        iconView.image?.isTemplate = true
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = name
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentLabel.alignment = .right

        amountLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        amountLabel.alignment = .right

        let labelStack = NSStackView(views: [iconView, titleLabel])
        labelStack.orientation = .horizontal
        labelStack.alignment = .centerY
        labelStack.spacing = 5
        labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let top = NSStackView(views: [labelStack, percentLabel])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.distribution = .fill
        top.spacing = 8
        top.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [top, progress, amountLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            progress.heightAnchor.constraint(equalToConstant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 43)
        ])

        applyAppearance()
        update(usage: 0, limit: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(usage: Double, limit: Double) {
        let percentage = limit > 0 ? usage / limit * 100 : 0
        progress.progress = max(0, min(percentage / 100, 1))
        percentLabel.stringValue = String(format: "%.1f%%", percentage)
        amountLabel.stringValue = "$\(Self.amount(usage)) / $\(Self.amount(limit))"
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        if isDarkAppearance(effectiveAppearance) {
            let primary = NSColor.white.withAlphaComponent(0.90)
            let secondary = NSColor.white.withAlphaComponent(0.72)
            iconView.contentTintColor = secondary
            titleLabel.textColor = secondary
            percentLabel.textColor = primary
            amountLabel.textColor = secondary
        } else {
            iconView.contentTintColor = .secondaryLabelColor
            titleLabel.textColor = .secondaryLabelColor
            percentLabel.textColor = .labelColor
            amountLabel.textColor = .secondaryLabelColor
        }
    }

    private static func amount(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

final class StatusPopoverViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "Codex Usage")
    private let summaryLabel = NSTextField(labelWithString: "Remaining -")
    private let remainingCaption = NSTextField(labelWithString: "REMAINING")
    private let dailyRow = UsageMeterView(name: "Daily", symbolName: "clock", color: .systemBlue)
    private let weeklyRow = UsageMeterView(name: "Weekly", symbolName: "calendar", color: .systemIndigo)
    private let monthlyRow = UsageMeterView(name: "Monthly", symbolName: "chart.bar", color: .systemPurple)
    private let expiresLabel = NSTextField(labelWithString: "Expires: -")
    private let schemaLabel = NSTextField(labelWithString: "等待刷新")
    private let endpointLabel = NSTextField(labelWithString: "节点推荐 -")
    private let endpointCaption = NSTextField(labelWithString: "NETWORK")
    private let endpointDomainLabel = NSTextField(labelWithString: "域名 -")
    private let endpointResultsStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()
    private let copyEndpointButton = NSButton()
    private let quitButton = NSButton()
    private var currentEndpointHost: String?
    private var endpointResultsUseErrorColor = false

    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?

    override func loadView() {
        let panelView = GlassPanelView(frame: NSRect(origin: .zero, size: statusPanelSize))
        panelView.onAppearanceChange = { [weak self] in
            self?.applyAppearance()
        }
        view = panelView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 25, weight: .bold)
        remainingCaption.font = .systemFont(ofSize: 10, weight: .semibold)
        remainingCaption.alignment = .right

        expiresLabel.font = .systemFont(ofSize: 10, weight: .medium)
        expiresLabel.lineBreakMode = .byTruncatingMiddle
        expiresLabel.maximumNumberOfLines = 1
        expiresLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        schemaLabel.font = .systemFont(ofSize: 10, weight: .medium)
        schemaLabel.alignment = .right
        schemaLabel.lineBreakMode = .byTruncatingTail
        schemaLabel.maximumNumberOfLines = 1
        schemaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        endpointLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        endpointLabel.lineBreakMode = .byTruncatingMiddle
        endpointLabel.maximumNumberOfLines = 1
        endpointLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        endpointCaption.font = .systemFont(ofSize: 10, weight: .semibold)
        endpointCaption.alignment = .right
        endpointDomainLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        endpointDomainLabel.lineBreakMode = .byTruncatingMiddle
        endpointDomainLabel.maximumNumberOfLines = 1
        endpointDomainLabel.isSelectable = true
        endpointDomainLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        endpointResultsStack.orientation = .vertical
        endpointResultsStack.alignment = .width
        endpointResultsStack.spacing = 3
        endpointResultsStack.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true

        configureIconButton(refreshButton, symbolName: "arrow.clockwise", accessibility: "刷新用量")
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)

        configureIconButton(copyEndpointButton, symbolName: "doc.on.doc", accessibility: "复制推荐域名")
        copyEndpointButton.target = self
        copyEndpointButton.action = #selector(copyEndpointHostPressed)
        copyEndpointButton.isEnabled = false

        configureIconButton(quitButton, symbolName: "rectangle.portrait.and.arrow.right", accessibility: "退出")
        quitButton.target = self
        quitButton.action = #selector(quitPressed)

        let buttonStack = NSStackView(views: [refreshButton, quitButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 2

        let header = NSStackView(views: [titleLabel, buttonStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .gravityAreas
        header.translatesAutoresizingMaskIntoConstraints = false

        let summaryRow = NSStackView(views: [summaryLabel, remainingCaption])
        summaryRow.orientation = .horizontal
        summaryRow.alignment = .lastBaseline
        summaryRow.distribution = .gravityAreas
        summaryRow.translatesAutoresizingMaskIntoConstraints = false

        let rows = NSStackView(views: [dailyRow, weeklyRow, monthlyRow])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 7
        rows.translatesAutoresizingMaskIntoConstraints = false

        let endpointHeader = NSStackView(views: [endpointLabel, endpointCaption])
        endpointHeader.orientation = .horizontal
        endpointHeader.alignment = .centerY
        endpointHeader.distribution = .gravityAreas
        endpointHeader.translatesAutoresizingMaskIntoConstraints = false

        let endpointDomainRow = NSStackView(views: [endpointDomainLabel, copyEndpointButton])
        endpointDomainRow.orientation = .horizontal
        endpointDomainRow.alignment = .centerY
        endpointDomainRow.distribution = .fill
        endpointDomainRow.spacing = 6
        endpointDomainRow.translatesAutoresizingMaskIntoConstraints = false

        setEndpointResultLines(["等待探测"])

        let endpointStack = NSStackView(views: [endpointHeader, endpointDomainRow, endpointResultsStack])
        endpointStack.orientation = .vertical
        endpointStack.alignment = .width
        endpointStack.spacing = 3
        endpointStack.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [expiresLabel, schemaLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .gravityAreas
        footer.translatesAutoresizingMaskIntoConstraints = false

        let footerBar = FooterBarView()
        footerBar.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(footer)

        let stack = NSStackView(views: [header, separator(), summaryRow, rows, endpointStack, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(footerBar)
        NSLayoutConstraint.activate([
            refreshButton.widthAnchor.constraint(equalToConstant: 22),
            refreshButton.heightAnchor.constraint(equalToConstant: 22),
            copyEndpointButton.widthAnchor.constraint(equalToConstant: 20),
            copyEndpointButton.heightAnchor.constraint(equalToConstant: 20),
            quitButton.widthAnchor.constraint(equalToConstant: 22),
            quitButton.heightAnchor.constraint(equalToConstant: 22),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            summaryRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rows.widthAnchor.constraint(equalTo: stack.widthAnchor),
            endpointStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            endpointHeader.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            endpointDomainRow.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            endpointResultsStack.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            dailyRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            weeklyRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            monthlyRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: footerBar.topAnchor, constant: -8),
            footerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerBar.heightAnchor.constraint(equalToConstant: 32),
            footer.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -12),
            footer.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor)
        ])
        applyAppearance()
    }

    func setLoading() {
        refreshButton.isEnabled = false
        statusLabel.isHidden = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在刷新..."
    }

    func setError(_ error: Error) {
        statusLabel.isHidden = false
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = "错误: \(error.localizedDescription)"
    }

    func update(_ snapshot: UsageSnapshot) {
        dailyRow.update(usage: snapshot.dailyUsage, limit: snapshot.dailyLimit)
        weeklyRow.update(usage: snapshot.weeklyUsage, limit: snapshot.weeklyLimit)
        monthlyRow.update(usage: snapshot.monthlyUsage, limit: snapshot.monthlyLimit)
        expiresLabel.stringValue = "Expires: \(snapshot.expiresAt == "-" ? "Never" : snapshot.expiresAt)"
        summaryLabel.attributedStringValue = Self.remainingString(snapshot.remaining)
        schemaLabel.stringValue = snapshot.schemaLabel
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
    }

    func setEndpointChecking() {
        currentEndpointHost = nil
        endpointLabel.stringValue = "节点推荐 探测中"
        endpointCaption.stringValue = "NETWORK"
        endpointDomainLabel.stringValue = "域名 -"
        setEndpointResultLines(["正在读取公共设置并运行 traceroute"])
        copyEndpointButton.isEnabled = false
    }

    func setEndpointError(_ error: Error) {
        currentEndpointHost = nil
        endpointLabel.stringValue = "节点推荐 暂不可用"
        endpointCaption.stringValue = "NETWORK"
        endpointDomainLabel.stringValue = "域名 -"
        setEndpointResultLines([error.localizedDescription], isError: true)
        copyEndpointButton.isEnabled = false
    }

    func update(_ recommendation: EndpointRecommendation) {
        currentEndpointHost = recommendation.recommendedHost
        endpointLabel.stringValue = recommendation.headline
        endpointCaption.stringValue = recommendation.sourceLabel
        endpointDomainLabel.stringValue = recommendation.recommendedHost ?? "域名 -"
        setEndpointResultLines(recommendation.detailLines)
        copyEndpointButton.isEnabled = recommendation.recommendedHost != nil
    }

    func setRefreshEnabled(_ enabled: Bool) {
        refreshButton.isEnabled = enabled
    }

    private func setEndpointResultLines(_ lines: [String], isError: Bool = false) {
        endpointResultsUseErrorColor = isError
        endpointResultsStack.arrangedSubviews.forEach { view in
            endpointResultsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, line) in lines.prefix(5).enumerated() {
            let label = NSTextField(labelWithString: line)
            label.font = index == 0
                ? .systemFont(ofSize: 10, weight: .semibold)
                : .systemFont(ofSize: 10, weight: .medium)
            label.alignment = .left
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
            endpointResultsStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: endpointResultsStack.widthAnchor).isActive = true
        }
        applyEndpointResultAppearance()
    }

    private func applyEndpointResultAppearance() {
        let color: NSColor
        if endpointResultsUseErrorColor {
            color = .systemRed
        } else if isDarkAppearance(view.effectiveAppearance) {
            color = NSColor.white.withAlphaComponent(0.58)
        } else {
            color = .secondaryLabelColor
        }

        for case let label as NSTextField in endpointResultsStack.arrangedSubviews {
            label.textColor = color
        }
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, accessibility: String) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility)
        button.image?.isTemplate = true
        button.bezelStyle = .inline
        button.isBordered = false
    }

    private func applyAppearance() {
        if isDarkAppearance(view.effectiveAppearance) {
            let primary = NSColor.white.withAlphaComponent(0.92)
            let secondary = NSColor.white.withAlphaComponent(0.68)
            let tertiary = NSColor.white.withAlphaComponent(0.56)
            titleLabel.textColor = primary
            summaryLabel.textColor = .systemBlue
            remainingCaption.textColor = secondary
            expiresLabel.textColor = secondary
            schemaLabel.textColor = secondary
            endpointLabel.textColor = primary
            endpointCaption.textColor = secondary
            endpointDomainLabel.textColor = primary
            applyEndpointResultAppearance()
            statusLabel.textColor = tertiary
            refreshButton.contentTintColor = secondary
            copyEndpointButton.contentTintColor = secondary
            quitButton.contentTintColor = secondary
        } else {
            titleLabel.textColor = .labelColor
            summaryLabel.textColor = .systemBlue
            remainingCaption.textColor = .secondaryLabelColor
            expiresLabel.textColor = .secondaryLabelColor
            schemaLabel.textColor = .secondaryLabelColor
            endpointLabel.textColor = .labelColor
            endpointCaption.textColor = .secondaryLabelColor
            endpointDomainLabel.textColor = .labelColor
            applyEndpointResultAppearance()
            statusLabel.textColor = .secondaryLabelColor
            refreshButton.contentTintColor = .secondaryLabelColor
            copyEndpointButton.contentTintColor = .secondaryLabelColor
            quitButton.contentTintColor = .secondaryLabelColor
        }
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func copyEndpointHostPressed() {
        guard let host = currentEndpointHost else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(host, forType: .string)
        setEndpointResultLines(["已复制域名 \(host)"])
    }

    @objc private func quitPressed() {
        onQuit?()
    }

    private static func remainingString(_ value: Double?) -> NSAttributedString {
        guard let value else {
            return NSAttributedString(string: "-")
        }
        let text = "$\(amount(value))"
        let result = NSMutableAttributedString(string: text)
        if let dotRange = text.range(of: ".") {
            let nsRange = NSRange(dotRange.lowerBound..<text.endIndex, in: text)
            result.addAttributes([
                .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: nsRange)
        }
        return result
    }

    private static func amount(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = UsageService()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusPopoverController = StatusPopoverViewController()
    private let statusPanel = UsagePanelWindow(
        contentRect: NSRect(origin: .zero, size: statusPanelSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )

    private let titleLabel = NSTextField(labelWithString: "Codex Usage")
    private let subtitleLabel = NSTextField(labelWithString: "Reads ~/.codex/auth.json and ~/.codex/config.toml")
    private let refreshButton = NSButton(title: "刷新用量", target: nil, action: nil)
    private let dailyRow = UsageMeterView(name: "Daily", symbolName: "clock", color: .systemBlue)
    private let weeklyRow = UsageMeterView(name: "Weekly", symbolName: "calendar", color: .systemIndigo)
    private let monthlyRow = UsageMeterView(name: "Monthly", symbolName: "chart.bar", color: .systemPurple)
    private let expiresLabel = NSTextField(labelWithString: "Expires  -")
    private let endpointTitleLabel = NSTextField(labelWithString: "节点推荐  -")
    private let endpointHostLabel = NSTextField(labelWithString: "域名  -")
    private let endpointDetailLabel = NSTextField(labelWithString: "等待 traceroute")
    private let copyEndpointButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private var isRefreshing = false
    private var refreshSerial = 0
    private var pendingRefreshTasks = 0
    private var currentEndpointHost: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureWindow()
        refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = makeCodexStatusIcon()
            button.imagePosition = .imageLeft
            button.title = " --"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.toolTip = "Codex Usage"
            button.target = self
            button.action = #selector(toggleUsagePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusPopoverController.loadViewIfNeeded()
        statusPanel.contentView = statusPopoverController.view
        statusPanel.isOpaque = false
        statusPanel.backgroundColor = .clear
        statusPanel.hasShadow = true
        statusPanel.level = .statusBar
        statusPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        statusPanel.hidesOnDeactivate = true
        statusPanel.isReleasedWhenClosed = false

        statusPopoverController.onRefresh = { [weak self] in
            self?.refresh()
        }
        statusPopoverController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func configureWindow() {
        window.title = "Codex Usage"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = .systemFont(ofSize: 13)

        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonPressed)
        refreshButton.bezelStyle = .rounded

        expiresLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        endpointTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        endpointTitleLabel.lineBreakMode = .byTruncatingMiddle
        endpointHostLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        endpointHostLabel.textColor = .labelColor
        endpointHostLabel.lineBreakMode = .byTruncatingMiddle
        endpointHostLabel.isSelectable = true
        endpointDetailLabel.font = .systemFont(ofSize: 13)
        endpointDetailLabel.alignment = .left
        endpointDetailLabel.textColor = .secondaryLabelColor
        endpointDetailLabel.maximumNumberOfLines = 5
        endpointDetailLabel.lineBreakMode = .byWordWrapping
        endpointDetailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configureIconButton(copyEndpointButton, symbolName: "doc.on.doc", accessibility: "复制推荐域名")
        copyEndpointButton.target = self
        copyEndpointButton.action = #selector(copyEndpointHostPressed)
        copyEndpointButton.isEnabled = false
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping

        let headerText = NSStackView(views: [titleLabel, subtitleLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 4

        let header = NSStackView(views: [headerText, refreshButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .gravityAreas

        let rows = NSStackView(views: [dailyRow, weeklyRow, monthlyRow])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 10

        let endpointHeader = NSStackView(views: [endpointTitleLabel, copyEndpointButton])
        endpointHeader.orientation = .horizontal
        endpointHeader.alignment = .centerY
        endpointHeader.distribution = .gravityAreas
        endpointHeader.spacing = 8

        let endpointStack = NSStackView(views: [endpointHeader, endpointHostLabel, endpointDetailLabel])
        endpointStack.orientation = .vertical
        endpointStack.alignment = .leading
        endpointStack.spacing = 5

        let mainStack = NSStackView(views: [header, separator(), rows, expiresLabel, endpointStack, statusLabel])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 22
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            mainStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            mainStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -28),
            header.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            rows.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            endpointStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            endpointHeader.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            endpointHostLabel.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            endpointDetailLabel.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            copyEndpointButton.widthAnchor.constraint(equalToConstant: 24),
            copyEndpointButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        window.orderOut(nil)
    }

    @objc private func toggleUsagePanel() {
        guard let button = statusItem.button else {
            return
        }

        if statusPanel.isVisible {
            statusPanel.orderOut(nil)
        } else {
            positionStatusPanel(relativeTo: button)
            statusPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refresh()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        statusPanel.orderOut(nil)
    }

    private func positionStatusPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            return
        }

        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = statusPanel.frame.size
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let idealX = buttonFrame.midX - panelSize.width / 2
        let clampedX = min(max(idealX, screenFrame.minX + 8), screenFrame.maxX - panelSize.width - 8)
        let idealY = buttonFrame.minY - panelSize.height - 6
        let clampedY = max(idealY, screenFrame.minY + 8)

        statusPanel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, accessibility: String) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility)
        button.image?.isTemplate = true
        button.bezelStyle = .rounded
    }

    @objc private func refreshButtonPressed() {
        refresh()
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }
        refreshSerial += 1
        let serial = refreshSerial
        isRefreshing = true
        pendingRefreshTasks = 2
        setRefreshEnabled(false)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在读取本地配置并查询用量..."
        statusPopoverController.setLoading()
        setEndpointChecking()
        statusPopoverController.setEndpointChecking()

        service.loadUsage { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                guard self.refreshSerial == serial else {
                    return
                }
                defer {
                    self.finishRefreshTask(serial: serial)
                }

                switch result {
                case .success(let snapshot):
                    self.update(snapshot)
                    self.statusPopoverController.update(snapshot)
                    self.updateStatusItem(with: snapshot)
                    self.statusLabel.textColor = .secondaryLabelColor
                    self.statusLabel.stringValue = snapshot.note ?? "已更新。"
                case .failure(let error):
                    self.statusPopoverController.setError(error)
                    self.statusLabel.textColor = .systemRed
                    self.statusLabel.stringValue = "错误: \(error.localizedDescription)"
                }
            }
        }

        service.loadEndpointRecommendation { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                guard self.refreshSerial == serial else {
                    return
                }
                defer {
                    self.finishRefreshTask(serial: serial)
                }

                switch result {
                case .success(let recommendation):
                    self.update(recommendation)
                    self.statusPopoverController.update(recommendation)
                case .failure(let error):
                    self.setEndpointError(error)
                    self.statusPopoverController.setEndpointError(error)
                }
            }
        }
    }

    private func update(_ snapshot: UsageSnapshot) {
        dailyRow.update(usage: snapshot.dailyUsage, limit: snapshot.dailyLimit)
        weeklyRow.update(usage: snapshot.weeklyUsage, limit: snapshot.weeklyLimit)
        monthlyRow.update(usage: snapshot.monthlyUsage, limit: snapshot.monthlyLimit)
        expiresLabel.stringValue = "Expires  \(snapshot.expiresAt)"
    }

    private func setEndpointChecking() {
        currentEndpointHost = nil
        endpointTitleLabel.stringValue = "节点推荐  探测中"
        endpointTitleLabel.textColor = .labelColor
        endpointHostLabel.stringValue = "域名  -"
        copyEndpointButton.isEnabled = false
        endpointDetailLabel.textColor = .secondaryLabelColor
        endpointDetailLabel.stringValue = "正在读取 /api/v1/settings/public 并运行 traceroute..."
    }

    private func setEndpointError(_ error: Error) {
        currentEndpointHost = nil
        endpointTitleLabel.stringValue = "节点推荐  暂不可用"
        endpointTitleLabel.textColor = .labelColor
        endpointHostLabel.stringValue = "域名  -"
        copyEndpointButton.isEnabled = false
        endpointDetailLabel.textColor = .systemRed
        endpointDetailLabel.stringValue = error.localizedDescription
    }

    private func update(_ recommendation: EndpointRecommendation) {
        currentEndpointHost = recommendation.recommendedHost
        endpointTitleLabel.stringValue = recommendation.headline
        endpointTitleLabel.textColor = .labelColor
        endpointHostLabel.stringValue = "域名  \(recommendation.recommendedHost ?? "-")"
        endpointDetailLabel.textColor = .secondaryLabelColor
        endpointDetailLabel.stringValue = recommendation.detail
        copyEndpointButton.isEnabled = recommendation.recommendedHost != nil
    }

    private func finishRefreshTask(serial: Int) {
        guard refreshSerial == serial else {
            return
        }
        pendingRefreshTasks = max(0, pendingRefreshTasks - 1)
        if pendingRefreshTasks == 0 {
            isRefreshing = false
            setRefreshEnabled(true)
        }
    }

    private func setRefreshEnabled(_ enabled: Bool) {
        refreshButton.isEnabled = enabled
        statusPopoverController.setRefreshEnabled(enabled)
    }

    @objc private func copyEndpointHostPressed() {
        guard let host = currentEndpointHost else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(host, forType: .string)
        endpointDetailLabel.textColor = .secondaryLabelColor
        endpointDetailLabel.stringValue = "已复制域名 \(host)"
    }

    private func updateStatusItem(with snapshot: UsageSnapshot) {
        let remaining = snapshot.dailyLimit > 0
            ? max(0, min(100, 100 - snapshot.dailyUsage / snapshot.dailyLimit * 100))
            : 0
        statusItem.button?.title = " \(Int(remaining.rounded()))%"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
