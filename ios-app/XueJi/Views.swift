import SwiftUI
import UIKit

// MARK: - 入口
@main
struct XueJiApp: App {
    init() {
        // Tab 栏透明，让极光背景透出来
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

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

// MARK: - 极光渐变背景（全局氛围底色）
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

/// 页面骨架：极光背景 + 内容
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
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
            brandBlock
            Spacer()
            loginCard
            Spacer()
            Spacer()
        }
    }

    private var brandBlock: some View {
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
    }

    private var loginCard: some View {
        GlassCard(corner: 28) {
            VStack(spacing: 16) {
                LabeledField(title: "服务器", text: $server, placeholder: "https://xueji.misktool.top")
                LabeledField(title: "账号", text: $account, placeholder: "手机号 / 账号名")
                SecureLabeledField(title: "密码", text: $password)
                if !msg.isEmpty {
                    Text(msg).font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    Task { await doLogin() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.white) }
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
    }

    private func doLogin() async {
        busy = true
        msg = ""
        APIClient.shared.baseString = server
        defer { busy = false }
        do {
            _ = try await APIClient.shared.login(account: account, password: password)
            await DataStore.shared.refresh(force: true)
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

// MARK: - 主界面：5 Tab（iOS 26 上 tab 栏自动官方液态玻璃）
struct MainTabView: View {
    @ObservedObject private var store = DataStore.shared

    private var scheme: ColorScheme? {
        if store.theme == "light" { return .light }
        if store.theme == "dark" { return .dark }
        return nil
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            GradesView()
                .tabItem { Label("成绩", systemImage: "graduationcap.fill") }
            StudyView()
                .tabItem { Label("学习", systemImage: "book.fill") }
            ChatView()
                .tabItem { Label("AI", systemImage: "bubble.left.and.bubble.right.fill") }
            MineView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
        }
        .tint(.white)
        .preferredColorScheme(scheme)
        .task { await DataStore.shared.refresh() }
    }
}

// MARK: - 首页
struct HomeView: View {
    @ObservedObject private var store = DataStore.shared

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        homeBody
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                }
            }
            .navigationTitle("")
            .refreshable { await store.refresh(force: true) }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.greeting())，\(store.displayName)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("☁️ " + store.saveMsg)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            AvatarView(name: store.displayName, size: 48)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var homeBody: some View {
        if store.loading && !store.loaded {
            loadingCard
        } else if !store.loadError.isEmpty && !store.loaded {
            errorCard
        } else if store.exams.isEmpty {
            emptyCard
        } else {
            statGrid
            quickActions
            subjectCard
            recentCard
        }
    }

    private var loadingCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("正在同步云端数据…").font(.footnote).foregroundStyle(.white)
            }
            .padding(30).frame(maxWidth: .infinity)
        }
    }

    private var errorCard: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(.white)
                Text(store.loadError).font(.footnote).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await store.refresh(force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18).frame(maxWidth: .infinity)
        }
    }

    private var emptyCard: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                Text("云端还没有考试记录").font(.subheadline).foregroundStyle(.white)
                Text("点右上角「+」录入第一次考试吧").font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            .padding(24).frame(maxWidth: .infinity)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            gridStat(icon: "chart.line.uptrend.xyaxis", title: "平均得分率", value: "\(store.avgPercent)%")
            gridStat(icon: "number", title: "平均分", value: store.avgScore > 0 ? String(format: "%.1f", store.avgScore) : "—")
            gridStat(icon: "doc.text.fill", title: "考试次数", value: "\(store.exams.count)")
            gridStat(icon: "star.fill", title: "最强科目", value: store.bestSubject)
        }
    }

    private func gridStat(icon: String, title: String, value: String) -> some View {
        GlassCard {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.body).foregroundStyle(.white)
                Text(value).font(.title3.weight(.heavy)).foregroundStyle(.white)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(title).font(.caption2).foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 8)
        }
    }

    private var quickActions: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("快捷功能", systemImage: "bolt.fill").font(.headline).foregroundStyle(.white)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    NavigationLink { AddExamForm() } label: { quickBtn(icon: "plus.circle.fill", label: "录入考试") }
                    NavigationLink { EssayPane() } label: { quickBtn(icon: "text.book.closed.fill", label: "作文批改") }
                    NavigationLink { HomeworkPane() } label: { quickBtn(icon: "checklist", label: "作业批改") }
                    NavigationLink { QuizPane() } label: { quickBtn(icon: "questionmark.circle.fill", label: "题目练习") }
                }
            }
            .padding(18)
        }
    }

    private func quickBtn(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.14), in: .rect(cornerRadius: 14))
    }

    private var subjectCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("各科平均得分率", systemImage: "chart.bar.fill")
                    .font(.headline).foregroundStyle(.white)
                ForEach(Array(store.subjects.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(s.name).font(.subheadline).foregroundStyle(.white)
                            Spacer()
                            Text("\(s.avgPercent)%").font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        ProgressView(value: Double(s.avgPercent), total: 100)
                            .tint(scoreColor(s.avgPercent))
                    }
                }
            }
            .padding(18)
        }
    }

    private var recentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("最近考试", systemImage: "clock.fill")
                    .font(.headline).foregroundStyle(.white)
                ForEach(Array(store.recentExams.enumerated()), id: \.offset) { idx, e in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.name + " · " + fmtDate(e.date))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text(subjectLine(e)).font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                    if idx < store.recentExams.count - 1 { Divider() }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 成绩：考试列表 + 录入 + 详情（AI 分析）
