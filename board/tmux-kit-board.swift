// tmux-kit-board:用滑鼠排列 tmux 的 pane(原本是 codenv 的 codenv-board,2026-10-15 搬到 tmux-kit)
// 開一個 Mac 視窗,列出 tmux 所有的 session、window 和 pane,每個 window 畫成小縮圖:
//   把 pane 拖到別的 window → 合併進去(join-pane);拖到「新 window」→ 拆出來(break-pane)
//   把 window 拖到另一個 window 上 → 交換位置(swap-window);拖到別的 session → 搬過去(move-window)
//   拖到最下面的「新 session」→ 開一個新的 session 裝它
//   點一下 pane → 切換過去;雙擊名字或按右鍵 → 改名、換排列方式;session 旁邊的「改名」→ 改 session 名字;Esc 或 Cmd+W 關掉
// 用法: tmux-kit-board [--socket tmux的socket路徑] [--client tmux的client名稱] [--daemon]
//   沒給 --socket 時用 $TMUX 指的那個 tmux(從 tmux 選單打開時就是目前這個),
//   連 $TMUX 都沒有就用 tmux 預設的那個(/private/tmp/tmux-<uid>/default)
//   --daemon(2026-10-15 加):登入時由 LaunchAgent 在背景啟動,平常不顯示;
//     在 iTerm(或終端機)裡按 Cmd+Ctrl+A 叫出來,再按一次收起來。Esc、Cmd+W、Cmd+Q 都只是收起來,快捷鍵會一直有效
//     在別的 App 裡 Cmd+Ctrl+A 不會被搶走,照樣是那個 App 自己的功能
//     用的是 Carbon 的 RegisterEventHotKey,不需要「輔助使用」權限
// 編譯: swiftc -O -swift-version 5 tmux-kit-board.swift -o ~/.tmux-kit/tmux-kit-board

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Carbon.HIToolbox

// MARK: - tmux

struct Pane: Identifiable, Equatable {
    let id: String          // %3
    let index: Int
    let active: Bool
    let left, top, width, height: Int
    let command: String
    let name: String        // @tmux-kit-pane-name(自己取的名字)
    let title: String       // 程式設定的標題(Claude Code 會寫目前在做的事)
}

struct Window: Identifiable, Equatable {
    let id: String          // @2
    let index: Int
    let name: String
    let active: Bool
    let bell: Bool
    let width, height: Int
    var panes: [Pane]
    var activePane: Pane? { panes.first(where: { $0.active }) ?? panes.first }
}

struct Session: Identifiable, Equatable {
    let id: String          // $0
    let name: String
    let attached: Bool
    var windows: [Window]
}

final class Tmux {
    let socket: String?
    var client: String?     // 從選單打開時是那個 tmux client;按快捷鍵叫出來時是 nil(切到最近用過的 client)
    let path: String

    init(socket: String?, client: String?) {
        self.socket = socket
        self.client = client
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "tmux"
    }

