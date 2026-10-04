import SwiftUI
import AppKit

// MARK: - Localization

/// Mac의 기본 언어가 한국어면 한국어, 그 외에는 영어
let isKorean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
func L(_ ko: String, _ en: String) -> String { isKorean ? ko : en }

/// 그룹 이름은 내부 식별자(한국어)로 쓰고, 화면에 보일 때만 번역
func groupTitle(_ key: String) -> String {
    switch key {
    case "앱 캐시": return L(key, "App Caches")
    case "개발 도구 캐시": return L(key, "Developer Tool Caches")
    case "시스템": return L(key, "System")
    case "Claude 앱 데이터": return L(key, "Claude App Data")
    default: return key
    }
}

// MARK: - Model

enum Safety: Int, Comparable {
    case safe = 0, caution = 1, manual = 2
    static func < (a: Safety, b: Safety) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe: return L("안전", "Safe")
        case .caution: return L("주의", "Caution")
        case .manual: return L("직접 확인", "Manual")
        }
    }
    var color: Color {
        switch self {
        case .safe: return .green
        case .caution: return .orange
        case .manual: return .gray
        }
    }
}

enum CleanAction {
    /// 경로를 휴지통으로 이동 (또는 설정에 따라 즉시 삭제)
    case removePaths([URL])
    /// 외부 명령 실행
    case command(String, [String])
    /// 정리하지 않고 Finder에서 위치만 보여줌
    case reveal(URL)
    /// 체크박스 대신 버튼으로 실행하고 다시 검사
    case button(String, String, [String])
}

struct CleanItem: Identifiable {
    let id = UUID()
    let group: String
    let title: String
    let detail: String
    let safety: Safety
    let action: CleanAction
    var revealOverride: URL? = nil
    var size: Int64
    var selected: Bool
    /// 명령 실행 후 실제로 사라져야 하는 경로. 남아 있으면 실패로 보고 (명령이 성공 코드만 내고 일부만 지우는 경우 대비)
    var expectGone: [URL] = []
    /// 그룹 전체를 한 번에 지우는 항목 (예: Colima VM 전체). '모두 선택'에서 제외하고 그룹 용량 중복 계산 안 함
    var wholeDelete = false

    var revealURL: URL? {
        if let u = revealOverride { return u }
        switch action {
        case .reveal(let u): return u
        case .removePaths(let us) where us.count == 1: return us[0]
        default: return nil
        }
    }
    var checkable: Bool {
        switch action {
        case .removePaths, .command: return true
        default: return false
        }
    }
}

// MARK: - Scanner

enum Scanner {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static func h(_ p: String) -> URL { home.appendingPathComponent(p) }