struct GradesView: View {
    @ObservedObject private var store = DataStore.shared
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Screen {
                gradesList
            }
            .navigationTitle("成绩")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus").foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddExamView() }
        }
    }

    @ViewBuilder
    private var gradesList: some View {
        if store.loading && !store.loaded {
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("正在加载…").font(.footnote).foregroundStyle(.white)
            }
        } else if !store.loadError.isEmpty && !store.loaded {
            VStack(spacing: 10) {
                Text(store.loadError).font(.footnote).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await store.refresh(force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if store.exams.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "graduationcap").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                Text("暂无成绩，点右上角「+」录入").font(.subheadline).foregroundStyle(.white)
            }
        } else {
            examList.refreshable { await store.refresh(force: true) }
        }
    }

    private var examList: some View {
        List {
            ForEach(store.exams) { e in
                NavigationLink {
                    ExamDetailView(examId: e.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.name).font(.subheadline.weight(.semibold))
                            Text("\(fmtDate(e.date)) · \(e.scores.count) 科")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(e.avgPct)%")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(scoreColor(e.avgPct))
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { idx in
                store.deleteExam(at: idx)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - 录入考试
struct AddExamView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DataStore.shared

    @State private var name = ""
    @State private var date = Date()
    @State private var drafts: [ScoreDraft] = []
    @State private var msg = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("考试信息") {
                    TextField("考试名称（如：期中考试）", text: $name)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }
                Section("各科成绩") {
                    ForEach($drafts) { $d in
                        HStack {
                            TextField("科目", text: $d.subject)
                                .frame(maxWidth: 90)
                            TextField("得分", text: $d.score).keyboardType(.decimalPad)
                            Text("/").foregroundStyle(.secondary)
                            TextField("满分", text: $d.full).keyboardType(.decimalPad)
                            Button {
                                drafts.removeAll { $0.id == d.id }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        drafts.append(ScoreDraft(subject: "", score: "", full: "100"))
                    } label: {
                        Label("添加一科", systemImage: "plus.circle.fill")
                    }
                }
                if !msg.isEmpty {
                    Section { Text(msg).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("录入考试")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(drafts.isEmpty)
                }
            }
            .onAppear {
                if drafts.isEmpty {
                    drafts = [ScoreDraft(subject: "语文", score: "", full: "100"),
                              ScoreDraft(subject: "数学", score: "", full: "100")]
                }
            }
        }
    }

    private func save() {
        var rows: [(String, Double, Double)] = []
        for d in drafts {
            let sub = d.subject.trimmingCharacters(in: .whitespaces)
            guard !sub.isEmpty, let sc = Double(d.score) else { continue }
            let f = Double(d.full) ?? 100
            rows.append((sub, sc, f))
        }
        if rows.isEmpty {
            msg = "请至少完整填写一科成绩"
            return
        }
        let title = name.trimmingCharacters(in: .whitespaces)
        let finalName = title.isEmpty ? "考试 " + fmtDate(fmtRawDate(date)) : title
        store.addExam(name: finalName, date: fmtRawDate(date), rows: rows)
        dismiss()
    }

    private func fmtRawDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

struct ScoreDraft: Identifiable {
    let id = UUID()
    var subject: String
    var score: String
    var full: String
}

// MARK: - 考试详情 + AI 分析
struct ExamDetailView: View {
    let examId: String

    @ObservedObject private var store = DataStore.shared
    @State private var busy = false
    @State private var errMsg = ""

    private var exam: ExamLite? {
        for e in store.exams where e.id == examId { return e }
        return nil
    }

    var body: some View {
        Screen {
            ScrollView {
                VStack(spacing: 14) {
                    if let e = exam {
                        summaryCard(e)
                        scoreCard(e)
                        analysisCard(e)
                    } else {
                        Text("记录不存在").foregroundStyle(.white)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("考试详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summaryCard(_ e: ExamLite) -> some View {
        GlassCard {
            VStack(spacing: 6) {
                Text(e.name).font(.headline).foregroundStyle(.white)
                Text(fmtDate(e.date)).font(.caption).foregroundStyle(.white.opacity(0.85))
                Text("\(e.avgPct)%").font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(20)
        }
    }

    private func scoreCard(_ e: ExamLite) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("各科成绩", systemImage: "list.number").font(.headline).foregroundStyle(.white)
                ForEach(e.scores) { s in
                    HStack {
                        Text(s.n).font(.subheadline).foregroundStyle(.white)
                        Spacer()
                        Text(scoreText(s)).font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        if let p = s.percent {
                            Text("\(p)%").font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func analysisCard(_ e: ExamLite) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI 分析", systemImage: "sparkles").font(.headline).foregroundStyle(.white)
                    Spacer()
                    if !busy {
                        Button {
                            Task { await runAnalysis(e) }
                        } label: {
                            Text(e.analysis.isEmpty ? "开始分析" : "重新分析")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Capsule())
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                if !errMsg.isEmpty {
                    Text(errMsg).font(.caption).foregroundStyle(.red)
                }
                if e.analysis.isEmpty {
                    Text("让 AI 结合这次考试的各科成绩，给出总体评价与学习建议。")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                } else {
                    Text(e.analysis).font(.subheadline).foregroundStyle(.white)
                }
            }
            .padding(18)
        }
    }

    private func runAnalysis(_ e: ExamLite) async {
        busy = true
        errMsg = ""
        defer { busy = false }
        var lines: [String] = []
        for s in e.scores {
            if let sc = s.score {
                lines.append("\(s.n)：\(Int(sc)) 分（满分 \(Int(s.full ?? 100))）")
            }
        }
        let prompt = "我是一名中学生，下面是我「\(e.name)」（\(fmtDate(e.date))）的成绩：\n" + lines.joined(separator: "\n") + "\n\n请给出：1. 总体评价；2. 强项与弱项分析；3. 下一步学习建议。用中文回答，简洁分点。"
        do {
            let out = try await APIClient.shared.aiChat(messages: [AIChatMessage(role: "user", content: prompt)])
            store.setExamAnalysis(id: e.id, text: out)
        } catch {
            errMsg = error.localizedDescription
        }
    }
}

// MARK: - 学习：作文批改 / 作业批改 / 题目练习
struct StudyView: View {
    @State private var segment = 0

    var body: some View {
        NavigationStack {
            Screen {
                VStack(spacing: 12) {
                    Picker("", selection: $segment) {
                        Text("作文批改").tag(0)
                        Text("作业批改").tag(1)
                        Text("题目练习").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    paneBody
                }
                .padding(.vertical)
            }
            .navigationTitle("学习")
        }
    }

    @ViewBuilder
    private var paneBody: some View {
        if segment == 0 {
            EssayPane()
        } else if segment == 1 {
            HomeworkPane()
        } else {
            QuizPane()
        }
    }
}

// MARK: - 作文批改
struct EssayPane: View {
    @ObservedObject private var store = DataStore.shared
    @State private var showEdit = false

    var body: some View {
        workList(
            items: store.essays,
            emptyIcon: "text.book.closed",
            emptyText: "还没有作文批改记录",
            onAdd: { showEdit = true }
        )
        .navigationTitle("作文批改")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: { Image(systemName: "plus").foregroundStyle(.white) }
            }
        }
        .sheet(isPresented: $showEdit) { WorkEditView(kind: "essay", subjectFixed: "语文") }
    }
}

// MARK: - 作业批改
struct HomeworkPane: View {
    @ObservedObject private var store = DataStore.shared
    @State private var showEdit = false

    var body: some View {
        workList(
            items: store.homeworks,
            emptyIcon: "checklist",
            emptyText: "还没有作业批改记录",
            onAdd: { showEdit = true }
        )
        .navigationTitle("作业批改")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: { Image(systemName: "plus").foregroundStyle(.white) }
            }
        }
        .sheet(isPresented: $showEdit) { WorkEditView(kind: "homework", subjectFixed: "") }
    }
}

/// 作文/作业共用列表
private func workList(items: [WorkItem], emptyIcon: String, emptyText: String, onAdd: @escaping () -> Void) -> some View {
    Group {
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: emptyIcon).font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                Text(emptyText).font(.subheadline).foregroundStyle(.white)
                Button {
                    onAdd()
                } label: {
                    Label("开始第一个", systemImage: "plus")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
            }
            .padding(.top, 60)
        } else {
            List {
                ForEach(items) { w in
                    NavigationLink {
                        WorkDetailView(item: w)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(w.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                if !w.scoreText.isEmpty {
                                    Text(w.scoreText).font(.caption.weight(.bold)).foregroundStyle(.indigo)
                                }
                            }
                            HStack {
                                if !w.subj.isEmpty {
                                    Text(w.subj).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                                Text(fmtDate(w.date)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - 作文/作业 编辑（AI 批改）
struct WorkEditView: View {
    let kind: String        // "essay" / "homework"
    let subjectFixed: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DataStore.shared

    @State private var title = ""
    @State private var subj = ""
    @State private var text = ""
    @State private var busy = false
    @State private var result = ""
    @State private var scoreTag = ""
    @State private var errMsg = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(kind == "essay" ? "作文信息" : "作业信息") {
                    TextField(kind == "essay" ? "作文标题" : "作业标题", text: $title)
                    if kind == "homework" {
                        TextField("科目（如：数学）", text: $subj)
                    }
                }
                Section("内容") {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                }
                if busy {
                    Section {
                        HStack {
                            ProgressView().tint(.indigo)
                            Text("AI 正在批改…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !errMsg.isEmpty {
                    Section { Text(errMsg).font(.footnote).foregroundStyle(.red) }
                }
                if !result.isEmpty {
                    Section("AI 批改结果") {
                        Text(result).font(.subheadline)
                        if !scoreTag.isEmpty {
                            Text("得分：" + scoreTag).font(.headline).foregroundStyle(.indigo)
                        }
                    }
                }
            }
            .navigationTitle(kind == "essay" ? "作文批改" : "作业批改")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if result.isEmpty {
                        Button("AI 批改") { Task { await grade() } }
                            .fontWeight(.semibold)
                            .disabled(busy || text.trimmingCharacters(in: .whitespaces).count < 10)
                    } else {
                        Button("保存") { save() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func grade() async {
        busy = true
        errMsg = ""
        defer { busy = false }
        var prompt: String
        if kind == "essay" {
            prompt = "你是一位资深语文老师。请批改下面这篇学生作文：第一行单独输出「得分：X/100」，然后分点给出详细点评（优点、问题、修改建议）。\n\n标题：" + title + "\n\n" + text
        } else {
            let s = subj.isEmpty ? "相应科目" : subj
            prompt = "你是一位" + s + "老师。请批改下面这份作业：指出其中的错误、给出正确解法并讲解思路。\n\n题目：" + title + "\n\n" + text
        }
        do {
            let out = try await APIClient.shared.aiChat(messages: [AIChatMessage(role: "user", content: prompt)])
            result = out
            scoreTag = parseScoreTag(out)
        } catch {
            errMsg = error.localizedDescription
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let finalTitle = t.isEmpty ? (kind == "essay" ? "未命名作文" : "未命名作业") : t
        store.addWork(kind: kind, title: finalTitle, subj: kind == "essay" ? "语文" : subj, text: text, result: result, score: scoreTag)
        dismiss()
    }
}

// MARK: - 作文/作业 详情
struct WorkDetailView: View {
    let item: WorkItem

    var body: some View {
        Screen {
            ScrollView {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline).foregroundStyle(.white)
                            HStack {
                                if !item.subj.isEmpty {
                                    Text(item.subj).font(.caption).foregroundStyle(.white.opacity(0.85))
                                }
                                Text(fmtDate(item.date)).font(.caption).foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                if !item.scoreText.isEmpty {
                                    Text("得分：" + item.scoreText).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                    }
                    if !item.result.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("AI 批改结果", systemImage: "sparkles").font(.headline).foregroundStyle(.white)
                                Text(item.result).font(.subheadline).foregroundStyle(.white)
                            }
                            .padding(18)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 题目练习（AI 生成 + 历史）
struct QuizPane: View {
    @ObservedObject private var store = DataStore.shared

    @State private var subj = "数学"
    @State private var topic = ""
    @State private var diff = 1
    @State private var count = 5
    @State private var busy = false
    @State private var errMsg = ""

    private let diffs = ["简单", "中等", "较难"]

    var body: some View {
        Screen {
            ScrollView {
                VStack(spacing: 14) {
                    genCard
                    if !errMsg.isEmpty {
                        Text(errMsg).font(.caption).foregroundStyle(.red)
                    }
                    if store.quizzes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "questionmark.circle").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                            Text("还没有练习记录").font(.subheadline).foregroundStyle(.white)
                        }
                        .padding(.top, 20)
                    } else {
                        historyCard
                    }
                }
                .padding()
            }
        }
        .navigationTitle("题目练习")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var genCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("AI 出题", systemImage: "wand.and.stars").font(.headline).foregroundStyle(.white)
                TextField("知识点（如：一元二次方程）", text: $topic)
                    .padding(10)
                    .background(.white.opacity(0.16), in: .rect(cornerRadius: 12))
                    .foregroundStyle(.white)
                HStack {
                    Text("科目").font(.caption).foregroundStyle(.white.opacity(0.85))
                    TextField("数学", text: $subj)
                        .frame(maxWidth: 90)
                        .padding(8)
                        .background(.white.opacity(0.16), in: .rect(cornerRadius: 10))
                        .foregroundStyle(.white)
                    Spacer()
                    Picker("难度", selection: $diff) {
                        Text("简单").tag(0)
                        Text("中等").tag(1)
                        Text("较难").tag(2)
                    }
                    .pickerStyle(.menu)
                }
                Stepper("题目数量：\(count) 道", value: $count, in: 3...10)
                    .foregroundStyle(.white)
                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "生成中…" : "开始生成")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
                .disabled(busy || topic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(18)
        }
    }

    private var historyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("练习历史", systemImage: "clock.arrow.circlepath").font(.headline).foregroundStyle(.white)
                ForEach(Array(store.quizzes.prefix(8).enumerated()), id: \.element.id) { _, q in
                    NavigationLink {
                        QuizDetailView(item: q)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.title).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                                Text(fmtDate(q.date) + (q.scoreText.isEmpty ? "" : " · " + q.scoreText))
                                    .font(.caption2).foregroundStyle(.white.opacity(0.8))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    if q.id != store.quizzes.prefix(8).last?.id { Divider() }
                }
            }
            .padding(18)
        }
    }

    private func generate() async {
        busy = true
        errMsg = ""
        defer { busy = false }
        let t = topic.trimmingCharacters(in: .whitespaces)
        let d = diffs[diff]
        let prompt = "请为一名中学生出 \(count) 道\(subj)题目，知识点：\(t)，难度：\(d)。要求：每题单独编号（1. 2. 3. …），先列出全部题目，最后另起一行以「【答案】」开头给出全部答案与简要解析。用中文。"
        do {
            let out = try await APIClient.shared.aiChat(messages: [AIChatMessage(role: "user", content: prompt)])
            store.addQuiz(subj: subj, topic: t, diff: d, count: count, content: out)
            topic = ""
        } catch {
            errMsg = error.localizedDescription
        }
    }
}

// MARK: - 题目练习详情
struct QuizDetailView: View {
    let item: WorkItem

    var body: some View {
        Screen {
            ScrollView {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title).font(.headline).foregroundStyle(.white)
                        Text(fmtDate(item.date)).font(.caption).foregroundStyle(.white.opacity(0.85))
                        Divider()
                        Text(item.result).font(.subheadline).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
                .padding()
            }
        }
        .navigationTitle("练习详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI 助手（与网页端同一云端聊天记录）
struct ChatView: View {
    @ObservedObject private var store = DataStore.shared

    @State private var input = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Screen {
                VStack(spacing: 0) {
                    msgList
                    inputBar
                }
            }
            .navigationTitle("AI 助手")
        }
    }

    private var msgList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.chatMsgs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                            Text("问我任何学习问题").font(.subheadline).foregroundStyle(.white)
                            Text("AI 已了解你的全部学习数据，回答与电脑端同步")
                                .font(.caption).foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(.top, 80)
                    }
                    ForEach(store.chatMsgs) { m in
                        bubble(m)
                            .id(m.id)
                    }
                    if busy {
                        HStack {
                            ProgressView().tint(.white)
                            Text("AI 正在思考…").font(.caption).foregroundStyle(.white.opacity(0.85))
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: store.chatMsgs.count) { _, _ in
                if let last = store.chatMsgs.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func bubble(_ m: ChatMsg) -> some View {
        HStack {
            if m.me { Spacer() }
            Text(m.text)
                .padding(12)
                .background(bubbleStyle(m), in: .rect(cornerRadius: 16))
                .foregroundStyle(m.me ? Color.white : Color.primary)
                .frame(maxWidth: 300, alignment: m.me ? .trailing : .leading)
            if !m.me { Spacer() }
        }
        .padding(.horizontal)
    }

    private func bubbleStyle(_ m: ChatMsg) -> AnyShapeStyle {
        if m.me { return AnyShapeStyle(Color.indigo) }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("输入问题…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(10)
                .background(.white.opacity(0.18), in: .rect(cornerRadius: 14))
                .foregroundStyle(.white)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(.white)
            }
            .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !busy else { return }
        input = ""
        store.appendChat(me: true, text: text)
        busy = true
        defer { busy = false }
        var history: [AIChatMessage] = []
        history.append(AIChatMessage(role: "system", content: "你是「学迹」学习系统的 AI 助手，用中文回答中学生的问题，语气友好、讲解清楚。"))
        for m in store.chatMsgs.suffix(21) {
            let role = m.me ? "user" : "assistant"
            history.append(AIChatMessage(role: role, content: m.text))
        }
        do {
            let out = try await APIClient.shared.aiChat(messages: history)
            store.appendChat(me: false, text: out)
        } catch {
            store.appendChat(me: false, text: "❌ " + error.localizedDescription)
        }
    }
}

// MARK: - 我的（个人 + 同步诊断 + 外观 + 退出）
struct MineView: View {
    @ObservedObject private var store = DataStore.shared
    @State private var balance: Double = 0

    var body: some View {
        NavigationStack {
            Screen {
                List {
                    profileSection
                    syncSection
                    themeSection
                    aboutSection
                    logoutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("我的")
            .task { balance = await APIClient.shared.fetchBalance() }
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(name: store.displayName, size: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.displayName).font(.headline)
                    Text("☁️ " + store.saveMsg)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var syncSection: some View {
        Section("☁️ 同步诊断") {
            LabeledRow(title: "登录账号", value: APIClient.shared.account.isEmpty ? "—" : APIClient.shared.account)
            LabeledRow(title: "云端考试", value: "\(store.exams.count) 次")
            LabeledRow(title: "云端作文 / 作业", value: "\(store.essays.count) 篇 / \(store.homeworks.count) 份")
            LabeledRow(title: "云端练习", value: "\(store.quizzes.count) 份")
            LabeledRow(title: "AI 余额", value: "¥" + String(format: "%.2f", balance))
            Button {
                Task {
                    await store.flushSave()
                    await store.refresh(force: true)
                }
            } label: {
                Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var themeSection: some View {
        Section("🎨 外观") {
            Picker("主题", selection: themeBinding) {
                Text("跟随系统").tag("auto")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
        }
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { store.theme },
            set: { store.setTheme($0) }
        )
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledRow(title: "版本", value: "1.2.0")
            LabeledRow(title: "界面", value: "iOS 液态玻璃")
            LabeledRow(title: "数据", value: "实时云端同步（按账号隔离）")
        }
    }

    private var logoutSection: some View {
        Section {
            Button("退出登录", role: .destructive) {
                Task {
                    await APIClient.shared.logout()
                    NotificationCenter.default.post(name: .xjLogout, object: nil)
                }
            }
        }
    }
}

struct LabeledRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 工具：从 AI 输出中提取「得分：X/100」
func parseScoreTag(_ text: String) -> String {
    if let r = text.range(of: #"得分[：:]\s*\d+\s*/\s*100"#, options: .regularExpression) {
        let s = String(text[r])
        return s.replacingOccurrences(of: " ", with: "")
    }
    if let r = text.range(of: #"\d+\s*/\s*100"#, options: .regularExpression) {
        return String(text[r]).replacingOccurrences(of: " ", with: "")
    }
    return ""
}