    @discardableResult
    func run(_ args: [String]) -> (ok: Bool, out: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path == "tmux" ? "/usr/bin/env" : path)
        // -u:背景啟動時沒有 LANG,不加的話中文名字會變成底線
        var full = (path == "tmux" ? ["tmux"] : []) + ["-u"]
        if let socket { full += ["-S", socket] }
        task.arguments = full + args
        // 不讓 tmux 自己去讀 $TMUX,一律用上面指定的 socket
        var env = ProcessInfo.processInfo.environment
        if socket != nil { env.removeValue(forKey: "TMUX") }
        task.environment = env
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        guard (try? task.run()) != nil else { return (false, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }

    func load() -> [Session]? {
        let sep = "\u{1F}"
        let fields = ["session_id", "session_name", "session_attached",
                      "window_id", "window_index", "window_name", "window_active", "window_bell_flag",
                      "window_width", "window_height",
                      "pane_id", "pane_index", "pane_active", "pane_left", "pane_top", "pane_width", "pane_height",
                      "pane_current_command", "@tmux-kit-pane-name", "pane_title"]
        let format = fields.map { "#{\($0)}" }.joined(separator: sep)
        let r = run(["list-panes", "-a", "-F", format])
        guard r.ok else { return nil }
        var sessions: [Session] = []
        for line in r.out.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.components(separatedBy: sep)
            guard f.count == fields.count else { continue }
            let pane = Pane(id: f[10], index: Int(f[11]) ?? 0, active: f[12] == "1",
                            left: Int(f[13]) ?? 0, top: Int(f[14]) ?? 0, width: Int(f[15]) ?? 1, height: Int(f[16]) ?? 1,
                            command: f[17], name: f[18], title: f[19])
            if sessions.last?.id != f[0] {
                if let i = sessions.firstIndex(where: { $0.id == f[0] }) {
                    let s = sessions.remove(at: i); sessions.append(s)
                } else {
                    sessions.append(Session(id: f[0], name: f[1], attached: f[2] != "0", windows: []))
                }
            }
            var s = sessions.removeLast()
            if let wi = s.windows.firstIndex(where: { $0.id == f[3] }) {
                s.windows[wi].panes.append(pane)
            } else {
                s.windows.append(Window(id: f[3], index: Int(f[4]) ?? 0, name: f[5], active: f[6] == "1", bell: f[7] == "1",
                                        width: Int(f[8]) ?? 1, height: Int(f[9]) ?? 1, panes: [pane]))
            }
            sessions.append(s)
        }
        for i in sessions.indices {
            sessions[i].windows.sort { $0.index < $1.index }
            for j in sessions[i].windows.indices { sessions[i].windows[j].panes.sort { $0.index < $1.index } }
        }
        return sessions.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // 名字裡的 # 會被 tmux 當成特殊寫法,改名時要寫成 ##
    func escaped(_ s: String) -> String { s.replacingOccurrences(of: "#", with: "##") }
    var clientArgs: [String] { client.map { ["-c", $0] } ?? [] }
}

// MARK: - 狀態

final class Board: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var message = ""
    @Published var offline = false
    var paused = false      // 視窗收起來時不用每秒去問 tmux
    let tmux: Tmux
    private var timer: Timer?
    private var dragStarted: Date?

