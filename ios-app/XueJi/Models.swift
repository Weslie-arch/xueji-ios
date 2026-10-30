import Foundation

// MARK: - 宽松数值（余额等可能是数字或字符串）
struct LenientDouble: Codable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
    init(_ v: Double?) { value = v }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = value { try c.encode(v) } else { try c.encodeNil() }
    }
}

// MARK: - 接口响应（仅简单结构走 Codable；state 一律走 JSONSerialization 宽松解析）
struct PingResp: Codable {
    let ok: Bool?
    let mode: String?
}

struct LoginResp: Codable {
    let ok: Bool?
    let account: String?
    let error: String?
    let message: String?
}

struct MeResp: Codable {
    let ok: Bool?
    let account: String?
    let phone: String?
    let nickname: String?
}

struct BalanceResp: Codable {
    let ok: Bool?
    let balance: LenientDouble?
}

// MARK: - AI
struct AIChatMessage: Codable {
    let role: String
    let content: String
}

struct AIErrorResp: Codable {
    let ok: Bool?
    let error: String?
}
