import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let manager = ServiceManager.shared

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 初始化状态栏图标控制器 (直接呈现状态栏图标，无任何初始弹窗)
        statusBarController = StatusBarController()

        // 2. 状态刷新
        manager.refreshState()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // 退出时连同推理服务一起停止
        manager.stopService()
    }
}