    init(tmux: Tmux) {
        self.tmux = tmux
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            if self?.paused == false { self?.refresh() }
        }
    }

    func refresh(force: Bool = false) {
        // 拖曳中不更新畫面,不然拖到一半目標會不見
        if !force, let d = dragStarted, Date().timeIntervalSince(d) < 8 { return }
        dragStarted = nil
        guard let s = tmux.load() else { offline = true; sessions = []; return }
        offline = false
        if s != sessions { sessions = s }
    }

    func beginDrag() { dragStarted = Date() }

    private func act(_ args: [String], _ done: String) {
        let r = tmux.run(args)
        message = r.ok ? done : "沒有成功,可能那個 pane 或 window 已經不在了"
        refresh(force: true)
    }

    func window(of pane: String) -> Window? {
        sessions.flatMap(\.windows).first(where: { $0.panes.contains(where: { $0.id == pane }) })
    }
    func session(of window: String) -> Session? {
        sessions.first(where: { $0.windows.contains(where: { $0.id == window }) })
    }

    // pane 搬到某個 window(排在那個 window 目前選到的 pane 旁邊)
    func movePane(_ pane: String, to w: Window) {
        guard let from = window(of: pane) else { return }
        if from.id == w.id { message = "已經在這個 window 裡了"; return }
        guard let target = w.activePane else { return }
        act(["join-pane", "-d", "-h", "-s", pane, "-t", target.id], "已經把 pane 搬到 window「\(w.name)」")
    }

    // pane 搬到另一個 pane 旁邊:目標比較寬就左右放,比較高就上下放
    func movePane(_ pane: String, nextTo target: Pane) {
        if pane == target.id { return }
        let side = target.width >= target.height * 2 ? "-h" : "-v"
        act(["join-pane", "-d", side, "-s", pane, "-t", target.id], "已經把 pane 搬過去")
    }

    // pane 拆出來,變成某個 session 裡的新 window
    func breakPane(_ pane: String, into s: Session) {
        guard let from = window(of: pane) else { return }
        if from.panes.count == 1, session(of: from.id)?.id == s.id { message = "這個 window 只有這一個 pane,不用拆"; return }
        act(["break-pane", "-d", "-s", pane, "-t", "\(s.id):"], "已經拆成新的 window")
    }

    func swapWindows(_ a: String, _ b: Window) {
        if a == b.id { return }
        guard let sa = session(of: a), let sb = session(of: b.id) else { return }
        if sa.id == sb.id {
            act(["swap-window", "-d", "-s", a, "-t", b.id], "已經交換位置")
        } else {
            act(["move-window", "-d", "-s", a, "-t", "\(sb.id):"], "已經搬到 session \(sb.name)")
        }
    }

    func moveWindow(_ a: String, to s: Session) {
        if session(of: a)?.id == s.id { return }
        act(["move-window", "-d", "-s", a, "-t", "\(s.id):"], "已經搬到 session \(s.name)")
    }

    func renameWindow(_ w: Window, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        act(["rename-window", "-t", w.id, "--", tmux.escaped(n)], "已經改名")
    }

    // session 改名(2026-10-15 加):tmux 不准兩個 session 同名,名字裡的 : 和 . 會被換成 _
    func renameSession(_ s: Session, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != s.name else { return }
        if sessions.contains(where: { $0.id != s.id && $0.name == n }) { message = "已經有叫「\(n)」的 session 了,換一個名字"; return }
        act(["rename-session", "-t", s.id, "--", tmux.escaped(n)], "已經改名")
    }

    func renamePane(_ p: Pane, _ name: String) {
        guard let w = window(of: p.id) else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty {
            tmux.run(["set", "-p", "-u", "-t", p.id, "@tmux-kit-pane-name"])
            if !w.panes.contains(where: { $0.id != p.id && !$0.name.isEmpty }) {
                tmux.run(["set", "-w", "-u", "-t", w.id, "pane-border-status"])
            }
            message = "已經拿掉名字"
        } else {
            tmux.run(["set", "-p", "-t", p.id, "@tmux-kit-pane-name", n])
            tmux.run(["set", "-w", "-t", w.id, "pane-border-status", "top"])
            message = "已經幫 pane 取名"
        }
        refresh(force: true)
    }

    func layout(_ w: Window, _ kind: String) {
        act(["select-layout", "-t", w.id, kind], "已經重新排列")
    }

    func renumber(_ s: Session) {
        act(["move-window", "-r", "-t", "\(s.id):"], "已經重新編號")
    }

    func newWindow(_ s: Session) {
        act(["new-window", "-d", "-t", "\(s.id):"], "已經開新的 window")
    }

    // 開新的 session(裡面先有一個 zsh 的 window)。tmux 不能開空的 session
    func newSession() {
        let r = tmux.run(["new-session", "-d", "-c", NSHomeDirectory(), "-P", "-F", "#{session_name}"])
        message = r.ok ? "已經開新的 session \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))" : "沒有成功開新的 session"
        refresh(force: true)
    }

    // window 或 pane 拖到「新 session」:先開新 session,把東西搬進去,再關掉開 session 時附帶的那個空 zsh
    func moveIntoNewSession(_ item: String) {
        let isWindow = item.hasPrefix("window:")
        let id = String(item.drop(while: { $0 != ":" }).dropFirst())
        if isWindow, let s = session(of: id), s.windows.count == 1 { message = "這個 session 只有這一個 window,不用搬"; return }
        if !isWindow, window(of: id) == nil { return }
        let r = tmux.run(["new-session", "-d", "-c", NSHomeDirectory(), "-P", "-F", "#{session_id} #{window_id} #{session_name}"])
        let f = r.out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        guard r.ok, f.count == 3 else { message = "沒有成功開新的 session"; refresh(force: true); return }
        let moved = isWindow ? tmux.run(["move-window", "-d", "-s", id, "-t", "\(f[0]):"])
                             : tmux.run(["break-pane", "-d", "-s", id, "-t", "\(f[0]):"])
        if moved.ok {
            tmux.run(["kill-window", "-t", f[1]])
            tmux.run(["move-window", "-r", "-t", "\(f[0]):"])
            message = isWindow ? "已經把 window 搬到新的 session \(f[2])" : "已經把 pane 拆到新的 session \(f[2])"
        } else {
            message = "新的 session \(f[2]) 開好了,但沒有搬成功"
        }
        refresh(force: true)
    }

    func focus(_ p: Pane) {
        guard let w = window(of: p.id), let s = session(of: w.id) else { return }
        tmux.run(["switch-client"] + tmux.clientArgs + ["-t", s.id])
        tmux.run(["select-window", "-t", w.id])
        tmux.run(["select-pane", "-t", p.id])
        message = "已經切換到「\(w.name)」"
        refresh(force: true)
    }
}

