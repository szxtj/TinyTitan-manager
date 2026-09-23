import SwiftUI
import AppKit

public final class StatusAndLogWindowController: NSWindowController {
    public static let shared = StatusAndLogWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = LocalizationManager.shared.tr(
            "TinyTitan Service Status & Live Logs",
            "TinyTitan 服务状态与实时日志"
        )
        window.center()
        window.setFrameAutosaveName("TinyTitanStatusAndLogWindow")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StatusAndLogView())

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showAndActivate() {
        self.window?.title = LocalizationManager.shared.tr(
            "TinyTitan Service Status & Live Logs",
            "TinyTitan 服务状态与实时日志"
        )
        self.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeKeyAndOrderFront(nil)
    }
}

public struct StatusAndLogView: View {
    @ObservedObject var manager = ServiceManager.shared
    @ObservedObject var l10n = LocalizationManager.shared

    @State private var autoScroll: Bool = true
    @State private var copyBanner: String? = nil

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部状态栏卡片
            topCardView
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - 快捷操作与工具栏
            actionToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // MARK: - 日志控制台
            logConsoleView
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            manager.reloadLogs()
        }
    }

    // MARK: - 顶部概览
    private var topCardView: some View {
        HStack(alignment: .center, spacing: 16) {
            // 状态指示图标
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Circle()
                    .fill(statusColor)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("TinyTitan Server")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(statusBadgeText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .cornerRadius(6)

                    Spacer()

                    if let banner = copyBanner {
                        Text(banner)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .transition(.opacity)
                    }
                }

                HStack(spacing: 12) {
                    Label(l10n.tr("Port: \(manager.port)", "端口: \(manager.port)"), systemImage: "network")
                    Label(l10n.tr("RAM Budget: \(manager.config.ramBudget)", "内存预算: \(manager.config.ramBudget)"), systemImage: "memorychip")
                    Label(l10n.tr("Context: \(manager.config.maxContext / 1024)K", "上下文: \(manager.config.maxContext / 1024)K"), systemImage: "doc.text")
                    Label(l10n.tr("KV: \(manager.config.kvBits)-bit", "KV精度: \(manager.config.kvBits)-bit"), systemImage: "archivebox")
                    Label(l10n.tr("Reasoning: \(manager.config.reasoning)", "思考: \(manager.config.reasoning)"), systemImage: "brain")
                    Label(l10n.tr("Cache: \(manager.config.promptCacheMode)", "前缀缓存: \(manager.config.promptCacheMode)"), systemImage: "clock.arrow.circlepath")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if let metrics = manager.lastGenerationMetrics {
                    HStack(spacing: 8) {
                        Label(
                            l10n.tr(
                                "Last Speed: \(String(format: "%.2f", metrics.speed)) tok/s (\(metrics.completionTokens) tokens / \(String(format: "%.2f", metrics.duration))s)",
                                "上次生成速度: \(String(format: "%.2f", metrics.speed)) tok/s (\(metrics.completionTokens) 字 / \(String(format: "%.2f", metrics.duration))s)"
                            ),
                            systemImage: "bolt.fill"
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - 工具栏
    private var actionToolbar: some View {
        HStack(spacing: 12) {
            Toggle(l10n.tr("Auto-scroll", "自动滚屏"), isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.subheadline)

            Spacer()

            Button(l10n.tr("Copy Logs", "复制日志")) {
                let full = manager.lastLogLines.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(full, forType: .string)
                showBanner(l10n.tr("Copied to clipboard", "已复制到剪贴板"))
            }
            .buttonStyle(.plain)
            .font(.subheadline)

            Button(l10n.tr("Clear Logs", "清空日志")) {
                manager.clearLogs()
            }
            .buttonStyle(.plain)
            .font(.subheadline)

            Button(l10n.tr("Open Log in Finder", "在访达中定位日志")) {
                NSWorkspace.shared.activateFileViewerSelecting([manager.logFile])
            }
            .buttonStyle(.plain)
            .font(.subheadline)

            Divider().frame(height: 16)

            if manager.state.isRunning {
                Button(l10n.tr("Restart Service", "重启服务")) {
                    manager.restartService()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                Button(l10n.tr("Start Service", "启动服务")) {
                    manager.startService()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - 日志区域
    private var logConsoleView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if manager.lastLogLines.isEmpty {
                        Text(l10n.tr("Log is empty. Start the service or send inference requests to view activity.", "当前日志为空。启动服务或发送聊天请求后此处将实时显示日志。"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(16)
                    } else {
                        ForEach(Array(manager.lastLogLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(colorForLine(line))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: manager.lastLogLines.count) { _ in
                if autoScroll, !manager.lastLogLines.isEmpty {
                    withAnimation {
                        proxy.scrollTo(manager.lastLogLines.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - 辅助样式
    private var statusColor: Color {
        switch manager.state {
        case .running:
            return .green
        case .starting:
            return .orange
        case .stopped:
            return .secondary
        case .missingRepo, .error:
            return .red
        }
    }

    private var statusBadgeText: String {
        switch manager.state {
        case .running(let pid, _):
            return l10n.tr("RUNNING (PID: \(pid))", "运行中 (PID: \(pid))")
        case .starting:
            return l10n.tr("INITIALIZING", "正在初始化")
        case .stopped:
            return l10n.tr("STOPPED", "已停止")
        case .missingRepo:
            return l10n.tr("MISSING DIRECTORY", "目录缺失")
        case .error(let msg):
            return l10n.tr("ERROR: \(msg)", "异常: \(msg)")
        }
    }

    private func colorForLine(_ line: String) -> Color {
        if line.contains("failed") || line.contains("error") || line.contains("❌") {
            return .red
        }
        if line.contains("watchdog") || line.contains("⚠️") {
            return .yellow
        }
        if line.contains("completed in") || line.contains("ready at") || line.contains("✅") {
            return .green
        }
        if line.contains("accepted") || line.contains("generating") {
            return .cyan
        }
        return .primary
    }

    private func showBanner(_ message: String) {
        withAnimation {
            copyBanner = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copyBanner = nil
            }
        }
    }
}