    static func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isVolumeKey]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: Set(keys)) else { continue }
            // 다른 볼륨이 연결된 지점(예: 시뮬레이터 디스크 이미지 마운트)은 건너뜀 — 중복 계산 방지
            if v.isVolume == true { e.skipDescendants(); continue }
            guard v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func childrenIncludingHidden(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
            .filter { !$0.lastPathComponent.hasPrefix(".") } ?? []
    }

    static func isDir(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
    }

    static func run(_ tool: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        // GUI 앱은 PATH가 짧아서 Homebrew 도구(limactl 등)를 못 찾음
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func which(_ name: String) -> String? {
        ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"].map { $0 + name }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// "1.2GB", "512MB", "300kB" 같은 Docker 크기 문자열을 바이트로
    static func parseSize(_ s: String) -> Int64 {
        let t = s.trimmingCharacters(in: .whitespaces)
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (u, m) in units where t.hasSuffix(u) {
            return Int64((Double(t.dropLast(u.count)) ?? 0) * m)
        }
        return 0
    }

    static func scan(progress: @escaping (String) -> Void) -> [CleanItem] {
        var items: [CleanItem] = []
        let minSize: Int64 = 20 * 1_000_000

        func add(_ group: String, _ title: String, _ detail: String, _ safety: Safety,
                 _ url: URL, selected: Bool? = nil, reveal: Bool = false, min: Int64? = nil,
                 contents: Bool = false) {
            guard exists(url) else { return }
            progress(title)
            let s = size(of: url)
            guard s >= (min ?? minSize) else { return }
            // contents: 폴더 자체는 남기고 안의 내용만 지움 (앱이 폴더가 있다고 가정하는 경우 대비)
            let targets = contents ? children(url) : [url]
            guard !targets.isEmpty else { return }
            items.append(CleanItem(group: group, title: title, detail: detail, safety: safety,
                                   action: reveal ? .reveal(url) : .removePaths(targets),
                                   revealOverride: url,
                                   size: s, selected: selected ?? (safety == .safe)))
        }

        // 1. 앱 캐시: 큰 폴더는 개별 항목, 나머지는 묶음
        let caches = h("Library/Caches")
        var smallCaches: [URL] = []
        var smallTotal: Int64 = 0
        var appleCaches: [URL] = []
        var appleTotal: Int64 = 0
        for c in children(caches) {
            progress(L("캐시: \(c.lastPathComponent)", "Cache: \(c.lastPathComponent)"))
            let s = size(of: c)
            if c.lastPathComponent.hasPrefix("com.apple.") {
                // macOS 자체 캐시는 기본 선택에서 빼고 따로 묶음
                appleCaches.append(c); appleTotal += s
            } else if s >= 100 * 1_000_000 {
                items.append(CleanItem(group: "앱 캐시", title: c.lastPathComponent,
                                       detail: L("앱이 필요하면 다시 만듭니다. 해당 앱을 종료한 뒤 정리하세요.", "The app recreates it when needed. Quit the app before cleaning."),
                                       safety: .safe, action: .removePaths([c]), size: s, selected: true))
            } else if s > 0 {
                smallCaches.append(c); smallTotal += s
            }
        }
        if smallTotal >= minSize {
            items.append(CleanItem(group: "앱 캐시", title: L("기타 작은 캐시 \(smallCaches.count)개", "\(smallCaches.count) other small caches"),
                                   detail: L("100MB 미만 캐시 폴더 묶음", "Cache folders under 100 MB, grouped"), safety: .safe,
                                   action: .removePaths(smallCaches), size: smallTotal, selected: true))
        }
        if appleTotal >= minSize {
            items.append(CleanItem(group: "앱 캐시", title: L("macOS 시스템 캐시 \(appleCaches.count)개", "\(appleCaches.count) macOS system caches"),
                                   detail: L("Apple 앱·서비스의 캐시. 대부분 다시 만들어지지만 필요할 때만 정리하세요.", "Caches of Apple apps and services. Most are recreated, but clean them only if needed."),
                                   safety: .caution, action: .removePaths(appleCaches), size: appleTotal, selected: false))
        }

        add("앱 캐시", L("사용자 로그", "User logs"), L("앱 로그 파일. 문제 진단용이며 지워도 됩니다.", "App log files used for troubleshooting. Safe to delete."), .safe, h("Library/Logs"), contents: true)
        add("개발 도구 캐시", L("npm 캐시", "npm cache"), L("npm 패키지 다운로드 캐시", "Downloaded npm packages"), .safe, h(".npm/_cacache"))
        add("개발 도구 캐시", "~/.cache", L("pip, huggingface 등 여러 도구의 캐시", "Caches from pip, Hugging Face and other tools"), .caution, h(".cache"),
            selected: false, contents: true)
        add("개발 도구 캐시", L("Gradle 캐시", "Gradle cache"), L("Android/Gradle 빌드 캐시", "Android/Gradle build cache"), .safe, h(".gradle/caches"), contents: true)

        // 2. Xcode
        add("Xcode", "DerivedData", L("빌드 중간 결과물. 다음 빌드가 조금 느려질 뿐입니다.", "Intermediate build products. The next build will just be a bit slower."), .safe,
            h("Library/Developer/Xcode/DerivedData"), contents: true)
        add("Xcode", "iOS DeviceSupport", L("연결했던 iPhone별 디버그 심볼. 다시 연결하면 재생성됩니다.", "Debug symbols for iPhones you connected. Recreated when you reconnect."), .safe,
            h("Library/Developer/Xcode/iOS DeviceSupport"), contents: true)
        add("Xcode", "Archives", L("배포용 아카이브. 앱스토어 제출 기록이 필요하면 남기세요.", "Distribution archives. Keep them if you need your App Store submission history."), .caution,
            h("Library/Developer/Xcode/Archives"), selected: false, contents: true)

        // 사용 불가 시뮬레이터
        progress(L("시뮬레이터 확인", "Checking simulators"))
        let (_, devOut) = run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable"])
        let unavailable = devOut.components(separatedBy: "\n").filter { $0.contains("(unavailable") }.count
        if unavailable > 0 {
            items.append(CleanItem(group: "Xcode", title: L("사용 불가 시뮬레이터 \(unavailable)개", "\(unavailable) unavailable simulators"),
                                   detail: L("설치된 런타임이 없어 실행할 수 없는 시뮬레이터", "Simulators that can't run because their runtime is missing"), safety: .safe,
                                   action: .command("/usr/bin/xcrun", ["simctl", "delete", "unavailable"]),
                                   size: 0, selected: true))
        }

        // 시뮬레이터 런타임 (가장 큰 항목인 경우가 많음)
        progress(L("시뮬레이터 런타임 확인", "Checking simulator runtimes"))
        let (code, json) = run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        if code == 0, let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            func platform(_ r: [String: Any]) -> String {
                let rid = r["runtimeIdentifier"] as? String ?? ""
                return rid.contains("watchOS") ? "watchOS" : rid.contains("tvOS") ? "tvOS"
                    : rid.contains("xrOS") ? "visionOS" : "iOS"
            }
            func version(_ r: [String: Any]) -> String { r["version"] as? String ?? "0" }
            // 플랫폼별 최신 버전 (숫자 비교: "9.0" < "27.0")
            var newest: [String: String] = [:]
            for r in dict.values {
                let p = platform(r), v = version(r)
                if let cur = newest[p], cur.compare(v, options: .numeric) != .orderedAscending { continue }
                newest[p] = v
            }
            for r in dict.values {
                guard let ident = r["identifier"] as? String, (r["deletable"] as? Bool) == true else { continue }
                let version = version(r)
                let platform = platform(r)
                let isNewest = newest[platform] == version
                items.append(CleanItem(
                    group: "Xcode", title: L("\(platform) \(version) 시뮬레이터 런타임", "\(platform) \(version) simulator runtime"),
                    detail: isNewest ? L("가장 최신 런타임입니다. 시뮬레이터를 쓴다면 남겨두세요.", "This is the newest runtime. Keep it if you use the simulator.")
                                     : L("오래된 런타임. 필요하면 Xcode > Settings > Components에서 다시 받을 수 있습니다.", "Older runtime. You can download it again from Xcode > Settings > Components."),
                    safety: .caution,
                    action: .command("/usr/bin/xcrun", ["simctl", "runtime", "delete", ident]),
                    size: (r["sizeBytes"] as? NSNumber)?.int64Value ?? 0, selected: !isNewest))
            }
        }

        // 3. 시스템
        progress(L("Time Machine 로컬 스냅샷 확인", "Checking Time Machine local snapshots"))
        let (_, snaps) = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        let snapCount = snaps.components(separatedBy: "\n").filter { $0.contains("com.apple") }.count
        if snapCount > 0 {
            items.append(CleanItem(group: "시스템", title: L("Time Machine 로컬 스냅샷 \(snapCount)개", "\(snapCount) Time Machine local snapshots"),
                                   detail: L("macOS가 보관 중인 로컬 백업. 외장 백업이 있다면 지워도 됩니다.", "Local backups kept by macOS. Safe to delete if you have an external backup."),
                                   safety: .caution,
                                   action: .command("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"]),
                                   size: 0, selected: false))
        }
        add("시스템", L("iPhone/iPad 백업", "iPhone/iPad backups"), L("Finder로 만든 기기 백업. iCloud 백업이 있는지 먼저 확인하세요.", "Device backups made with Finder. Make sure you have an iCloud backup first."), .caution,
            h("Library/Application Support/MobileSync/Backup"), selected: false, contents: true)

        // 4. 대용량 앱 데이터: 하위 항목별로 보여주고 기본은 선택 안 함
        scanColima(&items, progress)
        scanLMStudio(&items, progress)
        scanOllama(&items, progress)
        scanClaude(&items, progress)
        scanAndroid(&items, progress)
        add("Docker Desktop", L("Docker Desktop 데이터", "Docker Desktop data"),
            L("Docker Desktop 앱의 정리 메뉴(Troubleshoot > Clean)를 사용하세요.", "Use the cleanup menu in the Docker Desktop app (Troubleshoot > Clean)."),
            .manual, h("Library/Containers/com.docker.docker"), reveal: true)

        return items
    }

    // MARK: Colima / Docker

    static func scanColima(_ items: inout [CleanItem], _ progress: (String) -> Void) {
        let dir = h(".colima")
        guard exists(dir), let colima = which("colima") else { return }
        let g = "Colima (Docker)"
        progress(L("Colima 확인", "Checking Colima"))
        // ~/.colima/_lima/<인스턴스>  : VM (기본 프로필은 "colima", 그 외 "colima-<프로필>")
        // ~/.colima/_lima/_disks/<인스턴스> : 컨테이너 데이터 디스크. `colima delete`는 --data 없이는 이걸 남김
        let lima = dir.appendingPathComponent("_lima")
        let disksDir = lima.appendingPathComponent("_disks")
        let instances = children(lima).filter { isDir($0) && !$0.lastPathComponent.hasPrefix("_") }
        let instanceNames = Set(instances.map(\.lastPathComponent))

        for inst in instances {
            let name = inst.lastPathComponent
            let profile = name == "colima" ? "default" : String(name.dropFirst("colima-".count))
            let disk = disksDir.appendingPathComponent(name)
            items.append(CleanItem(
                group: g, title: L("Colima VM 전체 삭제", "Delete entire Colima VM") + (profile == "default" ? "" : " (\(profile))"),
                detail: L("Docker 가상머신과 그 안의 모든 이미지·컨테이너·볼륨을 지웁니다. 나중에 `colima start`로 새로 만들 수 있습니다.", "Deletes the Docker VM and all images, containers and volumes in it. You can recreate it later with `colima start`."),
                safety: .caution, action: .command(colima, ["delete", profile, "--force", "--data"]),
                size: size(of: inst) + size(of: disk), selected: false,
                expectGone: [inst, disk], wholeDelete: true))
        }

        // VM은 이미 지워졌는데 데이터 디스크만 남은 경우 (예전 `colima delete`가 남긴 것)
        for disk in children(disksDir) where isDir(disk) && !instanceNames.contains(disk.lastPathComponent) {
            progress(L("Colima 남은 디스크 확인", "Checking leftover Colima disks"))
            let s = size(of: disk)
            guard s > 0 else { continue }
            items.append(CleanItem(
                group: g, title: L("남은 Colima 데이터 디스크", "Leftover Colima data disk") + (disk.lastPathComponent == "colima" ? "" : " (\(disk.lastPathComponent))"),
                detail: L("Colima VM은 이미 삭제됐고 컨테이너 데이터 디스크만 남아 있습니다. `colima start`를 하면 다시 연결되니, 컨테이너 데이터가 필요 없을 때만 지우세요.", "The Colima VM is already gone; only its container data disk remains. `colima start` would reattach it, so delete it only if you don't need that data."),
                safety: .caution, action: .removePaths([disk]), size: s, selected: false, wholeDelete: true))
        }

        let running = run(colima, ["status"]).0 == 0
        guard instanceNames.contains("colima") else { return }   // VM이 없으면 '시작' 안내도 하지 않음
        guard running, let docker = which("docker") else {
            items.append(CleanItem(
                group: g, title: L("이미지·컨테이너별로 보려면 Colima를 시작하세요", "Start Colima to see images and containers"),
                detail: L("지금은 Colima가 꺼져 있어서 안의 내용을 볼 수 없습니다. 시작에 1분 정도 걸립니다.", "Colima is stopped, so its contents can't be listed. Starting takes about a minute."),
                safety: .manual, action: .button(L("Colima 시작", "Start Colima"), colima, ["start"]), size: 0, selected: false))
            return
        }

        progress(L("Docker 이미지 확인", "Checking Docker images"))
        let (_, imgs) = run(docker, ["images", "--format", "{{.ID}}\t{{.Repository}}:{{.Tag}}\t{{.Size}}"])
        for line in imgs.split(separator: "\n") {
            let f = line.split(separator: "\t").map(String.init)
            guard f.count == 3 else { continue }
            items.append(CleanItem(group: g, title: L("이미지: \(f[1])", "Image: \(f[1])"), detail: "ID \(f[0])", safety: .caution,
                                   action: .command(docker, ["rmi", "-f", f[0]]), size: parseSize(f[2]), selected: false))
        }

        let (_, cons) = run(docker, ["ps", "-a", "--filter", "status=exited", "--filter", "status=created",
                                     "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}"])
        for line in cons.split(separator: "\n") {
            let f = line.split(separator: "\t").map(String.init)
            guard f.count == 3 else { continue }
            items.append(CleanItem(group: g, title: L("중지된 컨테이너: \(f[1])", "Stopped container: \(f[1])"), detail: L("이미지 \(f[2])", "Image \(f[2])"), safety: .safe,
                                   action: .command(docker, ["rm", f[0]]), size: 0, selected: false))
        }

        let (_, vols) = run(docker, ["volume", "ls", "-q", "--filter", "dangling=true"])
        for v in vols.split(separator: "\n").map(String.init) where !v.isEmpty {
            items.append(CleanItem(group: g, title: L("사용 안 하는 볼륨: \(v.prefix(24))", "Unused volume: \(v.prefix(24))"),
                                   detail: L("어떤 컨테이너에도 연결되지 않은 데이터 볼륨", "Data volume not attached to any container"), safety: .caution,
                                   action: .command(docker, ["volume", "rm", v]), size: 0, selected: false))
        }

        let (_, df) = run(docker, ["system", "df", "--format", "{{.Type}}\t{{.Size}}"])
        if let bc = df.split(separator: "\n").first(where: { $0.hasPrefix("Build Cache") }) {
            let s = parseSize(String(bc.split(separator: "\t").last ?? ""))
            if s > 0 {
                items.append(CleanItem(group: g, title: L("Docker 빌드 캐시", "Docker build cache"), detail: L("다음 빌드가 느려질 뿐입니다.", "The next build will just be slower."),
                                       safety: .safe, action: .command(docker, ["builder", "prune", "-af"]),
                                       size: s, selected: false))
            }
        }

        // Docker 안에서 지워도 VM 디스크 파일은 그대로라서 TRIM으로 되돌려줘야 함
        items.append(CleanItem(
            group: g, title: L("VM 디스크 빈 공간 반환 (TRIM)", "Return free VM disk space (TRIM)"),
            detail: L("Docker 항목을 지운 뒤 Mac 디스크로 공간을 돌려줍니다. 위 항목들과 함께 체크하세요 (마지막에 실행됨).", "Gives space back to your Mac after deleting Docker items. Check it together with the items above (runs last)."),
            safety: .safe, action: .command(colima, ["ssh", "--", "sudo", "fstrim", "-av"]), size: 0, selected: false))
    }

    // MARK: LM Studio

    static func scanLMStudio(_ items: inout [CleanItem], _ progress: (String) -> Void) {
        let g = "LM Studio"
        let models = h(".lmstudio/models")
        for publisher in children(models) where isDir(publisher) {
            for model in children(publisher) where isDir(model) {
                progress("LM Studio: \(model.lastPathComponent)")
                let s = size(of: model)
                guard s >= minChild else { continue }
                items.append(CleanItem(group: g, title: model.lastPathComponent,
                                       detail: L("AI 모델 · \(publisher.lastPathComponent). 다시 쓰려면 LM Studio에서 새로 받아야 합니다.", "AI model · \(publisher.lastPathComponent). You'd need to download it again in LM Studio."),
                                       safety: .caution, action: .removePaths([model]), size: s, selected: false))
            }
        }
        let backends = h(".lmstudio/extensions/backends/vendor")
        if exists(backends) {
            let s = size(of: backends)
            if s >= minChild {
                items.append(CleanItem(group: g, title: L("실행 엔진 (backends/vendor)", "Runtime engines (backends/vendor)"),
                                       detail: L("모델 실행용 라이브러리. LM Studio를 계속 쓴다면 남기세요.", "Libraries for running models. Keep them if you still use LM Studio."),
                                       safety: .caution, action: .removePaths([backends]), size: s, selected: false))
            }
        }
    }

    // MARK: Ollama

    static func scanOllama(_ items: inout [CleanItem], _ progress: (String) -> Void) {
        guard let ollama = which("ollama") else { return }
        progress(L("Ollama 모델 확인", "Checking Ollama models"))
        let (code, out) = run(ollama, ["list"])
        guard code == 0 else { return }
        for line in out.split(separator: "\n").dropFirst() {
            // NAME  ID  SIZE(숫자 단위)  MODIFIED
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count >= 4 else { continue }
            items.append(CleanItem(group: "Ollama", title: f[0], detail: L("Ollama AI 모델", "Ollama AI model"),
                                   safety: .caution, action: .command(ollama, ["rm", f[0]]),
                                   size: parseSize(f[2] + f[3]), selected: false))
        }
    }

    // MARK: Claude

    static func scanClaude(_ items: inout [CleanItem], _ progress: (String) -> Void) {
        let g = "Claude 앱 데이터"
        let base = h("Library/Application Support/Claude")
        let notes: [String: (String, Safety)] = [
            "vm_bundles": (L("Claude의 가상머신 이미지. 지우면 해당 기능을 쓸 때 다시 내려받아야 할 수 있습니다.", "Claude's virtual machine image. It may need to be downloaded again when you use that feature."), .caution),
            "Cache": (L("앱 캐시. 자동으로 다시 만들어집니다.", "App cache. Recreated automatically."), .safe),
            "Code Cache": (L("앱 코드 캐시. 자동으로 다시 만들어집니다.", "App code cache. Recreated automatically."), .safe),
            "GPUCache": (L("그래픽 캐시. 자동으로 다시 만들어집니다.", "Graphics cache. Recreated automatically."), .safe),
        ]
        for c in children(base) {
            progress("Claude: \(c.lastPathComponent)")
            let s = size(of: c)
            guard s >= minChild else { continue }
            let (detail, safety) = notes[c.lastPathComponent]
                ?? (L("Claude 앱이 사용하는 데이터. 무엇인지 확실하지 않으면 남겨두세요.", "Data used by the Claude app. Keep it if you're not sure what it is."), .caution)
            items.append(CleanItem(group: g, title: c.lastPathComponent,
                                   detail: detail + L(" Claude 앱을 종료한 뒤 정리하세요.", " Quit the Claude app before cleaning."),
                                   safety: safety, action: .removePaths([c]), size: s, selected: false))
        }
    }

    // MARK: Android

    static func scanAndroid(_ items: inout [CleanItem], _ progress: (String) -> Void) {
        let avd = h(".android/avd")
        for d in children(avd) where d.pathExtension == "avd" {
            progress("Android: \(d.lastPathComponent)")
            let s = size(of: d)
            guard s >= minChild else { continue }
            let ini = d.deletingPathExtension().appendingPathExtension("ini")
            items.append(CleanItem(group: "Android", title: L("에뮬레이터: \(d.deletingPathExtension().lastPathComponent)", "Emulator: \(d.deletingPathExtension().lastPathComponent)"),
                                   detail: L("Android 가상 기기와 그 안의 데이터", "Android virtual device and its data"), safety: .caution,
                                   action: .removePaths(exists(ini) ? [d, ini] : [d]), size: s, selected: false))
        }
        let sdk = h("Library/Android/sdk")
        for sub in ["system-images", "emulator", "ndk"] {
            let u = sdk.appendingPathComponent(sub)
            if exists(u) {
                progress("Android SDK: \(sub)")
                let s = size(of: u)
                if s >= minChild {
                    items.append(CleanItem(group: "Android", title: "SDK \(sub)",
                                           detail: L("Android Studio > SDK Manager에서 다시 설치할 수 있습니다.", "You can reinstall it from Android Studio > SDK Manager."),
                                           safety: .caution, action: .removePaths([u]), size: s, selected: false))
                }
            }
        }
    }

    static let minChild: Int64 = 50 * 1_000_000
}