// MARK: - 畫面

let paneType = UTType.plainText

func label(_ p: Pane) -> String {
    if !p.name.isEmpty { return p.name }
    // tmux 預設把標題設成電腦名稱,那種不用顯示;Claude Code 這類程式會把標題寫成目前在做的事
    let host = ProcessInfo.processInfo.hostName.lowercased().replacingOccurrences(of: ".local", with: "")
    let t = p.title.trimmingCharacters(in: .whitespaces)
    let tl = t.lowercased().replacingOccurrences(of: ".local", with: "")
    if !t.isEmpty, tl != host, !host.hasPrefix(tl), !tl.hasPrefix(host), t != p.command { return "\(p.command) · \(t)" }
    return p.command
}

// 拖曳的內容用文字傳:pane:%3 或 window:@2
func dropString(_ providers: [NSItemProvider], _ handle: @escaping (String) -> Void) -> Bool {
    guard let item = providers.first else { return false }
    _ = item.loadObject(ofClass: NSString.self) { obj, _ in
        if let s = obj as? String { DispatchQueue.main.async { handle(s) } }
    }
    return true
}

struct Prompt: Identifiable {
    let id = UUID()
    let title: String
    var text: String
    let apply: (String) -> Void
}

struct BoardView: View {
    @ObservedObject var board: Board
    @State private var prompt: Prompt?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("tmux 排列").font(.title2.bold())
                Text("把 pane 拖到別的 window 就會合併,拖到「新 window」會拆出來;window 拖到 window 上會交換位置。點 pane 切換過去,雙擊名字或按右鍵可以改名(session 按「改名」)。Esc 或 Cmd+W 關掉;在 iTerm 裡按 Cmd+Ctrl+A 叫出來或收起來。")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                NewSessionButton(board: board)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            if !board.message.isEmpty {
                Text(board.message).font(.callout).foregroundStyle(.tint)
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }
            Divider()
            if board.offline {
                VStack(spacing: 8) {
                    Text("找不到 tmux").font(.title3)
                    Text("請先開好 tmux,這裡就會列出來。").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(board.sessions) { s in SessionView(board: board, session: s, prompt: $prompt) }
                        NewSessionDrop(board: board)
                    }.padding(16)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 380)
        .sheet(item: $prompt) { p in PromptView(prompt: p) { prompt = nil } }
        .onChange(of: prompt?.id) { _ in
            // 跳出改名框時把自己叫到最前面,打的字才會進到這裡
            if prompt != nil { NSApp.activate(ignoringOtherApps: true); NSApp.keyWindow?.makeKeyAndOrderFront(nil) }
        }
    }
}

