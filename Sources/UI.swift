import SwiftUI
import AppKit

// MARK: - 공통

enum Page: String, CaseIterable, Identifiable {
    case overview, clean, apps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return L("개요", "Overview")
        case .clean: return L("공간 정리", "Clean Up")
        case .apps: return L("앱 제거", "Uninstall Apps")
        }
    }
    var icon: String {
        switch self {
        case .overview: return "chart.pie"
        case .clean: return "sparkles"
        case .apps: return "xmark.app"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return L("무엇이 공간을 차지하나", "What's using space")
        case .clean: return L("항목을 골라 정리", "Pick items to clean")
        case .apps: return L("앱과 남은 데이터 함께", "Apps and their leftovers")
        }
    }
}

struct GroupInfo {
    let icon: String
    let blurb: String

    static func of(_ g: String) -> GroupInfo {
        switch g {
        case "앱 캐시": return .init(icon: "tray.full", blurb: L("앱이 임시로 저장한 파일. 지워도 필요하면 자동으로 다시 생깁니다.", "Temporary files saved by apps. Recreated automatically when needed."))
        case "개발 도구 캐시": return .init(icon: "terminal", blurb: L("npm·pip·Gradle 등이 내려받아 둔 파일.", "Files downloaded by npm, pip, Gradle and others."))
        case "Xcode": return .init(icon: "hammer", blurb: L("빌드 결과물과 iPhone 시뮬레이터.", "Build products and iPhone simulators."))
        case "시스템": return .init(icon: "gearshape", blurb: L("Time Machine 로컬 스냅샷과 기기 백업.", "Time Machine local snapshots and device backups."))
        case "Colima (Docker)": return .init(icon: "shippingbox", blurb: L("Docker 가상머신. 컨테이너 데이터가 들어 있습니다.", "Docker virtual machine. Contains your container data."))
        case "LM Studio", "Ollama": return .init(icon: "cpu", blurb: L("내려받은 AI 모델. 다시 쓰려면 새로 받아야 합니다.", "Downloaded AI models. You'd need to download them again to use them."))
        case "Claude 앱 데이터": return .init(icon: "bubble.left.and.text.bubble.right", blurb: L("Claude 데스크톱 앱 데이터. 앱을 종료한 뒤 정리하세요.", "Claude desktop app data. Quit the app before cleaning."))
        case "Android": return .init(icon: "iphone", blurb: L("Android 에뮬레이터와 SDK.", "Android emulators and SDK."))
        case "Docker Desktop": return .init(icon: "shippingbox", blurb: L("Docker Desktop 앱 데이터.", "Docker Desktop app data."))
        default: return .init(icon: "folder", blurb: "")
        }
    }
}

struct SafetyPill: View {
    let safety: Safety
    var body: some View {
        Text(safety.label).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(safety.color.opacity(0.15), in: Capsule())
            .foregroundStyle(safety.color)
    }
}