// MARK: - Safety guard

/// 모든 삭제가 마지막으로 거치는 검사. 스캔 로직에 버그가 있어도
/// 홈 폴더·개인 문서·Library 최상위 폴더 같은 곳은 절대 지우지 않는다.
enum SafeDelete {
    static let home = Scanner.home.standardizedFileURL.path

    /// 이 폴더들 자체는 절대 삭제 불가 (안의 하위 항목은 허용)
    static let protectedDirs: Set<String> = Set([
        "", "Library", "Library/Application Support", "Library/Caches", "Library/Preferences",
        "Library/Containers", "Library/Group Containers", "Library/Logs", "Library/Developer",
        "Library/Developer/Xcode", "Library/Mobile Documents", "Library/Mail", "Library/Messages",
        "Library/Keychains", "Library/LaunchAgents", "Library/Saved Application State",
        "Library/HTTPStorages", "Library/WebKit", "Library/Cookies", "Library/Application Scripts",
        "Library/Preferences/ByHost", "Applications", ".lmstudio", ".android",
    ].map { $0.isEmpty ? home : home + "/" + $0 } + ["/Applications"])

    /// 이 폴더 아래는 어떤 경우에도 건드리지 않음
    static let forbiddenTrees: [String] = [
        "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public",
        "Library/Mobile Documents", "Library/Mail", "Library/Messages", "Library/Keychains",
        "Library/CloudStorage", ".ssh", ".gnupg",
    ].map { home + "/" + $0 }

