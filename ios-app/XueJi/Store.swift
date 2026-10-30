import Foundation
import SwiftUI

// MARK: - 宽松取值工具（JSONSerialization 值安全转换）
func jDbl(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}

func jStr(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

func jArr(_ v: Any?) -> [[String: Any]] {
    return v as? [[String: Any]] ?? []
}

func jDict(_ v: Any?) -> [String: Any] {
    return v as? [String: Any] ?? [:]
}

func genId() -> String {
    let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
    let r = String(Int.random(in: 1296...46655), radix: 36)
    return t + r
}

// MARK: - 展示模型（手工解析，免疫字段类型差异）
struct ScoreLite: Identifiable {
    let id: Int
    let n: String
    let score: Double?
    let full: Double?

    var percent: Int? {
        guard let s = score, let f = full, f > 0 else { return nil }
        return Int(s / f * 100)
    }
}

struct ExamLite: Identifiable {
    let id: String
    let name: String
    let date: String
    let avgPct: Int
    let scores: [ScoreLite]
    var analysis: String
}

struct WorkItem: Identifiable {
    let id: String
    let title: String
    let date: String
    let subj: String
    let result: String
    let scoreText: String
}

struct ChatMsg: Identifiable {
    let id: Int
    let me: Bool
    let text: String
}

struct SubjectStat: Identifiable {
    let id = UUID()
    let name: String
    let avgPercent: Int
    let count: Int
}

// MARK: - 全局数据仓库：云端 state 的唯一镜像，全部页面共享
@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var loaded = false
    @Published var loading = false
    @Published var loadError = ""
    @Published var saveMsg = "尚未改动"
    @Published var exams: [ExamLite] = []
    @Published var essays: [WorkItem] = []
    @Published var homeworks: [WorkItem] = []
    @Published var quizzes: [WorkItem] = []
    @Published var chatMsgs: [ChatMsg] = []
    @Published var theme = "auto"

    private(set) var raw: [String: Any] = ["exams": []]
    private var saveTask: Task<Void, Never>?

    // ---------- 统计 ----------
    var avgPercent: Int {
        var sum = 0.0
        var full = 0.0
        for e in exams {
            for s in e.scores {
                if let sc = s.score, let f = s.full, f > 0 { sum += sc; full += f }
            }
        }
        if full <= 0 { return 0 }
        return Int(sum / full * 100)
    }

    var avgScore: Double {
        var sum = 0.0
        var n = 0.0
        for e in exams {
            for s in e.scores {
                if let sc = s.score { sum += sc; n += 1 }
            }
        }
        if n <= 0 { return 0 }
        return sum / n
    }

    var bestSubject: String {
        var agg: [String: (Double, Double)] = [:]
        for e in exams {
            for s in e.scores {
                guard let sc = s.score, let f = s.full, f > 0 else { continue }
                let old = agg[s.n] ?? (0, 0)
                agg[s.n] = (old.0 + sc, old.1 + f)
            }
        }
        var best: String?
        var bestP = -1.0
        for (k, v) in agg {
            let p = v.0 / v.1 * 100
            if p > bestP { bestP = p; best = k }
        }
        return best ?? "—"
    }

    var recentExams: [ExamLite] {
        return Array(exams.prefix(3))
    }

    /// 各科平均得分率（首页进度条用）
    var subjects: [SubjectStat] {
        var agg: [String: [Double]] = [:]
        for e in exams {
            for s in e.scores {
                guard let p = s.percent, let _ = s.score else { continue }
                var list = agg[s.n] ?? []
                list.append(Double(p))
                agg[s.n] = list
            }
        }
        var out: [SubjectStat] = []
        for (k, v) in agg {
            let avg = v.reduce(0.0, +) / Double(v.count)
            out.append(SubjectStat(name: k, avgPercent: Int(avg), count: v.count))
        }
        out.sort { $0.avgPercent > $1.avgPercent }
        return out
    }

    var displayName: String {
        let n = APIClient.shared.nickname
        if !n.isEmpty { return n }
        let a = APIClient.shared.account
        return a.isEmpty ? "同学" : a
    }

    // ---------- 读取 ----------
    func refresh(force: Bool = false) async {
        if loaded && !force { return }
        if loading { return }
        loading = true
        loadError = ""
        defer { loading = false }
        do {
            let st = try await APIClient.shared.fetchRawState()
            applyRaw(st)
            loaded = true
        } catch {
            if !loaded {
                loadError = error.localizedDescription
            }
        }
    }

    /// 把云端 state 解析进展示模型（宽松，任何字段异常都不会抛错）
    func applyRaw(_ st: [String: Any]) {
        raw = st
        var exs: [ExamLite] = []
        for e in jArr(st["exams"]) {
            var rows: [ScoreLite] = []
            for (j, s) in jArr(e["scores"]).enumerated() {
                let name = jStr(s["n"])
                rows.append(ScoreLite(id: j, n: name.isEmpty ? "科目" : name, score: jDbl(s["score"]), full: jDbl(s["full"])))
            }
            var avg = Int(jDbl(e["avgPct"]) ?? -1)
            if avg < 0 {
                var sum = 0.0
                var cnt = 0.0
                for r in rows {
                    if let p = r.percent { sum += Double(p); cnt += 1 }
                }
                avg = cnt > 0 ? Int(sum / cnt) : 0
            }
            let ex = ExamLite(id: jStr(e["id"]).isEmpty ? genId() : jStr(e["id"]),
                              name: jStr(e["name"]).isEmpty ? "考试" : jStr(e["name"]),
                              date: jStr(e["date"]),
                              avgPct: avg,
                              scores: rows,
                              analysis: jStr(e["analysis"]))
            exs.append(ex)
        }
        exs.sort { $0.date > $1.date }
        exams = exs

        essays = parseWorks(jArr(st["essays"]))
        homeworks = parseWorks(jArr(st["homeworks"]))
        quizzes = parseQuizList(jArr(st["quizzes"]))

        var cms: [ChatMsg] = []
        let msgs = jArr(jDict(st["chat"])["msgs"])
        for (i, m) in msgs.enumerated() {
            let role = jStr(m["role"])
            cms.append(ChatMsg(id: i, me: role == "user", text: jStr(m["content"])))
        }
        chatMsgs = cms

        let set = jDict(st["settings"])
        let t = jStr(set["theme"])
        theme = t.isEmpty ? "auto" : t
    }

    private func parseWorks(_ list: [[String: Any]]) -> [WorkItem] {
        var out: [WorkItem] = []
        for it in list {
            let w = WorkItem(id: jStr(it["id"]).isEmpty ? genId() : jStr(it["id"]),
                             title: jStr(it["title"]).isEmpty ? "未命名" : jStr(it["title"]),
                             date: jStr(it["date"]),
                             subj: jStr(it["subj"]),
                             result: jStr(it["result"]),
                             scoreText: jStr(it["score"]))
            out.append(w)
        }
        return out
    }

    private func parseQuizList(_ list: [[String: Any]]) -> [WorkItem] {
        var out: [WorkItem] = []
        for it in list {
            var title = jStr(it["topic"])
            if title.isEmpty { title = "练习" }
            let sub = jStr(it["subj"])
            let label = sub.isEmpty ? title : sub + " · " + title
            let w = WorkItem(id: jStr(it["id"]).isEmpty ? genId() : jStr(it["id"]),
                             title: label,
                             date: jStr(it["date"]),
                             subj: sub,
                             result: jStr(it["content"]),
                             scoreText: jStr(it["diff"]))
            out.append(w)
        }
        return out
    }

    // ---------- 写入（改 raw → 重算 → 防抖上传） ----------
    func addExam(name: String, date: String, rows: [(String, Double, Double)]) {
        var arr = jArr(raw["exams"])
        var items: [[String: Any]] = []
        var sum = 0.0
        for r in rows {
            items.append(["n": r.0, "score": r.1, "full": r.2])
            sum += r.1 / max(r.2, 1) * 100
        }
        let avg = rows.isEmpty ? 0 : Int(sum / Double(rows.count))
        let ex: [String: Any] = ["id": genId(), "name": name, "date": date, "scores": items, "avgPct": avg, "images": [Any]()]
        arr.insert(ex, at: 0)
        raw["exams"] = arr
        applyRaw(raw)
        scheduleSave()
    }

    func setExamAnalysis(id: String, text: String) {
        var arr = jArr(raw["exams"])
        for i in 0..<arr.count {
            if jStr(arr[i]["id"]) == id {
                arr[i]["analysis"] = text
                break
            }
        }
        raw["exams"] = arr
        applyRaw(raw)
        scheduleSave()
    }

    /// 删除考试（offsets 对应当前展示的 exams 排序）
    func deleteExam(at offsets: IndexSet) {
        var ids: [String] = []
        for i in offsets {
            if i < exams.count { ids.append(exams[i].id) }
        }
        if ids.isEmpty { return }
        var arr = jArr(raw["exams"])
        arr.removeAll { e in ids.contains(jStr(e["id"])) }
        raw["exams"] = arr
        applyRaw(raw)
        scheduleSave()
    }

    func addWork(kind: String, title: String, subj: String, text: String, result: String, score: String) {
        let key = kind == "essay" ? "essays" : "homeworks"
        var arr = jArr(raw[key])
        let item: [String: Any] = ["id": genId(), "title": title, "subj": subj, "date": shortToday(), "text": text, "result": result, "score": score, "images": [Any]()]
        arr.insert(item, at: 0)
        raw[key] = arr
        applyRaw(raw)
        scheduleSave()
    }

    func addQuiz(subj: String, topic: String, diff: String, count: Int, content: String) {
        var arr = jArr(raw["quizzes"])
        let item: [String: Any] = ["id": genId(), "subj": subj, "topic": topic, "diff": diff, "count": count, "date": shortToday(), "content": content]
        arr.insert(item, at: 0)
        raw["quizzes"] = arr
        applyRaw(raw)
        scheduleSave()
    }

    func appendChat(me: Bool, text: String) {
        var chat = jDict(raw["chat"])
        var msgs = jArr(chat["msgs"])
        var dict: [String: Any] = ["content": text]
        if me { dict["role"] = "user" } else { dict["role"] = "assistant" }
        msgs.append(dict)
        chat["msgs"] = msgs
        raw["chat"] = chat
        let nextId = (chatMsgs.last?.id ?? -1) + 1
        chatMsgs.append(ChatMsg(id: nextId, me: me, text: text))
        scheduleSave()
    }

    func setTheme(_ t: String) {
        var set = jDict(raw["settings"])
        set["theme"] = t
        raw["settings"] = set
        theme = t
        scheduleSave()
    }

    private func shortToday() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func scheduleSave() {
        saveMsg = "⏳ 正在保存…"
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            await self?.flushSave()
        }
    }

    func flushSave() async {
        let snapshot = raw
        do {
            try await APIClient.shared.pushRawState(snapshot)
            saveMsg = "✅ 已同步到云端"
        } catch {
            saveMsg = "⚠️ 保存失败：" + error.localizedDescription
        }
    }

    func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 5 && h < 11 { return "早上好" }
        if h >= 11 && h < 13 { return "中午好" }
        if h >= 13 && h < 18 { return "下午好" }
        return "晚上好"
    }
}

