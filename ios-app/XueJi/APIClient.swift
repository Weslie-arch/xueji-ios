import Foundation

enum APIMode: String {
    case php, node, unknown

    var label: String {
        switch self {
        case .php: return "PHP 后端"
        case .node: return "Node 后端"
        case .unknown: return "未连接"
        }
    }
}

/// 学迹 API 客户端
/// - 登录后 URLSession 自动携带 xj_token Cookie（与网页端同一套会话）
/// - 自动探测 PHP / Node 两种后端（与网页端 boot 逻辑一致）
final class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published var mode: APIMode = .unknown
    @Published var account: String = ""
    @Published var nickname: String = ""
    @Published var balance: Double = 0

    private let baseKey = "xj_server_base"

    var baseString: String {
        get { UserDefaults.standard.string(forKey: baseKey) ?? "https://xueji.misktool.top" }
        set {
            var s = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            while s.hasSuffix("/") { s.removeLast() }
            UserDefaults.standard.set(s, forKey: baseKey)
        }
    }

    private var baseURL: URL? { URL(string: baseString) }

    // MARK: - 路径

    /// 按后端模式拼 URL。path 例："login" / "state" / "balance"
    private func endpoint(_ path: String) throws -> URL {
        guard let base = baseURL else { throw APIError.badURL }
        switch mode {
        case .php:
            var comps = URLComponents(url: base.appendingPathComponent("api.php"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "action", value: path)]
            return comps.url!
        default:
            return base.appendingPathComponent("api/" + path)
        }
    }

    // MARK: - 探测

    /// 探测 PHP → Node（与网页端顺序一致），成功后设置 mode
    func detect() async throws {
        if let base = baseURL {
            // 先试 PHP
            var comps = URLComponents(url: base.appendingPathComponent("api.php"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "action", value: "ping")]
            if let ping = try? await getJSON(comps.url!, as: PingResp.self, timeout: 8),
               ping.ok == true, ping.mode == "server" {
                await MainActor.run { self.mode = .php }
                return
            }
            // 再试 Node
            if let ping = try? await getJSON(base.appendingPathComponent("api/ping"), as: PingResp.self, timeout: 8),
               ping.ok == true, ping.mode == "server" {
                await MainActor.run { self.mode = .node }
                return
            }
        }
        throw APIError.serverNotFound
    }

    // MARK: - 登录会话

    func login(account: String, password: String) async throws -> String {
        try await detect()
        struct Body: Codable { let phone: String; let pass: String }
        let resp = try await postJSON(endpoint("login"), body: Body(phone: account, pass: password), as: LoginResp.self)
        if resp.ok == true, let acc = resp.account {
            await MainActor.run { self.account = acc }
            _ = try? await refreshMe()
            return acc
        }
        throw APIError.message(resp.error ?? resp.message ?? "登录失败")
    }

    func refreshMe() async throws -> Bool {
        let me = try await getJSON(try endpoint("me"), as: MeResp.self)
        guard me.ok == true else { return false }
        await MainActor.run {
            self.account = me.account ?? me.phone ?? self.account
            self.nickname = me.nickname ?? ""
        }
        return true
    }

    func restoreSession() async -> Bool {
        guard (try? await detect()) != nil else { return false }
        return (try? await refreshMe()) ?? false
    }

    func logout() async {
        if let url = try? endpoint("logout") {
            _ = try? await postJSON(url, body: Optional<Int>.none, as: MeResp.self)
        }
        await MainActor.run {
            self.account = ""
            self.nickname = ""
            self.balance = 0
        }
    }

    // MARK: - 数据（宽松 JSONSerialization 解析，免疫字段类型差异）

    /// 读取云端 state（原始字典）；请求自带 30 秒超时看门狗，绝不无限等待
    func fetchRawState() async throws -> [String: Any] {
        let url = try endpoint("state")
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? String, (obj["ok"] as? Bool) != true {
                throw APIError.message(e)
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, "读取失败")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }
        guard (obj["ok"] as? Bool) == true else {
            throw APIError.message("登录会话已过期，请退出后重新登录")
        }
        guard let st = obj["state"] as? [String: Any] else {
            return ["exams": [Any]()]
        }
        return st
    }

    /// 上传云端 state（整包写回，与网页端 save 同一接口）；24 秒超时
    func pushRawState(_ raw: [String: Any]) async throws {
        let url = try endpoint("state")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 40
        req.httpBody = try JSONSerialization.data(withJSONObject: raw)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? String {
                throw APIError.message(e)
            }
            if (obj["ok"] as? Bool) == true { return }
        }
        throw APIError.message("服务器未确认保存")
    }

    func fetchBalance() async -> Double {
        if let b = try? await getJSON(try endpoint("balance"), as: BalanceResp.self), b.ok == true {
            let v = b.balance?.value ?? 0
            await MainActor.run { self.balance = v }
            return v
        }
        return 0
    }

    // MARK: - AI 聊天（服务端转发，Key 不经过 App）

    func aiChat(messages: [AIChatMessage]) async throws -> String {
        struct Body: Codable { let messages: [AIChatMessage]; let kind: String }
        let url = try endpoint("ai")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        req.httpBody = try JSONEncoder().encode(Body(messages: messages, kind: "chat"))

        let (data, resp) = try await URLSession.shared.data(for: req)
        let mime = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""

        // PHP 后端：SSE 流（一次性收完再解析）；Node 后端：普通 JSON
        if mime.contains("text/event-stream"), let text = String(data: data, encoding: .utf8) {
            var out = ""
            var errMsg: String?
            for line in text.split(separator: "\n") {
                let l = line.trimmingCharacters(in: .whitespaces)
                guard l.hasPrefix("data:") else { continue }
                let payload = l.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let d = payload.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                if let e = obj["error"] as? String { errMsg = e; continue }
                if let done = obj["done"] as? Bool, done { continue }
                if let choices = obj["choices"] as? [[String: Any]],
                   let ch = choices.first,
                   let delta = ch["delta"] as? [String: Any],
                   let c = delta["content"] as? String { out += c }
            }
            if let e = errMsg { throw APIError.message(e) }
            if out.isEmpty { throw APIError.message("AI 未返回内容") }
            return out
        }

        // JSON：{ok, content, balance} 或 {ok:false, error}
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? String { throw APIError.message(e) }
            if let c = obj["content"] as? String, !c.isEmpty { return c }
        }
        throw APIError.message("AI 响应异常")
    }

    // MARK: - 基础请求

    private func getJSON<T: Decodable>(_ url: URL, as type: T.Type, timeout: Double = 30) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        return try decode(data, status: http.statusCode)
    }

    private func postJSON<B: Encodable, T: Decodable>(_ url: URL, body: B?, as type: T.Type, timeout: Double = 60) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        if let b = body { req.httpBody = try JSONEncoder().encode(b) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        return try decode(data, status: http.statusCode)
    }

    private func decode<T: Decodable>(_ data: Data, status: Int) throws -> T {
        let dec = JSONDecoder()
        if let obj = try? dec.decode(T.self, from: data) { return obj }
        // 后端可能返回 401/403 + {ok:false,error:...}
        if let err = try? JSONDecoder().decode(AIErrorResp.self, from: data), let e = err.error {
            throw APIError.http(status, e)
        }
        throw APIError.badResponse
    }
}

enum APIError: LocalizedError {
    case badURL
    case serverNotFound
    case badResponse
    case http(Int, String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务器地址不正确"
        case .serverNotFound: return "连不上学迹服务器，请检查地址与网络"
        case .badResponse: return "服务器响应异常"
        case .http(let code, let msg): return msg + "（\(code)）"
        case .message(let m): return m
        }
    }
}