/// 체크 / 일부 체크 / 해제 3단계 체크박스
struct TriCheck: View {
    enum State { case on, mixed, off }
    let state: State
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: state == .on ? "checkmark.square.fill" : state == .mixed ? "minus.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

struct Banner: View {
    let icon: String
    let color: Color
    let title: String
    var detail: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                if let d = detail { Text(d).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Spacer()
            if let l = actionLabel, let a = action { Button(l, action: a) }
            if let c = onClose {
                Button(action: c) { Image(systemName: "xmark") }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

func openTrash() { NSWorkspace.shared.open(Scanner.h(".Trash")) }

// MARK: - 루트

struct RootView: View {
    @State var page: Page = .overview
    @State var expandAll = false
    @StateObject var cleaner = Store()
    @StateObject var uninstaller = UninstallStore()
    @StateObject var system = SystemStore()

    func go(_ p: Page, _ group: String?) {
        if let g = group {
            cleaner.expanded.insert(g)
            cleaner.focusGroup = g
        }
        page = p
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.title)
                        Text(p.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: p.icon) }
                .padding(.vertical, 4)
                .tag(p)
            }
            .safeAreaInset(edge: .bottom) { DiskMeter(store: cleaner).padding(12) }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 260)
        } detail: {
            switch page {
            case .overview: OverviewView(cleaner: cleaner, system: system, go: go)
            case .clean: CleanerView(store: cleaner, expandAll: expandAll)
            case .apps: UninstallerView(store: uninstaller)
            }
        }
        .frame(minWidth: 1020, minHeight: 660)
        .onAppear {
            cleaner.refreshFree()
            // 화면 확인용 실행 옵션 (아무것도 지우지 않음): -autoscan, -page apps, -select <번들ID>
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-autoscan") { cleaner.scan() }
            if args.contains("-expand") { expandAll = true }
            if let i = args.firstIndex(of: "-page"), i + 1 < args.count {
                page = ["apps": .apps, "clean": .clean][args[i + 1]] ?? .overview
            }
            if let i = args.firstIndex(of: "-select"), i + 1 < args.count {
                let bid = args[i + 1]
                Task {
                    for _ in 0..<50 where uninstaller.apps.isEmpty { try? await Task.sleep(nanoseconds: 100_000_000) }
                    if let a = uninstaller.apps.first(where: { $0.bundleID == bid }) { uninstaller.select(a.id) }
                }
            }
        }
    }
}

