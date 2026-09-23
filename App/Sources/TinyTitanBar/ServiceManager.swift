import Foundation
import SwiftUI
import Combine

public enum ServiceState: Equatable {
    case stopped
    case starting
    case running(pid: Int32, port: Int)
    case missingRepo
    case error(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .stopped:
            return "已停止"
        case .starting:
            return "启动中..."
        case .running(_, let port):
            return "运行中 (端口: \(port))"
        case .missingRepo:
            return "未找到 TinyTitan 目录"
        case .error(let msg):
            return "异常: \(msg)"
        }
    }
}

public struct GenerationMetrics: Equatable {
    public let speed: Double          // tok/s (token generation speed)
    public let duration: Double       // total or tg duration in seconds
    public let completionTokens: Int  // number of generated tokens
    public let promptTokens: Int      // number of prompt tokens
    public let cachedTokens: Int      // prompt cached tokens
}

@MainActor
public final class ServiceManager: ObservableObject {
    public static let shared = ServiceManager()

    @Published public private(set) var state: ServiceState = .stopped
    @Published public private(set) var lastLogLines: [String] = []
    @Published public private(set) var lastGenerationMetrics: GenerationMetrics?
    @Published public var config: ServerConfiguration

    public var port: Int { config.port }
    public var baseURL: String { "http://127.0.0.1:\(port)/v1" }

    public var modelID: String {
        // 优先提取模型目录名或 manifest 中的名称
        let modelURL = URL(fileURLWithPath: config.model)
        return modelURL.lastPathComponent
    }

    public let homeDir: URL
    public let tinyTitanDir: URL
    public let serverScript: URL
    public let logFile: URL
    public let pidFile: URL
    public let modelsDir: URL

    private var monitorTimer: Timer?

    private init() {
        let loadedConfig = ServerConfiguration.load()
        loadedConfig.exportToEnvFile()
        self.config = loadedConfig

        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
        let defaultTinyTitan = homeDir.appendingPathComponent("TinyTitan")
        let ssdTinyTitan = URL(fileURLWithPath: "/Volumes/JustinSSD/TinyTitan-work")

        if FileManager.default.fileExists(atPath: defaultTinyTitan.path) {
            self.tinyTitanDir = defaultTinyTitan
        } else if FileManager.default.fileExists(atPath: ssdTinyTitan.path) {
            self.tinyTitanDir = ssdTinyTitan
        } else {
            self.tinyTitanDir = defaultTinyTitan
        }

        self.serverScript = tinyTitanDir.appendingPathComponent("server.sh")
        self.logFile = tinyTitanDir.appendingPathComponent("server.log")
        self.pidFile = tinyTitanDir.appendingPathComponent("server.pid")
        self.modelsDir = tinyTitanDir.appendingPathComponent("models")

        startMonitoring()
        startLogTail()
    }

    // MARK: - 状态监视轮询