// MARK: - 头像视图：取名字首字的渐变圆
struct AvatarView: View {
    var name: String
    var size: CGFloat = 44

    private var gradient: LinearGradient {
        let palettes: [[Color]] = [
            [.blue, .indigo], [.purple, .pink], [.orange, .red],
            [.teal, .green], [.indigo, .purple]
        ]
        let idx = abs(name.hashValue) % palettes.count
        return LinearGradient(colors: palettes[idx], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            Circle().fill(gradient)
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 通用小工具
func scoreColor(_ percent: Int) -> Color {
    if percent >= 85 { return .green }
    if percent >= 60 { return .orange }
    return .red
}

func fmtDate(_ s: String?) -> String {
    guard let s, !s.isEmpty else { return "未标日期" }
    return s
}

func scoreText(_ s: ScoreLite) -> String {
    guard let sc = s.score else { return "—" }
    if let f = s.full, f > 0 { return "\(Int(sc)) / \(Int(f))" }
    return "\(Int(sc))"
}

func subjectLine(_ e: ExamLite) -> String {
    var parts: [String] = []
    for s in e.scores {
        guard let sc = s.score else { continue }
        if let f = s.full, f > 0 {
            parts.append("\(s.n) \(Int(sc))/\(Int(f))")
        } else {
            parts.append("\(s.n) \(Int(sc))")
        }
    }
    if parts.isEmpty { return "无科目明细" }
    return parts.joined(separator: " · ")
}

extension Notification.Name {
    static let xjLogout = Notification.Name("xjLogout")
}