struct PromptView: View {
    @State var prompt: Prompt
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.title).font(.headline)
            TextField("名字", text: $prompt.text).frame(width: 300).onSubmit { prompt.apply(prompt.text); close() }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                Button("確定") { prompt.apply(prompt.text); close() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20)
    }
}

struct SessionView: View {
    @ObservedObject var board: Board
    let session: Session
    @Binding var prompt: Prompt?
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Session \(session.name)").font(.headline)
                    .onTapGesture(count: 2) { renameSession() }
                    .help("雙擊可以改這個 session 的名字")
                if session.attached { Text("正在看").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18))) }
                Text("\(session.windows.count) 個 window").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("改名") { renameSession() }.controlSize(.small)
                Button("重新編號") { board.renumber(session) }.controlSize(.small)
                Button("新增 window") { board.newWindow(session) }.controlSize(.small)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(targeted ? Color.accentColor.opacity(0.15) : .clear))
            .onDrop(of: [paneType], isTargeted: $targeted) { providers in
                dropString(providers) { s in
                    if s.hasPrefix("window:") { board.moveWindow(String(s.dropFirst(7)), to: session) }
                    if s.hasPrefix("pane:") { board.breakPane(String(s.dropFirst(5)), into: session) }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(session.windows) { w in WindowCard(board: board, window: w, prompt: $prompt) }
                NewWindowDrop(board: board, session: session)
            }
        }
    }

    func renameSession() {
        prompt = Prompt(title: "Session \(session.name) 的新名字", text: session.name) { board.renameSession(session, $0) }
    }
}

struct NewWindowDrop: View {
    @ObservedObject var board: Board
    let session: Session
    @State private var targeted = false
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(RoundedRectangle(cornerRadius: 10).fill(targeted ? Color.accentColor.opacity(0.1) : .clear))
            .overlay(Text("新 window\n把 pane 拖到這裡,拆成新的 window").multilineTextAlignment(.center)
                .font(.callout).foregroundStyle(.secondary))
            .frame(height: 176)
            .onDrop(of: [paneType], isTargeted: $targeted) { providers in
                dropString(providers) { s in
                    if s.hasPrefix("pane:") { board.breakPane(String(s.dropFirst(5)), into: session) }
                    if s.hasPrefix("window:") { board.moveWindow(String(s.dropFirst(7)), to: session) }
                }
            }
    }
}

// 上面的「新增 session」按鈕:按一下開空的,也可以把 window 或 pane 拖上來
struct NewSessionButton: View {
    @ObservedObject var board: Board
    @State private var targeted = false
    var body: some View {
        Button("新增 session") { board.newSession() }
            .help("按一下開一個新的 session;把 window 或 pane 拖到這裡,會開新的 session 裝它")
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: targeted ? 2 : 0))
            .onDrop(of: [paneType], isTargeted: $targeted) { providers in
                dropString(providers) { s in board.moveIntoNewSession(s) }
            }
    }
}

struct NewSessionDrop: View {
    @ObservedObject var board: Board
    @State private var targeted = false
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(RoundedRectangle(cornerRadius: 10).fill(targeted ? Color.accentColor.opacity(0.1) : .clear))
            .overlay(Text("新 session\n把 window 或 pane 拖到這裡,開一個新的 session 裝它;只要空的就按上面的「新增 session」")
                .multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary))
            .frame(height: 70)
            .onDrop(of: [paneType], isTargeted: $targeted) { providers in
                dropString(providers) { s in board.moveIntoNewSession(s) }
            }
    }
}

