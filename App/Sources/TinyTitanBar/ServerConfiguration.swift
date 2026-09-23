import Foundation

public struct ServerConfiguration: Codable, Equatable {
    // 1. 监听端口 (默认: 1231)
    public var port: Int
    
    // 2. 模型目录路径 (默认: ~/TinyTitan/models/qwen3.8-flash-next_125B_A6B_4Bit)
    public var model: String

    // 3. 进程物理内存预算 (4G, 6G, 8G, 10G, 12G, 16G, 24G, 32G - 默认: 8G)
    public var ramBudget: String

    // 4. 专家缓存槽位数 (留空为由 ramBudget 自动计算，或手动指定: 8, 16, 24, 32, 40, 48, 64, 96, 112, 128...)
    public var expertCacheSlots: String

    // 5. 最大上下文长度 (4096, 8192, 16384, 32768, 65536, 131072, 262144 - 默认: 32768)
    public var maxContext: Int

    // 6. KV 缓存存储精度 (4, 8, 16 - 默认: 8)
    public var kvBits: Int

    // 7. 思考推理深度策略 (off, on, minimal, low, medium, high, xhigh, max - 默认: off)
    public var reasoning: String

    // 8. 懒加载模式 (true: 端口秒级就绪，首个请求再挂载权重；false: 立即挂载 - 默认: true)
    public var lazyLoad: Bool

    // 9. 空闲超时自动释放内存秒数 (0: 关闭常驻; 1800: 30分钟无请求释放回20MB内存 - 默认: 0)
    public var idleUnloadSeconds: Int

    // 10. 多轮提示词前缀复用模式 (multi-prefix, single-prefix, off - 默认: multi-prefix)
    public var promptCacheMode: String

    // 11. 前缀缓存内存池大小 (MiB, 默认: 256)
    public var promptCacheMemMib: Int

    // 12. 请求并发排队上限 (默认: 4)
    public var queueLimit: Int

    public static let defaultModelPath = "/Volumes/JustinSSD/TinyTitan-work/models/qwen3.8-flash-next_125B_A6B_4Bit"

    public init(
        port: Int = 1231,
        model: String = ServerConfiguration.defaultModelPath,
        ramBudget: String = "8G",
        expertCacheSlots: String = "",
        maxContext: Int = 32768,
        kvBits: Int = 8,
        reasoning: String = "off",
        lazyLoad: Bool = true,
        idleUnloadSeconds: Int = 0,
        promptCacheMode: String = "multi-prefix",
        promptCacheMemMib: Int = 256,
        queueLimit: Int = 4
    ) {
        self.port = port
        self.model = model
        self.ramBudget = ramBudget
        self.expertCacheSlots = expertCacheSlots
        self.maxContext = maxContext
        self.kvBits = kvBits
        self.reasoning = reasoning
        self.lazyLoad = lazyLoad
        self.idleUnloadSeconds = idleUnloadSeconds
        self.promptCacheMode = promptCacheMode
        self.promptCacheMemMib = promptCacheMemMib
        self.queueLimit = queueLimit
    }

    enum CodingKeys: String, CodingKey {
        case port, model, ramBudget, expertCacheSlots, maxContext, kvBits
        case reasoning, lazyLoad, idleUnloadSeconds, promptCacheMode
        case promptCacheMemMib, queueLimit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 1231
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ServerConfiguration.defaultModelPath
        ramBudget = try container.decodeIfPresent(String.self, forKey: .ramBudget) ?? "8G"
        expertCacheSlots = try container.decodeIfPresent(String.self, forKey: .expertCacheSlots) ?? ""
        maxContext = try container.decodeIfPresent(Int.self, forKey: .maxContext) ?? 32768
        kvBits = try container.decodeIfPresent(Int.self, forKey: .kvBits) ?? 8
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? "off"
        lazyLoad = try container.decodeIfPresent(Bool.self, forKey: .lazyLoad) ?? true
        idleUnloadSeconds = try container.decodeIfPresent(Int.self, forKey: .idleUnloadSeconds) ?? 0
        promptCacheMode = try container.decodeIfPresent(String.self, forKey: .promptCacheMode) ?? "multi-prefix"
        promptCacheMemMib = try container.decodeIfPresent(Int.self, forKey: .promptCacheMemMib) ?? 256
        queueLimit = try container.decodeIfPresent(Int.self, forKey: .queueLimit) ?? 4
    }

