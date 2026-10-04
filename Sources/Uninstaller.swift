import SwiftUI
import AppKit

// MARK: - Model

struct AppInfo: Identifiable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let fromAppStore: Bool
    var size: Int64 = -1
}

struct Leftover: Identifiable {
    var id: String { url.path }
    let url: URL
    let kind: String
    /// 번들 ID가 아니라 앱 이름으로만 일치 → 다른 앱 데이터일 수 있어 기본 선택 안 함
    let byName: Bool
    /// macOS가 보호하는 다른 앱의 컨테이너 등 → 전체 디스크 접근 권한 없이는 읽기·삭제 불가
    let restricted: Bool
    var size: Int64
    var selected: Bool
}

// MARK: - Finder

enum AppFinder {
    static func listApps() -> [AppInfo] {
        let roots = [URL(fileURLWithPath: "/Applications"), Scanner.h("Applications")]
        var found: [AppInfo] = []
        for root in roots {
            for u in Scanner.children(root) {
                if u.pathExtension == "app" {
                    if let a = info(u) { found.append(a) }
                } else if Scanner.isDir(u) {
                    // "/Applications/회사 이름/앱.app" 형태
                    for sub in Scanner.children(u) where sub.pathExtension == "app" {
                        if let a = info(sub) { found.append(a) }
                    }
                }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func info(_ url: URL) -> AppInfo? {
        guard let b = Bundle(url: url), let bid = b.bundleIdentifier else { return nil }
        // macOS 기본 앱과 자기 자신은 제외
        if bid.hasPrefix("com.apple.") || bid == Bundle.main.bundleIdentifier { return nil }
        let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let fileName = url.deletingPathExtension().lastPathComponent
        return AppInfo(url: url, name: fileName.isEmpty ? name : fileName,
                       bundleID: bid,
                       version: b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                       fromAppStore: Scanner.exists(url.appendingPathComponent("Contents/_MASReceipt")))
    }

    /// 앱이 ~/Library에 남긴 파일 찾기. 번들 ID나 앱 이름과 정확히 일치하는 것만 고른다.
    enum Match { case none, bundleID, name }

    static func leftovers(for app: AppInfo) -> [Leftover] {
        let bid = app.bundleID.lowercased()
        // "com.foo" 같은 짧은 ID는 같은 회사의 다른 앱과 겹칠 수 있어 접두어 매칭을 하지 않음
        guard bid.split(separator: ".").count >= 2 else { return [] }
        let allowPrefix = bid.split(separator: ".").count >= 3
        // 너무 짧거나 흔한 이름은 이름 매칭에서 제외
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent]
            .map { $0.lowercased() }.filter { $0.count >= 3 })

        func matchesExact(_ n: String) -> Match {
            let l = n.lowercased()
            let stem = (l as NSString).deletingPathExtension
            if l == bid || stem == bid { return .bundleID }
            // "com.foo.app.helper", "com.foo.app.savedState" 등
            if allowPrefix && l.hasPrefix(bid + ".") { return .bundleID }
            if names.contains(l) { return .name }
            return .none
        }
        func matchesGroup(_ n: String) -> Match {
            // 그룹 컨테이너: "group.com.foo.app", "TEAMID.com.foo.app"
            let l = n.lowercased()
            if l == bid || l.hasSuffix("." + bid) { return .bundleID }
            if allowPrefix && l.hasPrefix(bid + ".") { return .bundleID }
            return .none
        }
        func matchesByHost(_ n: String) -> Match {
            n.lowercased().hasPrefix(bid + ".") ? .bundleID : .none
        }

        let places: [(String, String, (String) -> Match)] = [
            ("Library/Application Support", L("앱 데이터", "App data"), matchesExact),
            ("Library/Caches", L("캐시", "Cache"), matchesExact),
            ("Library/Preferences", L("설정", "Preferences"), matchesExact),
            ("Library/Preferences/ByHost", L("설정", "Preferences"), matchesByHost),
            ("Library/Containers", L("샌드박스 데이터", "Sandbox data"), matchesExact),
            ("Library/Group Containers", L("공유 데이터", "Shared data"), matchesGroup),
            ("Library/Application Scripts", L("스크립트", "Scripts"), matchesGroup),
            ("Library/Saved Application State", L("창 상태", "Window state"), matchesExact),
            ("Library/HTTPStorages", L("웹 저장소", "Web storage"), matchesExact),
            ("Library/WebKit", L("웹 데이터", "Web data"), matchesExact),
            ("Library/Cookies", L("쿠키", "Cookies"), matchesExact),
            ("Library/Logs", L("로그", "Logs"), matchesExact),
            ("Library/LaunchAgents", L("자동 실행 항목", "Launch agents"), matchesExact),
        ]

        var result: [Leftover] = []
        var seen = Set<String>()
        for (dir, kind, match) in places {
            for u in Scanner.children(Scanner.h(dir)) {
                let m = match(u.lastPathComponent)
                guard m != .none, SafeDelete.allowed(u), seen.insert(u.path).inserted else { continue }
                let restricted = !readable(u)
                result.append(Leftover(url: u, kind: kind, byName: m == .name, restricted: restricted,
                                       size: restricted ? 0 : Scanner.size(of: u),
                                       selected: m == .bundleID && !restricted))
            }
        }
        return result.sorted { $0.size > $1.size }
    }

    static func readable(_ u: URL) -> Bool {
        if Scanner.isDir(u) { return (try? FileManager.default.contentsOfDirectory(atPath: u.path)) != nil }
        return FileManager.default.isReadableFile(atPath: u.path)
    }

    /// 심볼릭 링크 자체도 존재로 판단 (fileExists는 링크를 따라감)
    static func present(_ u: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: u.path)) != nil
    }

    /// 휴지통으로 이동. 메인 스레드가 아닌 곳에서 호출할 것 (Finder 대체 처리가 오래 걸릴 수 있음).
    static func trash(_ url: URL) -> Bool {
        guard SafeDelete.allowed(url) else { return false }
        // 이미 없으면 성공으로 간주 (이전 시도에서 지워진 경우)
        guard present(url) else { return true }
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { return true }
        // 관리자 소유 앱 번들(App Store 앱 등)만 Finder에게 맡겨 암호를 묻게 함.
        // 보호된 앱 데이터는 Finder로도 지울 수 없으므로 시도하지 않음.
        guard url.pathExtension == "app" else { return false }
        _ = Scanner.run("/usr/bin/osascript", [
            "-e", "on run argv",
            "-e", "tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)",
            "-e", "end run", url.path])
        return !present(url)
    }
}

