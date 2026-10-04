import SwiftUI
import AppKit

// MARK: - Model

/// "시스템 데이터"를 구성하는 항목 하나와, 사용자가 할 수 있는 일
struct SysCategory: Identifiable {
    enum Kind {
        /// 공간 정리 화면의 해당 그룹에서 정리
        case clean(group: String)
        /// 앱 제거 화면에서 정리
        case apps
        /// 다른 앱에서 직접 관리 (버튼으로 열어줌)
        case manual(label: String, open: URL)
        /// macOS가 알아서 관리 — 건드리지 않는 게 맞음
        case system
    }

    var id: String { title }
    let title: String
    let icon: String
    let color: Color
    let explain: String
    let kind: Kind
    var size: Int64
    /// 큰 하위 항목 (이름, 크기, 위치)
    var top: [(String, Int64, URL)]
}

enum SystemAnalyzer {
    static func sizeAll(_ urls: [URL]) -> Int64 { urls.reduce(0) { $0 + Scanner.size(of: $1) } }

    static func topChildren(_ dirs: [URL], limit: Int = 4, exclude: Set<String> = []) -> [(String, Int64, URL)] {
        var all: [(String, Int64, URL)] = []
        for d in dirs {
            for c in Scanner.children(d) where !exclude.contains(c.lastPathComponent) {
                let s = Scanner.size(of: c)
                if s >= 100_000_000 { all.append((c.lastPathComponent, s, c)) }
            }
        }
        return Array(all.sorted { $0.1 > $1.1 }.prefix(limit))
    }