    static func allowed(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        guard !p.contains("/../"), !protectedDirs.contains(p) else { return false }
        if forbiddenTrees.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return false }
        if p.hasPrefix(home + "/") { return true }
        // /Applications 아래는 .app 번들만 (바로 아래 또는 한 단계 하위 폴더)
        if p.hasPrefix("/Applications/") && p.hasSuffix(".app") {
            return p.dropFirst("/Applications/".count).split(separator: "/").count <= 2
        }
        return false
    }
}

// MARK: - ViewModel

@MainActor
final class Store: ObservableObject {
    @Published var items: [CleanItem] = []
    @Published var scanning = false
    @Published var cleaning = false
    @Published var status = L("‘검사’를 눌러 시작하세요.", "Press Scan to start.")
    @Published var useTrash = true
    @Published var log: [String] = []
    @Published var freeSpace: Int64 = 0
    @Published var totalSpace: Int64 = 0
    /// 마지막 정리 결과: 처리된 용량, 실패 메시지
    @Published var lastFreed: Int64? = nil
    @Published var lastFailures: [String] = []
    /// 펼쳐진 그룹 / 다른 화면에서 이동해 올 때 보여줄 그룹
    @Published var expanded: Set<String> = []
    @Published var focusGroup: String? = nil
    /// 추천 정리 대상: 검사 직후 기본 선택된 '안전' 항목
    @Published var recommendedIDs: Set<UUID> = []

