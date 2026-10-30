import Foundation

// MARK: - 宽松数值（成绩/分数后端可能是数字也可能是字符串）
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

// MARK: - 接口响应
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

struct StateResp: Codable {
    let ok: Bool?
    let state: XJState?
    let error: String?
}

// MARK: - 学迹数据（与网页端 state 结构对应）
struct XJState: Codable {
    var exams: [Exam]?
    var essays: [SimpleItem]?
    var homeworks: [SimpleItem]?
}

struct Exam: Codable {
    var id: String?
    var date: String?
    var scores: [ScoreItem]?
}

struct ScoreItem: Codable {
    var n: String?        // 科目名
    var score: LenientDouble?
    var full: LenientDouble?
}

struct SimpleItem: Codable {
    var id: String?
    var date: String?
    var title: String?
    var topic: String?
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

// MARK: - 展示模型
struct SubjectStat: Identifiable {
    let id = UUID()
    let name: String
    let avgPercent: Int
    let count: Int
}

struct ExamRow: Identifiable {
    let id: String
    let date: String
    let scores: [ScoreItem]
}