    /// 官方与脚本推荐配置基准
    public static let `default` = ServerConfiguration(
        port: 1231,
        model: ServerConfiguration.defaultModelPath,
        ramBudget: "8G",
        expertCacheSlots: "",
        maxContext: 32768,
        kvBits: 8,
        reasoning: "off",
        lazyLoad: true,
        idleUnloadSeconds: 0,
        promptCacheMode: "multi-prefix",
        promptCacheMemMib: 256,
        queueLimit: 4
    )

    private static let userDefaultsKey = "TinyTitan_ServerConfiguration"

    public static var configDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TinyTitan")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static var envConfigFile: URL {
        configDirectory.appendingPathComponent("config.env")
    }

    public static var repoEnvConfigFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("TinyTitan")
            .appendingPathComponent("config.env")
    }

    /// 读取持久化配置
    public static func load() -> ServerConfiguration {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(ServerConfiguration.self, from: data) {
            return decoded
        }
        return .default
    }

    /// 保存配置并同步导出环境变量文件（供命令行 server.sh 共享）
    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: ServerConfiguration.userDefaultsKey)
        }
        exportToEnvFile()
    }

    /// 导出为 Shell 可识别的 config.env
    public func exportToEnvFile() {
        let envContent = """
        # TinyTitan 运行配置 (由 TinyTitan Manager 自动生成)
        export PORT=\(port)
        export MODEL="\(model)"
        export RAM_BUDGET="\(ramBudget)"
        export EXPERT_CACHE_SLOTS="\(expertCacheSlots)"
        export MAX_CONTEXT=\(maxContext)
        export KV_BITS=\(kvBits)
        export REASONING="\(reasoning)"
        export LAZY_LOAD=\(lazyLoad ? "true" : "false")
        export IDLE_UNLOAD_SECONDS=\(idleUnloadSeconds)
        export PROMPT_CACHE_MODE="\(promptCacheMode)"
        export PROMPT_CACHE_MEM_MIB=\(promptCacheMemMib)
        export QUEUE_LIMIT=\(queueLimit)
        """
        try? envContent.write(to: ServerConfiguration.envConfigFile, atomically: true, encoding: .utf8)
        
        // 同时同步一份到 ~/TinyTitan/config.env
        let repoTarget = ServerConfiguration.repoEnvConfigFile
        if FileManager.default.fileExists(atPath: repoTarget.deletingLastPathComponent().path) {
            try? envContent.write(to: repoTarget, atomically: true, encoding: .utf8)
        }
    }

    /// 生成注入到 Process.environment 的字典
    public var environmentDictionary: [String: String] {
        var dict: [String: String] = [
            "PORT": "\(port)",
            "MODEL": model,
            "RAM_BUDGET": ramBudget,
            "MAX_CONTEXT": "\(maxContext)",
            "KV_BITS": "\(kvBits)",
            "REASONING": reasoning,
            "LAZY_LOAD": lazyLoad ? "true" : "false",
            "IDLE_UNLOAD_SECONDS": "\(idleUnloadSeconds)",
            "PROMPT_CACHE_MODE": promptCacheMode,
            "PROMPT_CACHE_MEM_MIB": "\(promptCacheMemMib)",
            "QUEUE_LIMIT": "\(queueLimit)"
        ]
        if !expertCacheSlots.trimmingCharacters(in: .whitespaces).isEmpty {
            dict["EXPERT_CACHE_SLOTS"] = expertCacheSlots
        }
        return dict
    }
}