    private func startMonitoring() {
        refreshState()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshState()
            }
        }
    }

    public func refreshState() {
        guard FileManager.default.fileExists(atPath: tinyTitanDir.path) else {
            self.state = .missingRepo
            return
        }

        guard let pid = readPID(), isProcessAlive(pid: pid) else {
            if case .starting = state {
                return
            }
            self.state = .stopped
            return
        }

        Task {
            let healthy = await checkHealth()
            if healthy {
                self.state = .running(pid: pid, port: self.port)
            } else {
                self.state = .starting
            }
        }
    }

    private func readPID() -> Int32? {
        if FileManager.default.fileExists(atPath: pidFile.path),
           let content = try? String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(content) {
            return pid
        }

        // 端口回退检测
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let out = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).first,
           let pid = Int32(out.trimmingCharacters(in: .whitespaces)) {
            return pid
        }

        return nil
    }

    public func isAnyProcessRunning() -> Bool {
        if let pid = readPID(), isProcessAlive(pid: pid) {
            return true
        }
        return false
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        return kill(pid, 0) == 0
    }

    public func checkHealth() async -> Bool {
        // 1. 优先检测 /health 端点
        if let healthURL = URL(string: "http://127.0.0.1:\(port)/health") {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 1.0
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        }

        // 2. 回退检测 /v1/models
        if let modelsURL = URL(string: "http://127.0.0.1:\(port)/v1/models") {
            var request = URLRequest(url: modelsURL)
            request.timeoutInterval = 1.0
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        }

        return false
    }

    // MARK: - 服务生命周期控制

    public func startService() {
        guard FileManager.default.fileExists(atPath: tinyTitanDir.path) else {
            self.state = .missingRepo
            return
        }
        self.state = .starting
        runScriptCommand("start")
    }

    public func stopService() {
        runScriptCommand("stop")
        self.state = .stopped
    }

    public func restartService() {
        self.state = .starting
        runScriptCommand("restart")
    }

    public func applyConfiguration(_ newConfig: ServerConfiguration, restartIfRunning: Bool = false) {
        self.config = newConfig
        newConfig.save()
        if restartIfRunning && self.state.isRunning {
            restartService()
        }
    }

    @discardableResult
    private func runScriptCommand(_ action: String) -> (output: String, exitCode: Int32) {
        guard FileManager.default.fileExists(atPath: serverScript.path) else {
            return ("未找到 server.sh", 1)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [serverScript.path, action]
        process.currentDirectoryURL = tinyTitanDir
        
        var env = ProcessInfo.processInfo.environment
        env["ROOT_DIR"] = tinyTitanDir.path
        for (k, v) in config.environmentDictionary {
            env[k] = v
        }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, process.terminationStatus)
        } catch {
            return (error.localizedDescription, 1)
        }
    }

    // MARK: - 本地可用模型扫描

    public func availableModels() -> [String] {
        var result: [String] = []
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
            for item in items {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let manifestPath = item.appendingPathComponent("manifest.json").path
                    let weightsPath = item.appendingPathComponent("model_weights.bin").path
                    if fm.fileExists(atPath: manifestPath) || fm.fileExists(atPath: weightsPath) {
                        result.append(item.path)
                    }
                }
            }
        }
        if result.isEmpty {
            result.append(config.model)
        }
        return result
    }

    // MARK: - 日志 Tail 与指标解析

    private func startLogTail() {
        reloadLogs()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadLogs()
            }
        }
    }

    public func reloadLogs() {
        guard FileManager.default.fileExists(atPath: logFile.path) else { return }
        do {
            let content = try String(contentsOf: logFile, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            let tail = lines.suffix(200).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            self.lastLogLines = Array(tail)

            // 倒序寻找最后一次成功生成的请求耗时与速度指标
            for line in lines.reversed() {
                if let metrics = parseGenerationMetrics(from: line) {
                    self.lastGenerationMetrics = metrics
                    break
                }
            }
        } catch {
            // ignore
        }
    }

    public func clearLogs() {
        try? "".write(to: logFile, atomically: true, encoding: .utf8)
        self.lastLogLines = []
        self.lastGenerationMetrics = nil
    }

    /// 从服务端日志行中解析最新一次生成的速度指标
    /// 示例 1: [2026-09-23T06:45:48Z] request 1 completed in 1.450s prompt=30 cached=0 completion=50 finish=stop
    /// 示例 2: [2026-09-22T19:08:10Z] request ... completed in 180.491s prompt=261 cached=0 completion=1113 tg_tok_s=6.499 finish=stop
    private func parseGenerationMetrics(from line: String) -> GenerationMetrics? {
        guard line.contains("completed in") && line.contains("completion=") else {
            return nil
        }

        func extractDouble(key: String) -> Double? {
            guard let range = line.range(of: key) else { return nil }
            let sub = line[range.upperBound...]
            let token = sub.prefix(while: { $0.isNumber || $0 == "." })
            return Double(token)
        }

        func extractInt(key: String) -> Int? {
            guard let range = line.range(of: key) else { return nil }
            let sub = line[range.upperBound...]
            let token = sub.prefix(while: { $0.isNumber })
            return Int(token)
        }

        guard let completionTokens = extractInt(key: "completion=") else {
            return nil
        }

        let promptTokens = extractInt(key: "prompt=") ?? 0
        let cachedTokens = extractInt(key: "cached=") ?? 0

        // 提取耗时: completed in 1.450s
        var duration: Double = 0
        if let inRange = line.range(of: "completed in ") {
            let sub = line[inRange.upperBound...]
            let token = sub.prefix(while: { $0.isNumber || $0 == "." })
            duration = Double(token) ?? 0
        }

        // 速度: 优先读取 tg_tok_s，否则用 completionTokens / duration
        var speed: Double = 0
        if let explicitSpeed = extractDouble(key: "tg_tok_s=") {
            speed = explicitSpeed
        } else if duration > 0 && completionTokens > 0 {
            speed = Double(completionTokens) / duration
        }

        return GenerationMetrics(
            speed: speed,
            duration: duration,
            completionTokens: completionTokens,
            promptTokens: promptTokens,
            cachedTokens: cachedTokens
        )
    }
}
