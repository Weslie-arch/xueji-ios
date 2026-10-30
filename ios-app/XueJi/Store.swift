import Foundation
import SwiftUI

// MARK: - 全局数据仓库：登录后拉一次，全部页面共享缓存，切 Tab 零等待
@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var loaded = false          // 云端数据是否已拉到过
    @Published var loading = false
    @Published var loadError = ""
    @Published var exams: [Exam] = []
    @Published var subjects: [SubjectStat] = []
    @Published var essaysCount = 0
    @Published var homeworksCount = 0

    // 概览统计
    var avgPercent: Int {
        var sum = 0.0, full = 0.0
        for e in exams { for s in e.scores ?? [] {
            if let sc = s.score?.value, let f = s.full?.value, f > 0 { sum += sc; full += f }
        } }
        return full > 0 ? Int(sum / full * 100) : 0
    }
    var avgScore: Double {
        var sum = 0.0, n = 0
        for e in exams { for s in e.scores ?? [] {
            if let sc = s.score?.value { sum += sc; n += 1 }
        } }
        return n > 0 ? sum / Double(n) : 0
    }
    var bestSubject: SubjectStat? { subjects.first }
    var latestDate: String? {
        exams.map { $0.date ?? "" }.filter { !$0.isEmpty }.sorted().last
    }
    var recentExams: [Exam] {
        exams.sorted { ($0.date ?? "") > ($1.date ?? "") }.prefix(3).map { $0 }
    }

    var displayName: String {
        let n = APIClient.shared.nickname
        return n.isEmpty ? (APIClient.shared.account.isEmpty ? "同学" : APIClient.shared.account) : n
    }

    /// 拉取云端数据（已加载且非强制时直接复用缓存，切页面不重复请求）
    func refresh(force: Bool = false) async {
        if loaded && !force { return }
        guard !loading else { return }
        loading = true
        loadError = ""
        defer { loading = false }
        do {
            let st = try await APIClient.shared.fetchState()
            let ex = (st.exams ?? []).sorted { ($0.date ?? "") > ($1.date ?? "") }
            var agg: [String: [Double]] = [:]
            for e in ex { for s in e.scores ?? [] {
                guard let sc = s.score?.value, let f = s.full?.value, f > 0, let n = s.n else { continue }
                agg[n, default: []].append(sc / f * 100)
            } }
            let stats = agg.map { SubjectStat(name: $0.key, avgPercent: Int($0.value.reduce(0, +) / Double($0.value.count)), count: $0.value.count) }
                .sorted { $0.avgPercent > $1.avgPercent }
            exams = ex
            subjects = stats
            essaysCount = st.essays?.count ?? 0
            homeworksCount = st.homeworks?.count ?? 0
            loaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        default: return "晚上好"
        }
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