    var recommended: [CleanItem] { items.filter { recommendedIDs.contains($0.id) } }
    var recommendedSize: Int64 { recommended.reduce(0) { $0 + $1.size } }
    var recommendedCount: Int { recommended.count }

    func cleanRecommended() {
        guard !busy, !recommended.isEmpty else { return }
        clean(recommended)
    }

    var busy: Bool { scanning || cleaning }
    var selectedSize: Int64 { items.filter { $0.selected }.reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter { $0.selected }.count }
    var groups: [String] {
        var seen: [String] = []
        for i in items where !seen.contains(i.group) { seen.append(i.group) }
        return seen
    }
    /// 그룹 표시 용량: 개별 항목 합계와 "전체 삭제" 항목 중 큰 값 (둘을 더하면 중복 계산)
    func groupSize(_ g: String) -> Int64 {
        let members = items.filter { $0.group == g && $0.checkable }
        let parts = members.filter { !$0.wholeDelete }.reduce(0) { $0 + $1.size }
        let whole = members.filter(\.wholeDelete).map(\.size).max() ?? 0
        return max(parts, whole)
    }
    func setGroup(_ g: String, _ on: Bool) {
        for i in items.indices where items[i].group == g && items[i].checkable && !items[i].wholeDelete {
            items[i].selected = on
        }
    }