/// 사이드바 하단 디스크 사용량
struct DiskMeter: View {
    @ObservedObject var store: Store
    var body: some View {
        let used = max(store.totalSpace - store.freeSpace, 0)
        let ratio = store.totalSpace > 0 ? Double(used) / Double(store.totalSpace) : 0
        VStack(alignment: .leading, spacing: 6) {
            Label("Macintosh HD", systemImage: "internaldrive").font(.caption.weight(.semibold))
            ProgressView(value: ratio).tint(ratio > 0.85 ? .red : ratio > 0.7 ? .orange : .accentColor)
            Text(L("\(fmt(store.freeSpace)) 사용 가능", "\(fmt(store.freeSpace)) available")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 공간 정리

struct CleanerView: View {
    @ObservedObject var store: Store
    var expandAll = false
    @State var confirm = false

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                summary
                                banners
                                legend
                                ForEach(store.groups, id: \.self) { groupCard($0).id($0) }
                            }
                            .padding(20)
                        }
                        // 개요 화면에서 '정리하기 →'로 왔으면 해당 그룹으로 스크롤
                        .onAppear { scrollToFocus(proxy) }
                        .onChange(of: store.focusGroup) { scrollToFocus(proxy) }
                        .onChange(of: store.scanning) { scrollToFocus(proxy) }
                    }
                    Divider()
                    actionBar
                }
            }
        }
        .navigationTitle(L("공간 정리", "Clean Up"))
        .toolbar {
            ToolbarItem {
                Button { store.scan() } label: { Label(L("다시 검사", "Rescan"), systemImage: "arrow.clockwise") }
                    .disabled(store.busy).help(L("다시 검사 (⌘R)", "Rescan (⌘R)")).keyboardShortcut("r")
            }
        }
        .confirmationDialog(L("\(fmt(store.selectedSize))를 정리할까요?", "Clean up \(fmt(store.selectedSize))?"), isPresented: $confirm, titleVisibility: .visible) {
            Button(store.useTrash ? L("휴지통으로 옮기기", "Move to Trash") : L("영구 삭제", "Delete Permanently"), role: .destructive) { store.clean() }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: { Text(confirmMessage) }
    }

    func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let g = store.focusGroup, store.groups.contains(g) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation { proxy.scrollTo(g, anchor: .top) }
            store.focusGroup = nil
        }
    }

    // 검사 전 / 검사 중 화면
    var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: store.scanning ? "magnifyingglass" : "sparkles")
                .font(.system(size: 54)).foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, isActive: store.scanning)
            Text(store.scanning ? L("검사하는 중…", "Scanning…") : L("Mac에서 지울 수 있는 공간을 찾아볼게요", "Let's find space you can free up on your Mac"))
                .font(.title2.weight(.semibold))
            if store.scanning {
                ProgressView().controlSize(.small)
                Text(store.status.replacingOccurrences(of: L("검사 중: ", "Scanning: "), with: ""))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 400)
            } else {
                Text(L("검사는 아무것도 지우지 않습니다. 결과를 보고 직접 고르세요.", "Scanning doesn't delete anything. You choose what to clean from the results."))
                    .foregroundStyle(.secondary)
                Button { store.scan() } label: {
                    Text(L("검사 시작", "Start Scan")).font(.headline).frame(width: 160, height: 32)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 상단 요약 카드
    var summary: some View {
        let reclaimable = store.groups.reduce(0) { $0 + store.groupSize($1) }
        return HStack(spacing: 12) {
            stat(L("찾은 항목", "Found"), "\(fmt(reclaimable))", L("정리 가능한 전체 용량", "Total space you can free"), .secondary)
            stat(L("선택함", "Selected"), "\(fmt(store.selectedSize))", L("\(store.selectedCount)개 항목", "\(store.selectedCount) items"), .accentColor)
            stat(L("지금 사용 가능", "Available now"), "\(fmt(store.freeSpace))", L("정리 후 약 \(fmt(store.freeSpace + store.selectedSize))", "About \(fmt(store.freeSpace + store.selectedSize)) after cleaning"), .green)
        }
    }

    func stat(_ title: String, _ value: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(color)
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder var banners: some View {
        if let freed = store.lastFreed {
            Banner(icon: "checkmark.circle.fill", color: .green,
                   title: L("\(fmt(freed)) 정리했어요", "Cleaned \(fmt(freed))"),
                   detail: store.useTrash ? L("파일은 휴지통에 있습니다. 휴지통을 비워야 실제 공간이 늘어납니다.", "The files are in the Trash. Empty the Trash to actually free the space.") : nil,
                   actionLabel: store.useTrash ? L("휴지통 열기", "Open Trash") : nil, action: openTrash,
                   onClose: { store.lastFreed = nil })
        }
        if !store.lastFailures.isEmpty {
            Banner(icon: "exclamationmark.triangle.fill", color: .orange,
                   title: L("일부 항목을 정리하지 못했어요", "Some items couldn't be cleaned"),
                   detail: store.lastFailures.joined(separator: "\n"),
                   onClose: { store.lastFailures = [] })
        }
    }

    var legend: some View {
        HStack(spacing: 16) {
            legendItem(.safe, L("지워도 자동으로 다시 생김", "Recreated automatically"))
            legendItem(.caution, L("다시 받아야 하거나 데이터가 사라짐", "Must be re-downloaded, or data is lost"))
            legendItem(.manual, L("안내만 표시", "Guidance only"))
            Spacer()
        }
        .font(.caption)
    }

    func legendItem(_ s: Safety, _ text: String) -> some View {
        HStack(spacing: 4) { SafetyPill(safety: s); Text(text).foregroundStyle(.secondary) }
    }

    // 그룹 카드
    func groupCard(_ g: String) -> some View {
        let info = GroupInfo.of(g)
        let members = store.items.filter { $0.group == g }
        let bulk = members.filter { $0.checkable && !$0.wholeDelete }
        let picked = members.filter(\.selected)
        let state: TriCheck.State = bulk.isEmpty || picked.isEmpty ? .off
            : bulk.allSatisfy(\.selected) ? .on : .mixed
        let isOpen = expandAll || store.expanded.contains(g)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if bulk.isEmpty {
                    Image(systemName: "square").font(.title3).hidden()
                } else {
                    TriCheck(state: state) { store.setGroup(g, state != .on) }
                        .help(state == .on ? L("이 그룹 모두 해제", "Deselect this group") : L("이 그룹 모두 선택", "Select this group"))
                }
                Image(systemName: info.icon).font(.title3).frame(width: 26).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupTitle(g)).font(.headline)
                    Text(picked.isEmpty ? info.blurb : L("\(picked.count)개 선택 · \(fmt(picked.reduce(0) { $0 + $1.size }))", "\(picked.count) selected · \(fmt(picked.reduce(0) { $0 + $1.size }))"))
                        .font(.caption).foregroundStyle(picked.isEmpty ? .secondary : Color.accentColor).lineLimit(1)
                }
                Spacer()
                Text(fmt(store.groupSize(g))).font(.title3.weight(.semibold)).monospacedDigit()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { store.expanded.remove(g) } else { store.expanded.insert(g) }
                }
            }

            if isOpen {
                Divider().padding(.leading, 14)
                VStack(spacing: 0) {
                    ForEach(members) { item in
                        itemRow(item)
                        if item.id != members.last?.id { Divider().padding(.leading, 50) }
                    }
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    func itemRow(_ i: CleanItem) -> some View {
        let binding = Binding(
            get: { store.items.first { $0.id == i.id }?.selected ?? false },
            set: { v in if let k = store.items.firstIndex(where: { $0.id == i.id }) { store.items[k].selected = v } })
        return HStack(alignment: .top, spacing: 12) {
            if i.checkable {
                Toggle("", isOn: binding).toggleStyle(.checkbox).labelsHidden()
            } else {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(i.title).fontWeight(.medium)
                    SafetyPill(safety: i.safety)
                }
                Text(i.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if case .button(let label, _, _) = i.action {
                    Button(label) { store.runButton(i) }.disabled(store.busy).padding(.top, 4)
                }
            }
            Spacer()
            if let u = i.revealURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([u]) } label: {
                    Image(systemName: "magnifyingglass.circle")
                }.buttonStyle(.borderless).help(L("Finder에서 위치 보기", "Show in Finder"))
            }
            Text(fmt(i.size)).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
                .foregroundStyle(i.size > 5_000_000_000 ? .primary : .secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .padding(.leading, 22)
        .contentShape(Rectangle())
        .onTapGesture { if i.checkable { binding.wrappedValue.toggle() } }
    }

    // 하단 실행 바
    var actionBar: some View {
        HStack(spacing: 14) {
            if store.cleaning {
                ProgressView().controlSize(.small)
                Text(store.status).foregroundStyle(.secondary).lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.selectedCount == 0 ? L("정리할 항목을 고르세요", "Choose items to clean") : L("\(store.selectedCount)개 항목 선택됨", "\(store.selectedCount) items selected"))
                        .fontWeight(.medium)
                    Toggle(L("휴지통 거치기 (되돌릴 수 있음)", "Use Trash (can be undone)"), isOn: $store.useTrash)
                        .toggleStyle(.checkbox).font(.caption)
                }
            }
            Spacer()
            Button(action: openTrash) { Label(L("휴지통", "Trash"), systemImage: "trash") }
            Button { confirm = true } label: {
                Text(store.selectedCount == 0 ? L("정리하기", "Clean Up") : L("\(fmt(store.selectedSize)) 정리하기", "Clean Up \(fmt(store.selectedSize))"))
                    .fontWeight(.semibold).frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(store.selectedCount == 0 || store.busy)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    var confirmMessage: String {
        let picked = store.items.filter(\.selected)
        var lines: [String] = []
        let files = picked.filter { if case .removePaths = $0.action { return true } else { return false } }
        let cmds = picked.filter { if case .command = $0.action { return true } else { return false } }
        if !files.isEmpty {
            lines.append(store.useTrash ? L("• 파일 \(files.count)개 항목 → 휴지통으로 이동 (되돌릴 수 있음)", "• \(files.count) file items → moved to Trash (can be undone)")
                                        : L("• 파일 \(files.count)개 항목 → 영구 삭제 (되돌릴 수 없음)", "• \(files.count) file items → deleted permanently (cannot be undone)"))
        }
        if !cmds.isEmpty {
            let names = cmds.map(\.title).joined(separator: ", ")
            lines.append(L("• \(names) → 바로 삭제 (휴지통을 거치지 않음)", "• \(names) → deleted immediately (skips the Trash)"))
        }
        if picked.contains(where: \.wholeDelete) {
            lines.append(L("\n⚠️ Colima VM/데이터 디스크 삭제가 포함되어 있습니다. 모든 컨테이너 데이터가 사라집니다.", "\n⚠️ This includes deleting the Colima VM/data disk. All container data will be lost."))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 앱 제거

struct UninstallerView: View {
    @ObservedObject var store: UninstallStore
    @State var confirm = false
    @State var confirmRemovesApp = true

    var body: some View {
        HStack(spacing: 0) {
            appList.frame(width: 280)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(L("앱 제거", "Uninstall Apps"))
        .toolbar {
            ToolbarItem {
                Button { store.load() } label: { Label(L("새로고침", "Refresh"), systemImage: "arrow.clockwise") }
                    .disabled(store.working)
            }
        }
        .onAppear { if store.apps.isEmpty { store.load() } }
        .confirmationDialog(confirmTitle, isPresented: $confirm, titleVisibility: .visible) {
            Button(confirmRemovesApp ? L("제거", "Remove") : L("데이터 지우기", "Delete Data"), role: .destructive) {
                store.startUninstall(removeApp: confirmRemovesApp)
            }
            Button(L("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("모두 휴지통으로 이동하므로 휴지통을 비우기 전까지 되돌릴 수 있습니다.", "Everything goes to the Trash, so you can undo it until you empty the Trash.")
                 + (store.selected.flatMap { store.isRunning($0) } != nil ? L("\n앱이 실행 중이라 먼저 종료합니다.", "\nThe app is running, so it will be quit first.") : ""))
        }
    }

    var confirmTitle: String {
        guard let a = store.selected else { return "" }
        let n = store.leftovers.filter(\.selected).count
        return confirmRemovesApp
            ? L("\(a.name)과(와) 데이터 \(n)개를 제거할까요?", "Remove \(a.name) and \(n) data items?")
            : L("\(a.name)의 데이터 \(n)개를 지울까요? (앱은 남겨둡니다)", "Delete \(n) data items of \(a.name)? (The app is kept.)")
    }

    var appList: some View {
        let largest = max(store.apps.map(\.size).max() ?? 1, 1)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("앱 이름으로 검색", "Search apps"), text: $store.search).textFieldStyle(.plain)
                }
                .padding(6).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                Picker("", selection: $store.sortBySize) {
                    Text(L("큰 순서", "By size")).tag(true)
                    Text(L("이름순", "By name")).tag(false)
                }.labelsHidden().fixedSize()
            }
            .padding(10)
            Divider()
            List(store.visibleApps, selection: Binding(get: { store.selectedID }, set: { store.select($0) })) { a in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(a.name).lineLimit(1)
                            Spacer()
                            Text(a.size < 0 ? L("계산 중…", "Calculating…") : fmt(a.size))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        // 가장 큰 앱 대비 크기 막대
                        GeometryReader { geo in
                            Capsule().fill(.quaternary)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.accentColor.opacity(0.6))
                                        .frame(width: a.size > 0 ? max(geo.size.width * CGFloat(Double(a.size) / Double(largest)), 3) : 0)
                                }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.vertical, 3)
                .tag(a.id)
            }
            .disabled(store.working)
            Divider()
            Text(L("\(store.apps.count)개 앱 · macOS 기본 앱은 표시하지 않음", "\(store.apps.count) apps · built-in macOS apps are hidden"))
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
    }

    @ViewBuilder var detail: some View {
        if let a = store.selected {
            appDetail(a)
        } else {
            VStack(spacing: 14) {
                Spacer()
                if !store.message.isEmpty {
                    Banner(icon: store.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                           color: store.messageIsError ? .orange : .green, title: store.message,
                           detail: store.messageIsError ? nil : L("휴지통을 비우면 공간이 확보됩니다.", "Empty the Trash to free up the space."),
                           actionLabel: L("휴지통 열기", "Open Trash"), action: openTrash)
                        .frame(maxWidth: 520)
                }
                if store.needsFullDiskAccess { fdaBanner.frame(maxWidth: 520) }
                if !store.orphaned.isEmpty { orphanCard.frame(maxWidth: 520) }
                Image(systemName: "xmark.app").font(.system(size: 48)).foregroundStyle(.secondary)
                Text(L("왼쪽에서 지울 앱을 고르세요", "Choose an app to remove on the left")).font(.title3.weight(.semibold))
                Text(L("앱을 고르면 그 앱이 남긴 설정·캐시·데이터를 함께 찾아 보여줍니다.", "SpaceSweep will also find the preferences, caches and data it left behind."))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    func appDetail(_ a: AppInfo) -> some View {
        let running = store.isRunning(a) != nil
        let appSize = max(a.size, 0)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 앱 정보
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.name).font(.title.weight(.bold))
                            Text([a.version.isEmpty ? nil : L("버전 \(a.version)", "Version \(a.version)"), a.fromAppStore ? "App Store" : nil]
                                    .compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([a.url]) } label: {
                                Text(a.url.path).font(.caption).lineLimit(1)
                            }.buttonStyle(.link)
                        }
                        Spacer()
                    }

                    if running {
                        Banner(icon: "bolt.circle.fill", color: .blue, title: L("지금 실행 중인 앱입니다", "This app is running"),
                               detail: L("제거하거나 데이터를 지우면 먼저 앱을 종료합니다. 저장하지 않은 작업이 있다면 먼저 저장하세요.", "Removing it or deleting its data quits the app first. Save any unsaved work."))
                    }
                    if !store.message.isEmpty && !store.working {
                        Banner(icon: store.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                               color: store.messageIsError ? .orange : .green, title: store.message,
                               actionLabel: store.messageIsError ? nil : L("휴지통 열기", "Open Trash"), action: openTrash)
                    }
                    if store.needsFullDiskAccess || store.leftovers.contains(where: \.restricted) { fdaBanner }

                    // 용량 요약: 앱 + 데이터 = 합계
                    HStack(spacing: 0) {
                        sizeBox(L("앱", "App"), appSize)
                        Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 30)
                        sizeBox(L("함께 지울 데이터", "Data to delete"), store.leftoverSize)
                        Image(systemName: "equal").foregroundStyle(.secondary).frame(width: 30)
                        sizeBox(L("확보되는 공간", "Space freed"), appSize + store.leftoverSize, highlight: true)
                    }

                    // 남은 데이터 목록
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(L("앱이 남긴 데이터", "Data left by the app")).font(.headline)
                            Spacer()
                            if store.leftovers.count > 1 {
                                let all = store.leftovers.allSatisfy(\.selected)
                                Button(all ? L("모두 해제", "Deselect All") : L("모두 선택", "Select All")) {
                                    for k in store.leftovers.indices { store.leftovers[k].selected = !all }
                                }.buttonStyle(.borderless)
                            }
                        }
                        .padding(14)
                        Divider()
                        if store.loadingLeftovers {
                            HStack { ProgressView().controlSize(.small); Text(L("찾는 중…", "Searching…")).foregroundStyle(.secondary) }
                                .padding(14)
                        } else if store.leftovers.isEmpty {
                            Text(L("남은 데이터를 찾지 못했습니다. 앱만 제거됩니다.", "No leftover data found. Only the app will be removed.")).foregroundStyle(.secondary).padding(14)
                        } else {
                            ForEach($store.leftovers) { $l in
                                leftoverRow($l)
                                if l.id != store.leftovers.last?.id { Divider().padding(.leading, 44) }
                            }
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

                    Text(L("번들 ID와 정확히 일치하는 데이터는 자동으로 선택됩니다. 앱 이름으로만 일치한 항목은 다른 앱의 데이터일 수 있어 직접 확인 후 선택하세요.", "Data that exactly matches the bundle ID is selected automatically. Items that only match the app name may belong to another app, so check them before selecting."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            Divider()
            HStack(spacing: 10) {
                if store.working {
                    ProgressView().controlSize(.small)
                    Text(store.message.isEmpty ? L("처리 중…", "Working…") : store.message).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("데이터만 지우기", "Delete Data Only")) { confirmRemovesApp = false; confirm = true }
                    .help(L("앱은 남기고 설정·캐시만 지웁니다. 앱을 처음 설치한 상태로 초기화할 때 사용하세요.", "Keeps the app and deletes only its preferences and caches. Use it to reset the app to a fresh install."))
                    .disabled(store.working || store.loadingLeftovers || store.leftovers.filter(\.selected).isEmpty)
                    .controlSize(.large)
                Button { confirmRemovesApp = true; confirm = true } label: {
                    Label(L("\(a.name) 제거", "Remove \(a.name)"), systemImage: "trash").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                .disabled(store.working || store.loadingLeftovers)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.bar)
        }
    }

    var orphanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("\(store.orphanedAppName)의 남은 데이터", "Leftover data of \(store.orphanedAppName)")).font(.headline)
                Spacer()
                Button(L("다시 시도", "Try Again")) { store.retryOrphans() }.disabled(store.working)
            }
            .padding(12)
            Divider()
            ForEach(store.orphaned) { l in
                HStack {
                    Text(l.kind).fontWeight(.medium)
                    Text(l.url.path.replacingOccurrences(of: Scanner.home.path, with: "~"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([l.url]) } label: {
                        Image(systemName: "magnifyingglass.circle")
                    }.buttonStyle(.borderless).help(L("Finder에서 위치 보기", "Show in Finder"))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    var fdaBanner: some View {
        Banner(icon: "lock.shield", color: .blue, title: L("macOS가 보호하는 데이터가 있어요", "Some data is protected by macOS"),
               detail: L("다른 앱의 컨테이너는 macOS가 잠가 두어서 SpaceSweep·Finder 모두 지울 수 없습니다. ", "macOS locks other apps' containers, so neither SpaceSweep nor Finder can delete them. ")
                     + L("지우려면 시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 권한에서 SpaceSweep을 켠 뒤, ", "To delete them, turn on SpaceSweep in System Settings > Privacy & Security > Full Disk Access, ")
                     + L("SpaceSweep을 다시 실행하세요.", "then relaunch SpaceSweep."),
               actionLabel: L("설정 열기", "Open Settings"), action: UninstallStore.openFullDiskAccessSettings)
    }

    func sizeBox(_ title: String, _ size: Int64, highlight: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(fmt(size)).font(.title3.weight(.bold)).monospacedDigit()
                .foregroundStyle(highlight ? Color.accentColor : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(highlight ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    func leftoverRow(_ l: Binding<Leftover>) -> some View {
        let v = l.wrappedValue
        return HStack(spacing: 12) {
            Toggle("", isOn: l.selected).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(v.kind).fontWeight(.medium)
                    if v.restricted {
                        Text(L("macOS 보호됨", "Protected by macOS")).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule()).foregroundStyle(.blue)
                    }
                    if v.byName {
                        Text(L("이름만 일치 · 확인 필요", "Name match only · check first")).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
                    }
                }
                Text(v.url.path.replacingOccurrences(of: Scanner.home.path, with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([v.url]) } label: {
                Image(systemName: "magnifyingglass.circle")
            }.buttonStyle(.borderless).help(L("Finder에서 위치 보기", "Show in Finder"))
            Text(v.restricted ? L("확인 불가", "Unknown") : fmt(v.size)).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { l.wrappedValue.selected.toggle() }
    }
}
