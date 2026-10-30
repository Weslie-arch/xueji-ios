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
    var corner: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: corner))
            } else {
                content
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: corner))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 0.6)
                    )
            }
        }
    }
}

// MARK: - 渐变背景（全局氛围底色）
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.92),
                                    Color(red: 0.55, green: 0.40, blue: 0.92),
                                    Color(red: 0.72, green: 0.45, blue: 0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.12)).frame(width: 320).blur(radius: 70)
                .offset(x: -110, y: -260)
            Circle().fill(.white.opacity(0.09)).frame(width: 260).blur(radius: 60)
                .offset(x: 130, y: 340)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 根视图：未登录 → 登录页；已登录 → 液态玻璃 TabView
struct RootView: View {
    @State private var loggedIn = false
    @State private var checking = true

    var body: some View {
        ZStack {
            AuroraBackground()
            if checking {
                VStack(spacing: 14) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 52)).foregroundStyle(.white)
                    ProgressView().tint(.white)
                    Text("正在连接学迹…").font(.footnote).foregroundStyle(.white.opacity(0.85))
                }
            } else if loggedIn {
                MainTabView()
            } else {
                LoginView { loggedIn = true }
            }
        }
        .task {
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
        VStack(spacing: 0) {
            Spacer()
            // 品牌
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 92, height: 92)
                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 42, weight: .semibold)).foregroundStyle(.white)
                }
                Text("学迹")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("把分散的设备，连成一条成长轨迹")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            // 玻璃登录卡
            GlassCard(corner: 28) {
                VStack(spacing: 16) {
                    LabeledField(title: "服务器", text: $server, placeholder: "https://xueji.misktool.top")
                    LabeledField(title: "账号", text: $account, placeholder: "手机号 / 账号名")
                    SecureLabeledField(title: "密码", text: $password)
                    if !msg.isEmpty {
                        Text(msg).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        Task { await doLogin() }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.accentColor) }
                            Text(busy ? "登录中…" : "登 录")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .disabled(busy || account.isEmpty || password.isEmpty)
                    Text("☁️ 登录后自动同步云端全部数据")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .padding(.horizontal, 26)
            Spacer()
            Spacer()
        }
    }

    private func doLogin() async {
        busy = true
        msg = ""
        APIClient.shared.baseString = server
        defer { busy = false }
        do {
            _ = try await APIClient.shared.login(account: account, password: password)
            await DataStore.shared.refresh(force: true) // 登录后立刻预载，进首页无需等待
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
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.quaternary, in: .rect(cornerRadius: 12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

struct SecureLabeledField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            SecureField("", text: $text)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.quaternary, in: .rect(cornerRadius: 12))
        }
    }
}

// MARK: - 主界面：系统 TabView（iOS 26 上 tab 栏自动获得官方液态玻璃）
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            GradesView()
                .tabItem { Label("成绩", systemImage: "graduationcap.fill") }
            ChatView()
                .tabItem { Label("AI 助手", systemImage: "bubble.left.and.bubble.right.fill") }
            MineView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
        }
        .tint(.indigo)
        .task { await DataStore.shared.refresh() } // 进主界面拉一次，之后全部走缓存
    }
}