struct WindowCard: View {
    @ObservedObject var board: Board
    let window: Window
    @Binding var prompt: Prompt?
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).help("按住這裡拖曳整個 window")
                Text("[\(window.index)] \(window.name)").font(.system(.body, design: .monospaced).bold()).lineLimit(1)
                if window.bell { Circle().fill(Color.orange).frame(width: 7, height: 7).help("這個 window 有新的動靜(例如 Claude 回覆完了)") }
                Spacer()
                Text("\(window.panes.count) 個 pane").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { renameWindow() }
            .onDrag { board.beginDrag(); return NSItemProvider(object: "window:\(window.id)" as NSString) }
            Preview(board: board, window: window, prompt: $prompt)
                .frame(height: 140)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(targeted ? Color.accentColor : (window.active ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.25)),
                          lineWidth: targeted ? 2.5 : 1))
        .onDrop(of: [paneType], isTargeted: $targeted) { providers in
            dropString(providers) { s in
                if s.hasPrefix("pane:") { board.movePane(String(s.dropFirst(5)), to: window) }
                if s.hasPrefix("window:") { board.swapWindows(String(s.dropFirst(7)), window) }
            }
        }
        .contextMenu {
            Button("切換到這個 window") { if let p = window.activePane { board.focus(p) } }
            Button("改 window 名字…") { renameWindow() }
            Divider()
            Button("排成左右並排") { board.layout(window, "even-horizontal") }
            Button("排成上下堆疊") { board.layout(window, "even-vertical") }
            Button("左邊一大格,右邊幾小格") { board.layout(window, "main-vertical") }
            Button("排成方格") { board.layout(window, "tiled") }
        }
    }

    func renameWindow() {
        prompt = Prompt(title: "Window [\(window.index)] 的新名字", text: window.name) { board.renameWindow(window, $0) }
    }
}

struct Preview: View {
    @ObservedObject var board: Board
    let window: Window
    @Binding var prompt: Prompt?

    var body: some View {
        GeometryReader { geo in
            // 終端機的一格大約是寬 1、高 2,照這個比例縮小
            let ww = CGFloat(max(window.width, 1)), wh = CGFloat(max(window.height, 1)) * 2
            let scale = min(geo.size.width / ww, geo.size.height / wh)
            let ox = (geo.size.width - ww * scale) / 2, oy = (geo.size.height - wh * scale) / 2
            ZStack(alignment: .topLeading) {
                ForEach(window.panes) { p in
                    PaneBox(board: board, pane: p, prompt: $prompt)
                        .frame(width: max(CGFloat(p.width) * scale - 3, 8), height: max(CGFloat(p.height) * 2 * scale - 3, 8))
                        .offset(x: ox + CGFloat(p.left) * scale, y: oy + CGFloat(p.top) * 2 * scale)
                }
            }
        }
    }
}

struct PaneBox: View {
    @ObservedObject var board: Board
    let pane: Pane
    @Binding var prompt: Prompt?
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(targeted ? Color.accentColor.opacity(0.35) : (pane.active ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(pane.active ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1))
            .overlay(
                Text(label(pane)).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    .padding(3).foregroundStyle(.primary)
            )
            .contentShape(Rectangle())
            .help("\(label(pane))(\(pane.width)×\(pane.height))\n拖到別的 window 就會搬過去;點一下切換到這個 pane")
            .onTapGesture(count: 2) { renamePane() }
            .onTapGesture { board.focus(pane) }
            .onDrag { board.beginDrag(); return NSItemProvider(object: "pane:\(pane.id)" as NSString) }
            .onDrop(of: [paneType], isTargeted: $targeted) { providers in
                dropString(providers) { s in
                    if s.hasPrefix("pane:") { board.movePane(String(s.dropFirst(5)), nextTo: pane) }
                    if s.hasPrefix("window:"), let w = board.window(of: pane.id) { board.swapWindows(String(s.dropFirst(7)), w) }
                }
            }
            .contextMenu {
                Button("切換到這個 pane") { board.focus(pane) }
                Button("幫這個 pane 取名…") { renamePane() }
                if !pane.name.isEmpty { Button("拿掉這個 pane 的名字") { board.renamePane(pane, "") } }
                if let w = board.window(of: pane.id), w.panes.count > 1, let s = board.session(of: w.id) {
                    Button("拆出去,變成新的 window") { board.breakPane(pane.id, into: s) }
                }
            }
    }

