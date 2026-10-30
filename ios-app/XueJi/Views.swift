import SwiftUI

// MARK: - 入口
@main
struct XueJiApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

// MARK: - 液态玻璃卡片（iOS 26 官方 glassEffect；旧系统回退毛玻璃）
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
            } else {
                content
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.6)
                    )
            }
        }
    }
}

// MARK: - 根视图：未登录 → 登录页；已登录 → 液态玻璃 TabView
struct RootView: View {
    @State private var loggedIn = false
    @State private var checking = true

    var body: some View {
        Group {
            if checking {
                ProgressView("正在连接学迹…")
            } else if loggedIn {
                MainTabView()
            } else {
                LoginView { loggedIn = true }
            }
        }
        .task {
            // 尝试用已有 Cookie 恢复会话（自动登录）
            let ok = await APIClient.shared.restoreSession()
            loggedIn = ok
            checking = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .xjLogout)) { _ in
            loggedIn = false
        }
    }
}

// MARK: - 登录页
struct LoginView: View {
    var onLogin: () -> Void

    @State private var server = APIClient.shared.baseString
    @State private var account = ""
    @State private var password = ""
    @State private var busy = false
    @State private var msg = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 6) {
                Text("学迹")
                    .font(.system(size: 44, weight: .heavy))
                Text("把分散的设备，连成一条成长轨迹")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            GlassCard {
                VStack(spacing: 14) {
                    LabeledField(title: "服务器", text: $server, placeholder: "https://xueji.misktool.top")
                    LabeledField(title: "账号", text: $account, placeholder: "手机号 / 账号名")
                    SecureLabeledField("密码", text: $password)
                    if !msg.isEmpty {
                        Text(msg).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        Task { await doLogin() }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "登录中…" : "登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || account.isEmpty || password.isEmpty)
                }
                .padding(18)
            }
            .padding(.horizontal, 26)
            Spacer()
            Spacer()
        }
        .padding()
    }

    private func doLogin() async {
        busy = true
        msg = ""
        APIClient.shared.baseString = server
        defer { busy = false }
        do {
            _ = try await APIClient.shared.login(account: account, password: password)
            onLogin()
        } catch {
            msg = error.localizedDescription
        }
    }
}

struct LabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

struct SecureLabeledField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            SecureField("", text: $text)
                .textFieldStyle(.plain)
        }
    }
}

// MARK: - 主界面：系统 TabView（iOS 26 上 tab 栏自动获得官方液态玻璃）
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("概览", systemImage: "chart.bar.fill") }
            GradesView()
                .tabItem { Label("成绩", systemImage: "graduationcap.fill") }
            ChatView()
                .tabItem { Label("AI 助手", systemImage: "bubble.left.and.bubble.right.fill") }
            MineView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
        }
    }
}

// MARK: - 概览
struct HomeView: View {
    @State private var exams: [Exam] = []
    @State private var subjects: [SubjectStat] = []
    @State private var loading = false
    @State private var err = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if loading { ProgressView("正在同步云端数据…").padding(.top, 40) }
                    if !err.isEmpty {
                        GlassCard {
                            VStack(spacing: 8) {
                                Image(systemName: "wifi.exclamationmark").font(.title2)
                                Text(err).font(.footnote).multilineTextAlignment(.center)
                                Button("重试") { Task { await load() } }.buttonStyle(.bordered)
                            }
                            .padding(18).frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal)
                    }
                    if !exams.isEmpty {
                        HStack(spacing: 14) {
                            StatCard(title: "考试次数", value: "\(exams.count)")
                            StatCard(title: "总体得分率", value: avgPercentText)
                        }
                        .padding(.horizontal)

                        if !subjects.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("各科平均得分率").font(.headline)
                                    ForEach(subjects) { s in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(s.name).font(.subheadline)
                                                Spacer()
                                                Text("\(s.avgPercent)%").font(.subheadline.weight(.semibold))
                                            }
                                            ProgressView(value: Double(s.avgPercent), total: 100)
                                                .tint(.accentColor)
                                        }
                                    }
                                }
                                .padding(18)
                            }
                            .padding(.horizontal)
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("最近考试").font(.headline)
                                ForEach(Array(exams.prefix(3).enumerated()), id: \.offset) { _, e in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(fmtDate(e.date)).font(.subheadline.weight(.semibold))
                                        Text(subjectLine(e)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Divider()
                                }
                            }
                            .padding(18)
                        }
                        .padding(.horizontal)
                    } else if !loading && err.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                            Text("云端还没有考试记录").font(.subheadline).foregroundStyle(.secondary)
                            Text("在电脑网页端录入成绩后，这里会自动出现")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.top, 60)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("学迹")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private var avgPercentText: String {
        var sum = 0.0, full = 0.0
        for e in exams { for s in e.scores ?? [] {
            if let sc = s.score?.value, let f = s.full?.value, f > 0 { sum += sc; full += f }
        } }
        return full > 0 ? "\(Int(sum / full * 100))%" : "—"
    }

    private func load() async {
        loading = true; err = ""
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
            await MainActor.run {
                exams = ex
                subjects = stats
            }
        } catch {
            await MainActor.run { err = error.localizedDescription }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var body: some View {
        GlassCard {
            VStack(spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2.weight(.bold))
            }
            .frame(maxWidth: .infinity).padding(16)
        }
    }
}

