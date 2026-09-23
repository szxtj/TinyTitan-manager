import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var cancellables = Set<AnyCancellable>()
    private let manager = ServiceManager.shared
    private let l10n = LocalizationManager.shared

    public override init() {
        super.init()
        setupStatusItem()
        bindServiceState()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIconAndMenu()
    }

    private func bindServiceState() {
        manager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIconAndMenu()
            }
            .store(in: &cancellables)

        l10n.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIconAndMenu()
            }
            .store(in: &cancellables)
    }

    private func updateIconAndMenu() {
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.title = ""
        switch manager.state {
        case .running:
            if let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Running")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = l10n.tr(
                "TinyTitan: Running (Port: \(manager.port))",
                "TinyTitan: 运行中 (端口: \(manager.port))"
            )
        case .starting:
            if let image = NSImage(systemSymbolName: "bolt.badge.clock.fill", accessibilityDescription: "Starting")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = l10n.tr(
                "TinyTitan: Starting up / Initializing...",
                "TinyTitan: 正在启动/初始化..."
            )
        case .stopped:
            if let image = NSImage(systemSymbolName: "bolt.slash", accessibilityDescription: "Stopped")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = l10n.tr(
                "TinyTitan: Service stopped",
                "TinyTitan: 服务已停止"
            )
        case .missingRepo:
            if let image = NSImage(systemSymbolName: "bolt.trianglebadge.exclamationmark", accessibilityDescription: "Missing Directory")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = l10n.tr(
                "TinyTitan: Directory not found (~/TinyTitan)",
                "TinyTitan: 未找到目录 (~/TinyTitan)"
            )
        case .error(let msg):
            if let image = NSImage(systemSymbolName: "bolt.badge.xmark", accessibilityDescription: "Error")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = l10n.tr(
                "TinyTitan Error: \(msg)",
                "TinyTitan 异常: \(msg)"
            )
        }
    }

    // MARK: - NSMenuDelegate 动态渲染菜单

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. 标题头
        let titleItem = NSMenuItem(title: "TinyTitan Manager", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "TinyTitan Manager",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(titleItem)

        // 状态说明
        let statusText: String
        switch manager.state {
        case .running(let pid, let port):
            statusText = "🟢 " + l10n.tr("Status: Running (PID: \(pid), Port: \(port))", "状态: 运行中 (PID: \(pid), 端口: \(port))")
        case .starting:
            statusText = "🟡 " + l10n.tr("Status: Initializing...", "状态: 正在初始化...")
        case .stopped:
            statusText = "🔴 " + l10n.tr("Status: Stopped", "状态: 已停止")
        case .missingRepo:
            statusText = "⚠️ " + l10n.tr("Status: Directory not found (~/TinyTitan)", "状态: 未找到项目目录 (~/TinyTitan)")
        case .error(let msg):
            statusText = "❌ " + l10n.tr("Error: \(msg)", "异常: \(msg)")
        }
        let statusMenuItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // 上一次生成速度指标
        if manager.state.isRunning {
            if let metrics = manager.lastGenerationMetrics {
                let speed = String(format: "%.2f", metrics.speed)
                let dur = String(format: "%.2f", metrics.duration)
                let metricsText = "⚡ " + l10n.tr(
                    "Last Speed: \(speed) tok/s (\(metrics.completionTokens) tok / \(dur)s)",
                    "上次生成速度: \(speed) tok/s (\(metrics.completionTokens) 字 / \(dur)s)"
                )
                let metricsItem = NSMenuItem(title: metricsText, action: nil, keyEquivalent: "")
                metricsItem.isEnabled = false
                menu.addItem(metricsItem)
            }

            let copyBaseURLItem = NSMenuItem(
                title: "🔗 " + l10n.tr("Copy Base URL (\(manager.baseURL))", "复制 Base URL (\(manager.baseURL))"),
                action: #selector(copyBaseURLAction),
                keyEquivalent: ""
            )
            copyBaseURLItem.target = self
            menu.addItem(copyBaseURLItem)

            let copyModelItem = NSMenuItem(
                title: "🏷️ " + l10n.tr("Copy Model ID (\(manager.modelID))", "复制 Model ID (\(manager.modelID))"),
                action: #selector(copyModelIDAction),
                keyEquivalent: ""
            )
            copyModelItem.target = self
            menu.addItem(copyModelItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. 查看服务状态与实时日志
        let showLogItem = NSMenuItem(
            title: "📊 " + l10n.tr("Service Status & Live Logs...", "查看服务状态与实时日志..."),
            action: #selector(showStatusAndLogWindow),
            keyEquivalent: "l"
        )
        showLogItem.target = self
        menu.addItem(showLogItem)

        // 偏好设置
        let settingsItem = NSMenuItem(
            title: "⚙️ " + l10n.tr("Settings & Runtime Parameters...", "服务偏好设置与运行参数..."),
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 思考模式快捷切换项 (8 档细粒度)
        let reasoningMenuItem = NSMenuItem(
            title: "🧠 " + l10n.tr("Reasoning Mode", "思考模式 (Reasoning)"),
            action: nil,
            keyEquivalent: ""
        )
        let reasoningSubMenu = NSMenu()
        let reasoningModes: [(key: String, en: String, zh: String)] = [
            ("off", "off (Direct / Instruct sampling - Fastest)", "off (极速模式，挂载 Instruct 参数)"),
            ("on", "on (Full Reasoning)", "on (开启完整思考链)"),
            ("minimal", "minimal (Minimal effort)", "minimal (微量思考)"),
            ("low", "low (Low effort)", "low (低度思考)"),
            ("medium", "medium (Medium effort)", "medium (中度思考)"),
            ("high", "high (High effort)", "high (高度思考)"),
            ("xhigh", "xhigh (Extra High - Qwen3.8 default)", "xhigh (超高思考 · Qwen3.8默认)"),
            ("max", "max (Maximum reasoning)", "max (极限思考深度)")
        ]
        for mode in reasoningModes {
            let item = NSMenuItem(
                title: l10n.tr(mode.en, mode.zh),
                action: #selector(changeReasoningMode(_:)),
                keyEquivalent: ""
            )
            item.representedObject = mode.key
            item.state = (manager.config.reasoning == mode.key) ? .on : .off
            item.target = self
            reasoningSubMenu.addItem(item)
        }
        reasoningMenuItem.submenu = reasoningSubMenu
        menu.addItem(reasoningMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 3. 服务基础控制项
        if manager.state.isRunning {
            let restartItem = NSMenuItem(
                title: l10n.tr("Restart Service", "重启服务"),
                action: #selector(restartService),
                keyEquivalent: "r"
            )
            restartItem.target = self
            menu.addItem(restartItem)

            let stopItem = NSMenuItem(
                title: l10n.tr("Stop Service", "停止服务"),
                action: #selector(stopService),
                keyEquivalent: "s"
            )
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(
                title: l10n.tr("Start Service", "启动服务"),
                action: #selector(startService),
                keyEquivalent: "s"
            )
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 4. 维护与辅助项
        let openRepoItem = NSMenuItem(
            title: l10n.tr("Open TinyTitan Folder (~/TinyTitan)", "打开 TinyTitan 目录 (~/TinyTitan)"),
            action: #selector(openRepoFolder),
            keyEquivalent: ""
        )
        openRepoItem.target = self
        menu.addItem(openRepoItem)

        let openLogItem = NSMenuItem(
            title: l10n.tr("Open Server Log File", "打开运行日志文件 (server.log)"),
            action: #selector(openLogFile),
            keyEquivalent: ""
        )
        openLogItem.target = self
        menu.addItem(openLogItem)

        menu.addItem(NSMenuItem.separator())

        // 5. 退出
        let quitItem = NSMenuItem(
            title: l10n.tr("Quit TinyTitan Manager (Stop Service)", "退出 TinyTitan Manager (并停止服务)"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func showStatusAndLogWindow() {
        StatusAndLogWindowController.shared.showAndActivate()
    }

    @objc private func showSettingsWindow() {
        SettingsWindowController.shared.showAndActivate()
    }

    @objc private func changeReasoningMode(_ sender: NSMenuItem) {
        guard let newMode = sender.representedObject as? String,
              newMode != manager.config.reasoning else { return }
        var updated = manager.config
        updated.reasoning = newMode
        manager.applyConfiguration(updated, restartIfRunning: manager.state.isRunning)
    }

    @objc private func startService() {
        manager.startService()
    }

    @objc private func stopService() {
        manager.stopService()
    }

    @objc private func restartService() {
        manager.restartService()
    }

    @objc private func openRepoFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: manager.tinyTitanDir.path)
    }

    @objc private func openLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([manager.logFile])
    }

    @objc private func copyBaseURLAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(manager.baseURL, forType: .string)
    }

    @objc private func copyModelIDAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(manager.modelID, forType: .string)
    }

    @objc private func quitApp() {
        manager.stopService()
        NSApp.terminate(nil)
    }
}