    func renamePane() {
        prompt = Prompt(title: "這個 pane 的名字(留空就是拿掉名字)", text: pane.name) { board.renamePane(pane, $0) }
    }
}

// MARK: - 啟動

// 視窗還沒在最前面時,第一下按住就能直接拖,不用先點一下視窗
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// 沒有 $TMUX 時(例如登入時背景啟動)用 tmux 預設的 socket;寫法跟 $TMUX 裡的一樣,兩邊才認得是同一個 tmux
func socketArg() -> String? {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--socket"), i + 1 < args.count { return args[i + 1] }
    if let t = ProcessInfo.processInfo.environment["TMUX"], let first = t.split(separator: ",").first { return String(first) }
    return "/private/tmp/tmux-\(getuid())/default"
}
let daemon = CommandLine.arguments.contains("--daemon")

// Cmd+Ctrl+A 全域快捷鍵(Carbon 的 C 函式不能抓外面的變數,所以要做的事放在全域變數)
var hotKeyAction: (() -> Void)?
var hotKeyRef: EventHotKeyRef?
func installHotKeyHandler() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        DispatchQueue.main.async { hotKeyAction?() }
        return noErr
    }, 1, &spec, nil, nil)
}
// 只在 iTerm / 終端機 / 排列視窗自己在最前面時佔用 Cmd+Ctrl+A,換到別的 App 就放掉,讓那個 App 自己用(2026-10-15 改)
func setHotKey(_ on: Bool) {
    if on, hotKeyRef == nil {
        // kVK_ANSI_A 是鍵盤上 A 那顆鍵的位置,開著注音也一樣
        let id = EventHotKeyID(signature: OSType(0x63646E76), id: 1)
        if RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(cmdKey | controlKey), id, GetApplicationEventTarget(), 0, &hotKeyRef) != noErr {
            hotKeyRef = nil
            FileHandle.standardError.write("tmux-kit-board: Cmd+Ctrl+A 已經被別的程式用掉了\n".data(using: .utf8)!)
        }
    } else if !on, let ref = hotKeyRef {
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }
}
let terminalApps: Set<String> = ["com.googlecode.iterm2", "com.apple.Terminal"]
func hotKeyWanted(_ app: NSRunningApplication?) -> Bool {
    guard let app = app else { return false }
    return app.processIdentifier == getpid() || terminalApps.contains(app.bundleIdentifier ?? "")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var board: Board!

    func applicationDidFinishLaunching(_ note: Notification) {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let socket = socketArg()
        board = Board(tmux: Tmux(socket: socket, client: value("--client")))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "tmux 排列"
        window.contentView = FirstMouseHostingView(rootView: BoardView(board: board))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating            // 浮在 iTerm 上面,拖曳時不會被蓋住
        // 出現在現在看的這個桌面,前面是全螢幕的 iTerm 或別的 App 也疊在上面,不會把人拉到別的桌面(2026-10-15 改)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.setFrameAutosaveName("tmux-kit-board")
        NSApp.mainMenu = makeMenu()
        if daemon {
            board.paused = true
            hotKeyAction = { [weak self] in self?.toggle() }
            installHotKeyHandler()
            setHotKey(hotKeyWanted(NSWorkspace.shared.frontmostApplication))
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let wanted = hotKeyWanted(app)
                setHotKey(wanted)
                // 換到別的 App 時順便收起來,不然浮在最上層的視窗會擋住那個 App
                if !wanted, let self = self, self.window.isVisible { self.hide() }
            }
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        // Esc 關掉視窗(改名框開著的時候 Esc 是取消改名,那時候按鍵是送到改名框,不會到這裡)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let w = self?.window, e.keyCode == 53, e.window === w, w.attachedSheet == nil else { return e }
            w.performClose(nil)
            return nil
        }
        if let path = value("--print-window-id") {
            try? String(window.windowNumber).write(toFile: path, atomically: true, encoding: .utf8)
        }
        // 已經開著的話,再打開一次就把舊的叫到最前面(新的自己結束);從選單打開的會帶上 tmux client 名稱
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("tmux-kit-board.show"), object: socket, queue: .main) { [weak self] note in
            self?.show(client: note.userInfo?["client"] as? String)
        }
    }

    func show(client: String?) {
        board.tmux.client = client
        board.paused = false
        board.refresh(force: true)
        // 不切成一般 App(Dock 圖示):切了的話,前面是全螢幕 App 時會被拉到別的桌面
        NSApp.unhide(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 背景模式:收起來(Dock 圖示也拿掉),鍵盤還給原本在用的 App
    @objc func hide() {
        window.orderOut(nil)
        board.paused = true
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func toggle() {
        if window.isVisible { hide() } else { show(client: nil) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if daemon { hide(); return false }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { !daemon }

    // 選單列:Cmd+Q 結束、Cmd+W 關視窗,還有改名時要用的 Cmd+C / Cmd+V
    func makeMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [(String, Selector, String)]) {
            let m = NSMenu(title: title)
            for (t, sel, key) in items {
                let item = NSMenuItem(title: t, action: sel, keyEquivalent: key)
                if sel == #selector(hide) { item.target = self }
                m.addItem(item)
            }
            let top = NSMenuItem(); top.submenu = m; main.addItem(top)
        }
        // 背景模式的 Cmd+Q 只收起來,不然結束後 Cmd+Ctrl+A 就沒反應了
        add("tmux 排列", [daemon ? ("收起 tmux 排列(Cmd+Ctrl+A 再叫出來)", #selector(hide), "q")
                                 : ("結束 tmux 排列", #selector(NSApplication.terminate(_:)), "q")])
        add("編輯", [("還原", Selector(("undo:")), "z"), ("剪下", #selector(NSText.cut(_:)), "x"),
                     ("拷貝", #selector(NSText.copy(_:)), "c"), ("貼上", #selector(NSText.paste(_:)), "v"),
                     ("全選", #selector(NSText.selectAll(_:)), "a")])
        add("視窗", [("關閉視窗", #selector(NSWindow.performClose(_:)), "w")])
        return main
    }
}

// 同一個 tmux 只開一個視窗:已經有的話請它出來,自己結束
// 背景模式不讓位:它要一直開著接快捷鍵(之前從選單開的那個視窗關掉就沒了)
let lockSocket = socketArg()
// Swift 的 hashValue 每次執行都不一樣,自己算一個固定的
let lockKey = (lockSocket ?? "default").utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) }
let lockPath = NSTemporaryDirectory() + "tmux-kit-board-" + String(lockKey, radix: 16) + ".pid"
if let old = try? String(contentsOfFile: lockPath, encoding: .utf8), let pid = Int32(old.trimmingCharacters(in: .whitespacesAndNewlines)),
   pid != getpid(), kill(pid, 0) == 0, !daemon {
    let client = CommandLine.arguments.firstIndex(of: "--client").flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil }
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("tmux-kit-board.show"), object: lockSocket,
                                                                 userInfo: client.map { ["client": $0] }, deliverImmediately: true)
    exit(0)
}
try? String(getpid()).write(toFile: lockPath, atomically: true, encoding: .utf8)

let app = NSApplication.shared
// 一般 App:開著時 Dock 有圖示,點視窗一定拿得到鍵盤(改名時打的字才不會跑到 iTerm)
// 背景模式先不顯示,叫出來時才變成一般 App
app.setActivationPolicy(daemon ? .accessory : .regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