// MARK: - 成绩
struct GradesView: View {
    @State private var exams: [ExamRow] = []
    @State private var loading = false
    @State private var err = ""

    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView() }
                else if !err.isEmpty {
                    VStack(spacing: 10) {
                        Text(err).font(.footnote).multilineTextAlignment(.center)
                        Button("重试") { Task { await load() } }.buttonStyle(.bordered)
                    }
                } else if exams.isEmpty {
                    ContentUnavailableView("暂无成绩", systemImage: "graduationcap", description: Text("电脑端录入后会同步到这里"))
                } else {
                    List {
                        ForEach(exams) { e in
                            Section(e.date.isEmpty ? "未标日期" : fmtDate(e.date)) {
                                ForEach(Array((e.scores).enumerated()), id: \.offset) { _, s in
                                    HStack {
                                        Text(s.n ?? "科目").font(.subheadline)
                                        Spacer()
                                        Text(scoreText(s)).font(.subheadline.weight(.semibold).monospacedDigit())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("成绩")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true; err = ""
        defer { loading = false }
        do {
            let st = try await APIClient.shared.fetchState()
            let rows = (st.exams ?? [])
                .sorted { ($0.date ?? "") > ($1.date ?? "") }
                .map { ExamRow(id: $0.id ?? UUID().uuidString, date: $0.date ?? "", scores: $0.scores ?? []) }
            await MainActor.run { exams = rows }
        } catch {
            await MainActor.run { err = error.localizedDescription }
        }
    }
}

// MARK: - AI 助手（服务端统一转发，Key 不经过 App）
struct ChatView: View {
    struct Msg: Identifiable { let id = UUID(); let me: Bool; var text: String }

    @State private var msgs: [Msg] = []
    @State private var input = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if msgs.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle).foregroundStyle(.secondary)
                                    Text("问我任何学习问题").font(.subheadline).foregroundStyle(.secondary)
                                    Text("AI 已了解你的全部学习数据，会结合你的情况回答")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.top, 80)
                            }
                            ForEach(msgs) { m in
                                HStack {
                                    if m.me { Spacer() }
                                    Text(m.text)
                                        .padding(12)
                                        .background(m.me ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial),
                                                    in: .rect(cornerRadius: 16))
                                        .foregroundStyle(m.me ? Color.white : Color.primary)
                                        .frame(maxWidth: 300, alignment: m.me ? .trailing : .leading)
                                        .id(m.id)
                                    if !m.me { Spacer() }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: msgs.count) { _, _ in
                        if let last = msgs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    TextField("输入问题…", text: $input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(10)
                        .background(.quaternary, in: .rect(cornerRadius: 14))
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .navigationTitle("AI 助手")
        }
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        input = ""
        msgs.append(Msg(me: true, text: text))
        let placeholderId = UUID()
        msgs.append(Msg(me: false, text: "…"))
        busy = true
        defer { busy = false }
        do {
            let history: [AIChatMessage] = msgs.filter { $0.text != "…" }.suffix(20)
                .map { AIChatMessage(role: $0.me ? "user" : "assistant", content: $0.text) }
            let out = try await APIClient.shared.aiChat(messages: history)
            if let i = msgs.firstIndex(where: { $0.id == placeholderId }) {
                msgs[i].text = out
            }
        } catch {
            if let i = msgs.firstIndex(where: { $0.id == placeholderId }) {
                msgs[i].text = "❌ " + error.localizedDescription
            }
        }
    }
}

// MARK: - 我的
struct MineView: View {
    @State private var server = APIClient.shared.baseString
    @State private var balance: Double = 0
    @State private var savedTip = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    LabeledRow(title: "账号", value: APIClient.shared.nickname.isEmpty ? APIClient.shared.account : APIClient.shared.nickname)
                    LabeledRow(title: "AI 余额", value: "¥" + String(format: "%.2f", balance))
                }
                Section("服务器") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("地址").font(.caption).foregroundStyle(.secondary)
                        TextField("https://xueji.misktool.top", text: $server)
                            .textFieldStyle(.plain)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !savedTip.isEmpty { Text(savedTip).font(.caption).foregroundStyle(.green) }
                    Button("保存地址并重连") {
                        APIClient.shared.baseString = server
                        savedTip = "已保存，重新登录后生效"
                    }
                }
                Section("关于") {
                    LabeledRow(title: "版本", value: "1.0.0")
                    LabeledRow(title: "界面", value: "iOS 26 液态玻璃")
                    LabeledRow(title: "数据", value: "实时云端同步（按账号隔离）")
                }
                Section {
                    Button("退出登录", role: .destructive) {
                        Task {
                            await APIClient.shared.logout()
                            // 回到登录页
                            NotificationCenter.default.post(name: .xjLogout, object: nil)
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .task { balance = await APIClient.shared.fetchBalance() }
        }
    }
}

struct LabeledRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
}

// MARK: - 工具
extension Notification.Name {
    static let xjLogout = Notification.Name("xjLogout")
}

func fmtDate(_ s: String?) -> String {
    guard let s, !s.isEmpty else { return "未标日期" }
    return s
}

func subjectLine(_ e: Exam) -> String {
    let parts = (e.scores ?? []).compactMap { s -> String? in
        guard let n = s.n, let sc = s.score?.value else { return nil }
        if let f = s.full?.value, f > 0 { return "\(n) \(Int(sc))/\(Int(f))" }
        return "\(n) \(Int(sc))"
    }
    return parts.isEmpty ? "无科目明细" : parts.joined(separator: " · ")
}

func scoreText(_ s: ScoreItem) -> String {
    guard let sc = s.score?.value else { return "—" }
    if let f = s.full?.value, f > 0 { return "\(Int(sc)) / \(Int(f))" }
    return "\(Int(sc))"
}