// MARK: - 首页：问候 + 头像 + 统计 + 各科分析
struct HomeView: View {
    @ObservedObject private var store = DataStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if store.loading && !store.loaded {
                        ProgressView("正在同步云端数据…").padding(.top, 40)
                    } else if !store.loadError.isEmpty && !store.loaded {
                        errorCard
                    } else if store.exams.isEmpty {
                        emptyCard
                    } else {
                        statGrid
                        subjectCard
                        recentCard
                    }
                }
                .padding(.horizontal)
                .padding(.vertical)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .refreshable { await store.refresh(force: true) }
        }
    }

    // 顶部问候 + 头像
    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.greeting())，\(store.displayName)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(store.loaded ? "☁️ 云端数据已同步" : "正在连接云端…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            AvatarView(name: store.displayName, size: 48)
        }
        .padding(.top, 6)
    }

    // 2×2 统计
    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            gridStat(icon: "chart.line.uptrend.xyaxis", title: "平均得分率", value: "\(store.avgPercent)%")
            gridStat(icon: "number", title: "平均分", value: store.avgScore > 0 ? String(format: "%.1f", store.avgScore) : "—")
            gridStat(icon: "doc.text.fill", title: "考试次数", value: "\(store.exams.count)")
            gridStat(icon: "star.fill", title: "最强科目", value: store.bestSubject?.name ?? "—")
        }
    }

    private func gridStat(icon: String, title: String, value: String) -> some View {
        GlassCard {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.body).foregroundStyle(.indigo)
                Text(value).font(.title3.weight(.heavy)).minimumScaleFactor(0.6).lineLimit(1)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 8)
        }
    }

    // 各科平均得分率
    private var subjectCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("各科平均得分率", systemImage: "chart.bar.fill")
                    .font(.headline)
                ForEach(Array(store.subjects.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(s.name).font(.subheadline)
                            Spacer()
                            Text("\(s.avgPercent)%").font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(s.avgPercent >= 85 ? .green : (s.avgPercent >= 60 ? .orange : .red))
                        }
                        ProgressView(value: Double(s.avgPercent), total: 100)
                            .tint(s.avgPercent >= 85 ? .green : (s.avgPercent >= 60 ? .orange : .red))
                    }
                }
            }
            .padding(18)
        }
    }

    // 最近考试
    private var recentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("最近考试", systemImage: "clock.fill")
                    .font(.headline)
                ForEach(Array(store.recentExams.enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fmtDate(e.date)).font(.subheadline.weight(.semibold))
                        Text(subjectLine(e)).font(.caption).foregroundStyle(.secondary)
                    }
                    if e.id != store.recentExams.last?.id { Divider() }
                }
            }
            .padding(18)
        }
    }

    private var errorCard: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark").font(.title2)
                Text(store.loadError).font(.footnote).multilineTextAlignment(.center)
                Button("重试") { Task { await store.refresh(force: true) } }.buttonStyle(.bordered)
            }
            .padding(18).frame(maxWidth: .infinity)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.white.opacity(0.8))
            Text("云端还没有考试记录").font(.subheadline).foregroundStyle(.white)
            Text("在电脑网页端录入成绩后，这里会自动出现")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.top, 60)
    }
}

// MARK: - 成绩
struct GradesView: View {
    @ObservedObject private var store = DataStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.loading && !store.loaded {
                    ProgressView("正在加载…")
                } else if !store.loadError.isEmpty && !store.loaded {
                    VStack(spacing: 10) {
                        Text(store.loadError).font(.footnote).multilineTextAlignment(.center)
                        Button("重试") { Task { await store.refresh(force: true) } }.buttonStyle(.bordered)
                    }
                } else if store.exams.isEmpty {
                    ContentUnavailableView("暂无成绩", systemImage: "graduationcap", description: Text("电脑端录入后会同步到这里"))
                } else {
                    List {
                        ForEach(Array(store.exams.enumerated()), id: \.offset) { _, e in
                            Section(e.date.isEmpty ? "未标日期" : fmtDate(e.date)) {
                                ForEach(Array((e.scores ?? []).enumerated()), id: \.offset) { _, s in
                                    HStack {
                                        Text(s.n ?? "科目").font(.subheadline)
                                        Spacer()
                                        Text(scoreText(s)).font(.subheadline.weight(.semibold).monospacedDigit())
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.clear)
            .navigationTitle("成绩")
            .refreshable { await store.refresh(force: true) }
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
                                        .background(m.me ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(.ultraThinMaterial),
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
    @ObservedObject private var store = DataStore.shared
    @State private var server = APIClient.shared.baseString
    @State private var balance: Double = 0
    @State private var savedTip = ""

    var body: some View {
        NavigationStack {
            List {
                // 个人名片
                Section {
                    HStack(spacing: 14) {
                        AvatarView(name: store.displayName, size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.displayName).font(.headline)
                            Text("☁️ 云端同步已就绪 · \(store.exams.count) 次考试")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("账号") {
                    LabeledRow(title: "登录账号", value: APIClient.shared.account.isEmpty ? "—" : APIClient.shared.account)
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
                    LabeledRow(title: "版本", value: "1.1.0")
                    LabeledRow(title: "界面", value: "iOS 26 液态玻璃")
                    LabeledRow(title: "数据", value: "实时云端同步（按账号隔离）")
                }
                Section {
                    Button("退出登录", role: .destructive) {
                        Task {
                            await APIClient.shared.logout()
                            NotificationCenter.default.post(name: .xjLogout, object: nil)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
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