    func refreshFree() {
        let v = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        freeSpace = v?.volumeAvailableCapacityForImportantUsage ?? 0
        totalSpace = Int64(v?.volumeTotalCapacity ?? 0)
    }

    func scan() {
        scanning = true
        items = []
        refreshFree()
        Task.detached {
            let result = Scanner.scan { msg in
                Task { @MainActor in self.status = L("검사 중: \(msg)", "Scanning: \(msg)") }
            }
            await MainActor.run {
                // 그룹 순서는 유지하고, 그룹 안에서만 큰 순서로 정렬
                var order: [String] = []
                for i in result where !order.contains(i.group) { order.append(i.group) }
                self.items = result.sorted {
                    let a = order.firstIndex(of: $0.group)!, b = order.firstIndex(of: $1.group)!
                    return a != b ? a < b : $0.size > $1.size
                }
                self.recommendedIDs = Set(self.items.filter { $0.selected && $0.safety == .safe && $0.checkable }.map(\.id))
                self.scanning = false
                self.status = L("검사 완료. 정리할 항목을 고르세요.", "Scan complete. Choose what to clean.")
            }
        }
    }

    func runButton(_ item: CleanItem) {
        guard case .button(_, let tool, let args) = item.action else { return }
        cleaning = true
        let command = "\(tool.split(separator: "/").last ?? "") \(args.joined(separator: " "))"
        status = L("실행 중: \(command)…", "Running: \(command)…")
        Task.detached {
            let (code, out) = Scanner.run(tool, args)
            await MainActor.run {
                self.cleaning = false
                if code != 0 { self.lastFailures = ["\(out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))"] }
                self.scan()
            }
        }
    }