// MARK: - ViewModel

@MainActor
final class UninstallStore: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var selectedID: String?
    @Published var leftovers: [Leftover] = []
    @Published var loadingLeftovers = false
    @Published var working = false
    @Published var search = ""
    @Published var sortBySize = true
    @Published var message = ""
    @Published var messageIsError = false
    /// 보호된 데이터 때문에 실패 → 전체 디스크 접근 권한 안내 표시
    @Published var needsFullDiskAccess = false
    /// 앱은 지워졌지만 지우지 못하고 남은 데이터 (다시 시도용)
    @Published var orphaned: [Leftover] = []
    @Published var orphanedAppName = ""
    private var sizeTask: Task<Void, Never>?

    var selected: AppInfo? { apps.first { $0.id == selectedID } }
    var visibleApps: [AppInfo] {
        let f = search.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search)
        }
        return sortBySize ? f.sorted { $0.size > $1.size } : f
    }
    var leftoverSize: Int64 { leftovers.filter(\.selected).reduce(0) { $0 + $1.size } }

    func load() {
        sizeTask?.cancel()
        Task.detached {
            let list = AppFinder.listApps()
            await MainActor.run { self.apps = list }
            // 크기 계산은 오래 걸리므로 하나씩 채워 넣음
            for a in list {
                if Task.isCancelled { return }
                let s = Scanner.size(of: a.url)
                await MainActor.run {
                    if let i = self.apps.firstIndex(where: { $0.id == a.id }) { self.apps[i].size = s }
                }
            }
        }
    }

    func select(_ id: String?) {
        guard !working else { return }
        selectedID = id
        leftovers = []
        message = ""
        needsFullDiskAccess = false
        guard let app = selected else { return }
        loadingLeftovers = true
        Task.detached {
            let l = AppFinder.leftovers(for: app)
            await MainActor.run {
                guard self.selectedID == app.id else { return }
                self.leftovers = l
                self.loadingLeftovers = false
            }
        }
    }

    func isRunning(_ app: AppInfo) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL || $0.bundleIdentifier == app.bundleID
        }
    }

    /// 버튼을 누른 순간의 앱·데이터 목록을 동기적으로 고정한 뒤 작업 시작.
    /// 이후 다른 앱을 클릭해도(working 동안 select 무시) 대상이 바뀌지 않음.
    func startUninstall(removeApp: Bool) {
        guard let app = selected, !loadingLeftovers, !working else { return }
        let targets = leftovers.filter(\.selected)
        working = true
        Task { await uninstall(app, targets, removeApp: removeApp) }
    }

    private func uninstall(_ app: AppInfo, _ targets: [Leftover], removeApp: Bool) async {
        messageIsError = false
        if let running = isRunning(app) {
            message = L("\(app.name) 종료 중…", "Quitting \(app.name)…")
            running.terminate()
            for _ in 0..<20 where !running.isTerminated { try? await Task.sleep(nanoseconds: 250_000_000) }
            if !running.isTerminated {
                working = false
                messageIsError = true
                message = L("\(app.name)이(가) 종료되지 않았습니다. 직접 종료한 뒤 다시 시도하세요.", "\(app.name) didn't quit. Quit it yourself and try again.")
                return
            }
        }

        message = L("휴지통으로 옮기는 중…", "Moving to Trash…")
        // 파일 작업은 백그라운드에서 (Finder 암호 창 등이 떠도 화면이 멈추지 않게)
        let (fails, protectedFails) = await Task.detached { () -> ([String], Bool) in
            var fails: [String] = []
            var protectedFails = false
            if removeApp, !AppFinder.trash(app.url) { fails.append(app.url.lastPathComponent) }
            for l in targets where !AppFinder.trash(l.url) {
                fails.append(l.url.lastPathComponent)
                if l.restricted || !AppFinder.readable(l.url) { protectedFails = true }
            }
            return (fails, protectedFails)
        }.value

        // select()는 작업 중이면 무시되므로 먼저 working을 내림
        working = false
        let freed = (removeApp ? max(app.size, 0) : 0) + targets.reduce(0) { $0 + $1.size }
        let appGone = removeApp && !AppFinder.present(app.url)
        let resultMessage = fails.isEmpty
            ? (removeApp ? L("\(app.name) 제거 완료", "Removed \(app.name)") : L("\(app.name) 데이터 정리 완료", "Deleted data of \(app.name)"))
              + (freed > 0 ? L(" · \(fmt(freed)) 휴지통으로 이동", " · \(fmt(freed)) moved to Trash") : "")
            : (appGone ? L("\(app.name) 앱은 제거했지만 일부 데이터를 지우지 못했습니다: ", "Removed \(app.name), but some data couldn't be deleted: ") : L("일부 항목을 지우지 못했습니다: ", "Some items couldn't be deleted: "))
              + fails.joined(separator: ", ")
        if appGone {
            // 앱 본체가 없어졌으면 실패가 있어도 목록에서 뺌 (없는 앱을 다시 지우려 하지 않게)
            // 남은 데이터는 따로 보관해서 '다시 시도'할 수 있게 함
            orphaned = targets.filter { AppFinder.present($0.url) }
            orphanedAppName = app.name
            apps.removeAll { $0.id == app.id }
            selectedID = nil
            leftovers = []
        } else {
            select(app.id)
        }
        // select()가 메시지를 지우므로 마지막에 설정
        message = resultMessage
        messageIsError = !fails.isEmpty
        needsFullDiskAccess = protectedFails
    }

    func retryOrphans() {
        guard !working, !orphaned.isEmpty else { return }
        let targets = orphaned
        working = true
        Task {
            let remaining = await Task.detached { targets.filter { !AppFinder.trash($0.url) } }.value
            working = false
            orphaned = remaining
            messageIsError = !remaining.isEmpty
            needsFullDiskAccess = !remaining.isEmpty
            message = remaining.isEmpty ? L("\(orphanedAppName)의 남은 데이터를 모두 휴지통으로 옮겼습니다.", "Moved all leftover data of \(orphanedAppName) to the Trash.")
                                        : L("아직 \(remaining.count)개 항목을 지우지 못했습니다.", "\(remaining.count) items still couldn't be deleted.")
        }
    }

    static func openFullDiskAccessSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }
}