    static func analyze(progress: @escaping (String) -> Void) -> [SysCategory] {
        let h = Scanner.h
        var out: [SysCategory] = []

        func add(_ title: String, _ icon: String, _ color: Color, _ explain: String, _ kind: SysCategory.Kind,
                 _ urls: [URL], top: [(String, Int64, URL)] = []) {
            progress(title)
            let s = sizeAll(urls.filter { Scanner.exists($0) })
            guard s >= 50_000_000 else { return }
            out.append(SysCategory(title: title, icon: icon, color: color, explain: explain, kind: kind, size: s, top: top))
        }

        // 개발 도구
        let assets = URL(fileURLWithPath: "/System/Library/AssetsV2")
        let simAssets = Scanner.children(assets).filter { $0.lastPathComponent.contains("SimulatorRuntime") }
        add(L("iOS 시뮬레이터", "iOS Simulators"), "iphone.gen3", .blue,
            L("Xcode가 내려받은 iPhone 시뮬레이터 런타임과 시뮬레이터 기기 데이터. 안 쓰는 버전은 지워도 됩니다.", "iPhone simulator runtimes downloaded by Xcode, plus simulator device data. Versions you don't use can be deleted."),
            .clean(group: "Xcode"),
            simAssets + [URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches"), h("Library/Developer/CoreSimulator")])
        add(L("Xcode 빌드 파일", "Xcode Build Files"), "hammer", .indigo,
            L("빌드 중간 결과물과 연결했던 iPhone의 디버그 심볼. 지워도 필요할 때 다시 만들어집니다.", "Intermediate build products and debug symbols for iPhones you connected. Recreated when needed."),
            .clean(group: "Xcode"), [h("Library/Developer/Xcode")],
            top: topChildren([h("Library/Developer/Xcode")]))

        // 앱
        progress(L("앱 데이터", "App data"))
        add(L("앱 데이터", "App data"), "square.stack.3d.up", .purple,
            L("설치된 앱들이 저장한 데이터. 안 쓰는 앱은 '앱 제거'에서 데이터까지 함께 지우세요.", "Data saved by installed apps. Remove apps you don't use, with their data, in Uninstall Apps."),
            .apps, [h("Library/Application Support"), h("Library/Containers")],
            top: topChildren([h("Library/Application Support")]))
        add(L("앱 캐시", "App Caches"), "tray.full", .teal,
            L("앱이 임시로 저장한 파일. 지워도 필요하면 다시 생깁니다.", "Temporary files saved by apps. Recreated when needed."),
            .clean(group: "앱 캐시"),
            [h("Library/Caches"), URL(fileURLWithPath: confstr(_CS_DARWIN_USER_CACHE_DIR))],
            top: topChildren([h("Library/Caches")]))

        // 홈 폴더의 숨김 폴더 (.vscode, .cache, .colima 등) — Finder에 안 보여서 시스템 데이터로 잡힘
        progress(L("숨김 폴더", "Hidden folders"))
        let dotDirs = Scanner.childrenIncludingHidden(Scanner.home).filter {
            $0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != ".Trash" && Scanner.isDir($0)
        }
        add(L("홈 폴더의 숨김 폴더", "Hidden Folders in Home"), "eye.slash", .orange,
            L("개발 도구·AI 모델·Docker 등이 홈 폴더에 숨겨 둔 파일. Finder에 보이지 않아 시스템 데이터로 분류됩니다.", "Files hidden in your home folder by developer tools, AI models, Docker and more. Finder doesn't show them, so they count as System Data."),
            .clean(group: "개발 도구 캐시"), dotDirs,
            top: Array(dotDirs.map { ($0.lastPathComponent, Scanner.size(of: $0), $0) }
                .filter { $0.1 >= 100_000_000 }.sorted { $0.1 > $1.1 }.prefix(5)))
        add(L("Android 개발 도구", "Android Developer Tools"), "apps.iphone", .green,
            L("Android Studio의 SDK와 에뮬레이터 이미지.", "Android Studio SDK and emulator images."),
            .clean(group: "Android"), [h("Library/Android")])

        // 시스템 전체가 쓰는 앱 데이터 (/Library/Application Support) — 음악 제작 라이브러리 등
        let sharedSupport = URL(fileURLWithPath: "/Library/Application Support")
        let steinbergManager = URL(fileURLWithPath: "/Applications/Steinberg Library Manager.app")
        add(L("공용 앱 데이터 (/Library)", "Shared App Data (/Library)"), "music.note.list", .pink,
            L("모든 사용자가 함께 쓰는 앱 데이터. 음악 제작 프로그램의 사운드 라이브러리처럼 큰 파일이 여기 있습니다. 관리자 권한이 필요해 해당 앱에서 지우는 게 안전합니다.", "App data shared by all users. Large files like sound libraries for music apps live here. Deleting needs admin rights, so it's safest to remove them from the app that installed them."),
            Scanner.exists(steinbergManager)
                ? .manual(label: L("Steinberg Library Manager 열기", "Open Steinberg Library Manager"), open: steinbergManager)
                : .manual(label: L("Finder에서 보기", "Show in Finder"), open: sharedSupport),
            [sharedSupport], top: topChildren([sharedSupport]))

        // macOS가 관리하는 것들
        let otherAssets = Scanner.children(assets).filter { !$0.lastPathComponent.contains("SimulatorRuntime") }
        add(L("macOS 다운로드 에셋", "macOS Downloaded Assets"), "arrow.down.circle", .gray,
            L("Siri·받아쓰기·글꼴·언어·사진 분석용 데이터. macOS가 필요에 따라 받고 지우므로 그대로 두세요.", "Data for Siri, dictation, fonts, languages and photo analysis. macOS downloads and removes it as needed, so leave it alone."),
            .system, otherAssets)
        add(L("시스템 로그·진단 기록", "System Logs & Diagnostics"), "doc.text.magnifyingglass", .gray,
            L("배터리 사용 기록과 진단 로그. macOS가 오래된 것부터 자동으로 지웁니다.", "Battery usage history and diagnostic logs. macOS deletes the oldest automatically."),
            .system, ["powerlog", "diagnostics", "uuidtext", "DiagnosticPipeline"]
                .map { URL(fileURLWithPath: "/private/var/db/" + $0) } + [URL(fileURLWithPath: "/private/var/log")])
        add(L("가상 메모리 (스왑)", "Virtual Memory (Swap)"), "memorychip", .gray,
            L("메모리가 부족할 때 디스크를 대신 쓰는 공간. Mac을 재시동하면 줄어듭니다.", "Disk space used when memory runs low. Shrinks when you restart your Mac."),
            .system, [URL(fileURLWithPath: "/private/var/vm")])
        add(L("임시 파일", "Temporary Files"), "clock.arrow.circlepath", .gray,
            L("앱들이 잠깐 쓰는 파일. 재시동할 때 macOS가 정리합니다.", "Short-lived files used by apps. macOS clears them on restart."),
            .system, [URL(fileURLWithPath: confstr(_CS_DARWIN_USER_TEMP_DIR))])
        add(L("macOS 업데이트 파일", "macOS Update Files"), "arrow.triangle.2.circlepath", .gray,
            L("내려받은 macOS 업데이트. 설치가 끝나면 macOS가 지웁니다.", "Downloaded macOS updates. macOS deletes them after installing."),
            .system, [URL(fileURLWithPath: "/Library/Updates")])

        return out.sorted { a, b in
            // 내가 정리할 수 있는 것을 먼저, 그 안에서는 큰 순서
            let ra = { if case .system = a.kind { return 1 } else { return 0 } }()
            let rb = { if case .system = b.kind { return 1 } else { return 0 } }()
            return ra != rb ? ra < rb : a.size > b.size
        }
    }

    static func confstr(_ name: Int32) -> String {
        let len = Darwin.confstr(name, nil, 0)
        guard len > 0 else { return NSTemporaryDirectory() }
        var buf = [CChar](repeating: 0, count: len)
        Darwin.confstr(name, &buf, len)
        return String(cString: buf)
    }
}

@MainActor
final class SystemStore: ObservableObject {
    @Published var categories: [SysCategory] = []
    @Published var analyzing = false
    @Published var status = ""

    var total: Int64 { categories.reduce(0) { $0 + $1.size } }
    var actionable: Int64 {
        categories.filter { if case .system = $0.kind { return false } else { return true } }.reduce(0) { $0 + $1.size }
    }

    func analyze() {
        guard !analyzing else { return }
        analyzing = true
        Task.detached {
            let r = SystemAnalyzer.analyze { msg in Task { @MainActor in self.status = msg } }
            await MainActor.run {
                self.categories = r
                self.analyzing = false
            }
        }
    }
}

// MARK: - 개요 화면

struct OverviewView: View {
    @ObservedObject var cleaner: Store
    @ObservedObject var system: SystemStore
    let go: (Page, String?) -> Void
    @State var confirmRecommended = false
    @State var openRows: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                diskCard
                recommendedCard
                systemDataSection
            }
            .padding(24)
        }
        .navigationTitle(L("개요", "Overview"))
        .toolbar {
            ToolbarItem {
                Button { system.analyze(); cleaner.scan() } label: { Label(L("다시 분석", "Analyze Again"), systemImage: "arrow.clockwise") }
                    .disabled(system.analyzing || cleaner.busy)
            }
        }
        .onAppear {
            if system.categories.isEmpty { system.analyze() }
            if cleaner.items.isEmpty && !cleaner.busy { cleaner.scan() }
        }
        .confirmationDialog(L("추천 항목 \(fmt(cleaner.recommendedSize))를 정리할까요?", "Clean up \(fmt(cleaner.recommendedSize)) of recommended items?"),
                            isPresented: $confirmRecommended, titleVisibility: .visible) {
            Button(L("휴지통으로 옮기기", "Move to Trash")) { cleaner.cleanRecommended() }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("'안전' 표시가 붙은 항목만 정리합니다. 캐시·빌드 파일처럼 지워도 다시 생기는 것들입니다. 파일은 휴지통으로 이동합니다.", "Only items marked Safe are cleaned — things like caches and build files that are recreated automatically. Files are moved to the Trash."))
        }
    }

    // 디스크 사용량
    var diskCard: some View {
        let used = max(cleaner.totalSpace - cleaner.freeSpace, 0)
        let total = max(cleaner.totalSpace, 1)
        let sys = min(system.total, used)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Macintosh HD").font(.title2.weight(.bold))
                Spacer()
                Text(L("\(fmt(cleaner.freeSpace)) 사용 가능", "\(fmt(cleaner.freeSpace)) available")).font(.title3.weight(.semibold)).foregroundStyle(.green)
                Text("/ \(fmt(cleaner.totalSpace))").foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 2) {
                    Rectangle().fill(Color.orange.gradient)
                        .frame(width: w * CGFloat(Double(sys) / Double(total)))
                    Rectangle().fill(Color.accentColor.gradient)
                        .frame(width: max(w * CGFloat(Double(used - sys) / Double(total)) - 2, 0))
                    Rectangle().fill(.quaternary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 22)
            HStack(spacing: 18) {
                let sysText = system.analyzing && system.categories.isEmpty ? L("계산 중…", "Calculating…") : fmt(system.total)
                legendDot(.orange, L("분석된 시스템 데이터 \(sysText)", "Analyzed System Data \(sysText)"))
                legendDot(.accentColor, L("앱·문서 등 \(fmt(max(used - sys, 0)))", "Apps, documents, etc. \(fmt(max(used - sys, 0)))"))
                legendDot(.gray.opacity(0.4), L("남은 공간", "Free space"))
            }
            .font(.caption)
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { Circle().fill(c).frame(width: 9, height: 9); Text(t).foregroundStyle(.secondary) }
    }

    // 추천 정리 (원클릭)
    var recommendedCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "wand.and.stars").font(.system(size: 30)).foregroundStyle(Color.accentColor)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("추천 정리", "Recommended Cleanup")).font(.headline)
                if cleaner.scanning {
                    Text(L("지울 수 있는 파일을 찾는 중…", "Looking for files you can delete…")).foregroundStyle(.secondary)
                } else if cleaner.cleaning {
                    Text(cleaner.status).foregroundStyle(.secondary).lineLimit(1)
                } else if let freed = cleaner.lastFreed {
                    Text(L("\(fmt(freed)) 정리 완료 · 휴지통을 비우면 공간이 늘어납니다", "Cleaned \(fmt(freed)) · empty the Trash to free the space")).foregroundStyle(.green)
                } else {
                    Text(L("지워도 자동으로 다시 생기는 캐시·빌드 파일 \(cleaner.recommendedCount)개를 한 번에 정리합니다.", "Clean \(cleaner.recommendedCount) caches and build files that are recreated automatically, in one step."))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if cleaner.lastFreed != nil && !cleaner.busy {
                Button(L("휴지통 열기", "Open Trash"), action: openTrash).controlSize(.large)
            }
            Button(L("직접 고르기", "Choose Myself")) { go(.clean, nil) }.controlSize(.large)
            Button {
                confirmRecommended = true
            } label: {
                Text(cleaner.busy ? L("잠시만요…", "One moment…") : L("\(fmt(cleaner.recommendedSize)) 정리", "Clean \(fmt(cleaner.recommendedSize))")).fontWeight(.semibold).frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(cleaner.busy || cleaner.recommendedSize == 0)
        }
        .padding(18)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.25)))
    }

    // 시스템 데이터 분석
    var systemDataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("시스템 데이터는 무엇으로 차 있나요?", "What's in System Data?")).font(.title3.weight(.bold))
                Spacer()
                if system.analyzing {
                    ProgressView().controlSize(.small)
                    Text(system.status).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 160)
                }
            }
            Text(L("macOS 설정의 '시스템 데이터'는 사진·문서·앱으로 분류되지 않는 모든 파일입니다. 아래는 그중 크기를 잴 수 있는 부분입니다. 회색 항목은 macOS가 알아서 관리하니 그대로 두세요.", "“System Data” in macOS Settings is every file that isn't classified as photos, documents or apps. Below are the parts that can be measured. Gray items are managed by macOS, so leave them alone."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if system.categories.isEmpty && system.analyzing {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(30)
            }
            let maxSize = max(system.categories.map(\.size).max() ?? 1, 1)
            VStack(spacing: 0) {
                ForEach(system.categories) { c in
                    categoryRow(c, maxSize: maxSize)
                    if c.id != system.categories.last?.id { Divider().padding(.leading, 60) }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    func categoryRow(_ c: SysCategory, maxSize: Int64) -> some View {
        let isSystem: Bool = { if case .system = c.kind { return true } else { return false } }()
        let open = openRows.contains(c.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: c.icon).font(.title3).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(c.color.gradient, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(c.title).fontWeight(.semibold)
                        if isSystem {
                            Text(L("macOS 관리", "Managed by macOS")).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(fmt(c.size)).font(.headline).monospacedDigit()
                    }
                    GeometryReader { g in
                        Capsule().fill(.quaternary).overlay(alignment: .leading) {
                            Capsule().fill(c.color.opacity(isSystem ? 0.4 : 0.85))
                                .frame(width: max(g.size.width * CGFloat(Double(c.size) / Double(maxSize)), 4))
                        }
                    }
                    .frame(height: 5)
                    Text(c.explain).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                actionButton(c).frame(minWidth: 120, alignment: .trailing)
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !c.top.isEmpty else { return }
                if open { openRows.remove(c.id) } else { openRows.insert(c.id) }
            }

            if open {
                VStack(spacing: 0) {
                    ForEach(Array(c.top.enumerated()), id: \.offset) { _, entry in
                        let (name, size, url) = entry
                        HStack {
                            Text(name).font(.callout)
                            Spacer()
                            Text(fmt(size)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                                Image(systemName: "magnifyingglass.circle")
                            }.buttonStyle(.borderless).help(L("Finder에서 위치 보기", "Show in Finder"))
                        }
                        .padding(.vertical, 5)
                    }
                }
                .padding(.leading, 62).padding(.trailing, 14).padding(.bottom, 10)
            } else if !c.top.isEmpty {
                Text(L("큰 항목 \(c.top.count)개 보기 ▾", "Show \(c.top.count) largest items ▾")).font(.caption).foregroundStyle(Color.accentColor)
                    .padding(.leading, 62).padding(.bottom, 10)
                    .onTapGesture { openRows.insert(c.id) }
            }
        }
    }

    @ViewBuilder func actionButton(_ c: SysCategory) -> some View {
        switch c.kind {
        case .clean(let g):
            Button(L("정리하기 →", "Clean Up →")) { go(.clean, g) }
        case .apps:
            Button(L("앱 제거로 →", "Uninstall Apps →")) { go(.apps, nil) }
        case .manual(let label, let url):
            Button(label) {
                if url.pathExtension == "app" { NSWorkspace.shared.open(url) }
                else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        case .system:
            Text(L("그대로 두세요", "Leave as is")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