    func clean(_ only: [CleanItem]? = nil) {
        // TRIM은 Docker 항목을 다 지운 뒤 실행되도록 맨 뒤로
        let picked = only ?? items.filter { $0.selected }
        let targets = picked.filter { !$0.title.contains("TRIM") } + picked.filter { $0.title.contains("TRIM") }
        let trash = useTrash
        cleaning = true
        log = []
        lastFreed = nil
        lastFailures = []
        Task.detached {
            let home = Scanner.home.path
            var freed: Int64 = 0
            var failures: [String] = []
            for item in targets {
                await MainActor.run { self.status = L("정리 중: \(item.title)", "Cleaning: \(item.title)") }
                let msg: String
                switch item.action {
                case .removePaths(let urls):
                    var fails = 0
                    for u in urls {
                        guard SafeDelete.allowed(u) else { fails += 1; continue }
                        do {
                            if trash { try FileManager.default.trashItem(at: u, resultingItemURL: nil) }
                            else { try FileManager.default.removeItem(at: u) }
                        } catch { fails += 1 }
                    }
                    if fails == 0 { freed += item.size } else { failures.append(L("\(item.title): \(fails)개를 지우지 못함 (사용 중이거나 권한 없음)", "\(item.title): couldn't remove \(fails) (in use or no permission)")) }
                    msg = fails == 0 ? "✓ \(item.title)" : L("△ \(item.title) — \(fails)개 실패 (사용 중이거나 권한 없음)", "△ \(item.title) — \(fails) failed (in use or no permission)")
                case .command(let tool, let args):
                    let (code, out) = Scanner.run(tool, args)
                    let left = item.expectGone.filter { AppFinder.present($0) }
                    if code != 0 {
                        failures.append("\(item.title): \(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))")
                    } else if !left.isEmpty {
                        failures.append(L("\(item.title): 명령은 끝났지만 파일이 남아 있습니다 — ", "\(item.title): the command finished but files remain — ")
                                        + left.map { $0.path.replacingOccurrences(of: home, with: "~") }.joined(separator: ", "))
                    } else {
                        freed += item.size
                    }
                    msg = code == 0 && left.isEmpty ? "✓ \(item.title)" : "✗ \(item.title)"
                case .reveal, .button:
                    continue
                }
                await MainActor.run { self.log.append(msg) }
            }
            await MainActor.run { [freed, failures] in
                self.lastFreed = freed
                self.lastFailures = failures
                self.cleaning = false
                self.refreshFree()
                self.status = trash ? L("완료. 휴지통을 비워야 공간이 확보됩니다.", "Done. Empty the Trash to free up the space.") : L("완료.", "Done.")
                self.scan()
            }
        }
    }
}

// MARK: - UI

func fmt(_ b: Int64) -> String {
    b <= 0 ? "—" : ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
}

#if !TEST
@main
struct SpaceSweepApp: App {
    var body: some Scene {
        WindowGroup("SpaceSweep") { RootView() }
            .windowResizability(.contentMinSize)
    }
}
#endif
