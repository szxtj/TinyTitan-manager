import SwiftUI
import AppKit

public final class SettingsWindowController: NSWindowController {
    public static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 780),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = LocalizationManager.shared.tr("TinyTitan Settings", "TinyTitan 服务偏好设置")
        window.center()
        window.setFrameAutosaveName("TinyTitanSettingsWindow")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showAndActivate() {
        self.window?.title = LocalizationManager.shared.tr("TinyTitan Settings", "TinyTitan 服务偏好设置")
        self.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeKeyAndOrderFront(nil)
    }
}

public struct SettingsView: View {
    @ObservedObject var manager = ServiceManager.shared
    @ObservedObject var l10n = LocalizationManager.shared

    @State private var draftConfig: ServerConfiguration = .default
    @State private var portString: String = "1231"
    @State private var showSaveSuccess: Bool = false
    @State private var saveNoticeMessage: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部导航标题
            headerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - 表单配置区域
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    generalAndLanguageSection
                    Divider()
                    networkAndModelSection
                    Divider()
                    ramAndHardwareSection
                    Divider()
                    contextAndKVSection
                    Divider()
                    reasoningAndLifecycleSection
                    Divider()
                    advancedSection
                }
                .padding(24)
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // MARK: - 底部操作栏
            footerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 720, height: 780)
        .onAppear {
            loadCurrentConfig()
        }
    }

    private func loadCurrentConfig() {
        self.draftConfig = manager.config
        self.portString = "\(manager.config.port)"
    }

    // MARK: - 顶部标题与提示
    private var headerBar: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.tr("TinyTitan Service Configuration & Parameters", "TinyTitan 服务运行与性能参数设置"))
                    .font(.system(size: 15, weight: .bold))
                Text(l10n.tr("Settings persist to config.env. Restart the service to apply changes immediately.", "配置自动持久化并同步 config.env，可随时热重启推理服务以生效。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if showSaveSuccess {
                Text(saveNoticeMessage)
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - 0. 通用与语言设置
    private var generalAndLanguageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("General & Language", "通用与语言"), systemImage: "globe")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Interface Language:", "界面语言:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $l10n.language) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 320)
                        Text(l10n.tr("Follows system preferences or switches immediately across all windows.", "自动跟随 macOS 系统语言或手动指定，切换后所有窗口即刻生效。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 1. 网络端口与模型路径
    private var networkAndModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("Network & Model Path", "网络端口与模型路径"), systemImage: "network")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Port:", "监听端口:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("1231", text: $portString)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 140)
                            .onChange(of: portString) { newValue in
                                if let p = Int(newValue), (1024...65535).contains(p) {
                                    draftConfig.port = p
                                }
                            }
                        Text(l10n.tr("Default: 1231 (OpenAI-compatible API HTTP endpoint)", "默认: 1231 (OpenAI 兼容 API 本地 HTTP 端口)"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Model Directory:", "模型目录路径:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        let models = manager.availableModels()
                        if models.count > 1 {
                            Picker("", selection: $draftConfig.model) {
                                ForEach(models, id: \.self) { path in
                                    Text(URL(fileURLWithPath: path).lastPathComponent).tag(path)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 440)
                        } else {
                            TextField(draftConfig.model, text: $draftConfig.model)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 440)
                        }

                        Text(l10n.tr("Supports repacked .gturbo directories with manifest.json and packed_experts.", "已解包或打包的模型目录路径（包含 manifest.json、packed_experts 等）。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 2. 内存与硬件资源控制 (RAM & Hardware)
    private var ramAndHardwareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("RAM & Hardware Resource Budget", "内存与硬件资源控制"), systemImage: "memorychip")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("RAM Budget:", "整机物理内存预算:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.ramBudget) {
                            Text(l10n.tr("4G (Minimum viable budget)", "4G (最低允许底线)")).tag("4G")
                            Text(l10n.tr("6G (Tight memory / 16GB Mac)", "6G (较紧凑预算)")).tag("6G")
                            Text(l10n.tr("8G (Recommended for 16GB Mac · 32 Slots)", "8G (16GB Mac 黄金推荐 · 32槽位)")).tag("8G")
                            Text(l10n.tr("10G (Balanced for 24GB Mac · 48 Slots)", "10G (24GB Mac 均衡 · 48槽位)")).tag("10G")
                            Text(l10n.tr("12G (Recommended for 24GB+ Mac · 64 Slots)", "12G (24GB+ Mac 推荐 · 64槽位)")).tag("12G")
                            Text(l10n.tr("16G (High capacity · 96+ Slots)", "16G (大内存高速 · 96+槽位)")).tag("16G")
                            Text(l10n.tr("24G (Huge RAM Mac)", "24G (大容量机型)")).tag("24G")
                            Text(l10n.tr("32G (Maximum cache residency)", "32G (超大物理内存)")).tag("32G")
                        }
                        .labelsHidden()
                        .frame(width: 440)
                        Text(l10n.tr("--ram-budget: Target RSS for entire process. Cache = target - (weights + floor, about 3.7G on Qwen3.8 4-bit). 8G yields ~7.6G peak RSS, zero swap.", "官方最新规范：控制整个进程的总物理常驻内存，自动扣减底座（约 3.7G，Qwen3.8 4-bit）后分配缓存。8G 实测峰值 7.6GB，彻底杜绝爆内存与 swap。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Expert Cache Slots:", "专家缓存槽位:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.expertCacheSlots) {
                            Text(l10n.tr("Auto (Derived from RAM Budget - Recommended)", "Auto (由内存预算自动向下匹配 · 推荐)")).tag("")
                            Text("8 Slots (~1 GB cache)").tag("8")
                            Text("16 Slots (~2 GB cache)").tag("16")
                            Text("24 Slots (~3 GB cache)").tag("24")
                            Text("32 Slots (~4 GB cache - Default for 8G)").tag("32")
                            Text("40 Slots").tag("40")
                            Text("48 Slots").tag("48")
                            Text("64 Slots (~8 GB cache - Default for 12G)").tag("64")
                            Text("96 Slots").tag("96")
                            Text("112 Slots").tag("112")
                            Text("128 Slots").tag("128")
                            Text("160 Slots").tag("160")
                            Text("192 Slots").tag("192")
                            Text("256 Slots").tag("256")
                        }
                        .labelsHidden()
                        .frame(width: 440)
                        Text(l10n.tr("Leave Auto to let TinyTitan compute the safest fit for RAM budget.", "手动覆盖每层专家槽位。通常保持 Auto 即可，系统会根据 RAM Budget 自动安全阶梯适配。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 3. 上下文长度与 KV 缓存精度
    private var contextAndKVSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("Context Length & KV Cache Storage", "上下文长度与 KV 缓存精度"), systemImage: "doc.text")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Max Context:", "最大上下文:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.maxContext) {
                            Text(l10n.tr("4,096 (4K) - Ultra low memory", "4,096 (4K) - 极低显存")).tag(4096)
                            Text(l10n.tr("8,192 (8K) - Lightweight & Fast", "8,192 (8K) - 极速日常模式")).tag(8192)
                            Text(l10n.tr("16,384 (16K)", "16,384 (16K)")).tag(16384)
                            Text(l10n.tr("32,768 (32K) - Recommended (Sweet Spot)", "32,768 (32K) - 黄金日常推荐")).tag(32768)
                            Text(l10n.tr("65,536 (64K) - Long Documents", "65,536 (64K) - 长篇文档")).tag(65536)
                            Text(l10n.tr("131,072 (128K) - Full Document Analysis", "131,072 (128K) - 超长文本深度分析")).tag(131072)
                            Text(l10n.tr("262,144 (256K) - Native Maximum Limit", "262,144 (256K) - 原生硬件极限")).tag(262144)
                        }
                        .labelsHidden()
                        .frame(width: 440)
                        Text(l10n.tr("Native range: 4K...256K. 32K balances multi-turn dialogues with fast TTFT and low KV memory.", "原生支持 4K ~ 256K。32K 兼顾日常多轮历史与极低首字延迟 (TTFT)。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("KV Cache Precision:", "KV 缓存压缩精度:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.kvBits) {
                            Text(l10n.tr("8-bit (Quantized - Optimal balance, recommended)", "8-bit (量化 · 兼顾生成质量与显存，默认推荐)")).tag(8)
                            Text(l10n.tr("4-bit (Deep compression - Cuts KV RAM in half)", "4-bit (深度压缩 · 超长文本显存开销再砍半)")).tag(4)
                            Text(l10n.tr("16-bit (Full FP16 fidelity - Doubles KV RAM)", "16-bit (未压缩 FP16 原生精度 · 显存占用最大)")).tag(16)
                        }
                        .labelsHidden()
                        .frame(width: 440)
                        Text(l10n.tr("8-bit delivers near-lossless generation quality with significantly reduced memory pressure.", "8-bit 量化能在维持极佳文本品质的同时大幅压低长上下文时的显存占用。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 4. 思考模式、内存自愈与生命周期 (Reasoning & Lifecycle)
    private var reasoningAndLifecycleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("Reasoning, Memory Healing & Performance", "思考模式、内存自愈与生命周期"), systemImage: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Reasoning Level:", "思考推理深度:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.reasoning) {
                            Text(l10n.tr("off (Direct answer, official Instruct sampling - Fastest)", "off (极速非思考模式 · 挂载 Instruct 采样，推荐)")).tag("off")
                            Text(l10n.tr("on (Full reasoning chain)", "on (开启完整思考链)")).tag("on")
                            Text("minimal").tag("minimal")
                            Text("low").tag("low")
                            Text("medium").tag("medium")
                            Text("high").tag("high")
                            Text(l10n.tr("xhigh (Qwen 3.8 template default)", "xhigh (Qwen 3.8 官方默认深度)")).tag("xhigh")
                            Text(l10n.tr("max (Maximum effort)", "max (极限思考深度)")).tag("max")
                        }
                        .labelsHidden()
                        .frame(width: 440)
                        Text(l10n.tr("When 'off', TinyTitan applies official Qwen Instruct sampling parameters for highest quality.", "设置为 off 时，TinyTitan 会自动挂载官方发布的高质量 Instruct 采样参数，首字极速输出。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Lazy Load:", "懒加载启动:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(l10n.tr("Defer loading model weights until first incoming request", "推迟大模型加载，直到首个对话请求到达"), isOn: $draftConfig.lazyLoad)
                            .toggleStyle(.checkbox)
                        Text(l10n.tr("Binds HTTP port instantly (RAM ~20MB). Loads 7GB weights only when needed.", "推荐开启：启动脚本秒级就绪，常驻仅 20MB；等首条聊天请求到达时再挂载 7GB 权重。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Idle Unload (Memory Healing):", "空闲释放 (内存自愈):"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.idleUnloadSeconds) {
                            Text(l10n.tr("0 (Disabled - Stay resident indefinitely in memory)", "0 (关闭 · 保持常驻内存随时待命)")).tag(0)
                            Text(l10n.tr("300 seconds (5 minutes)", "300 秒 (5 分钟)")).tag(300)
                            Text(l10n.tr("600 seconds (10 minutes)", "600 秒 (10 分钟)")).tag(600)
                            Text(l10n.tr("1800 seconds (30 minutes · Mac Healing sweet spot)", "1800 秒 (30 分钟 · Mac 内存自愈黄金推荐)")).tag(1800)
                            Text(l10n.tr("3600 seconds (1 hour)", "3600 秒 (1 小时)")).tag(3600)
                        }
                        .labelsHidden()
                        .frame(width: 440)
                        Text(l10n.tr("Unloads 7GB+ weights after idle timeout, returning RAM to macOS (~20MB). Next request reloads automatically.", "闲置超时后自动将 7GB+ 模型卸载，内存彻底还给 macOS！下一次发送消息时透明重载唤醒。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Prompt Cache Mode:", "提示词前缀复用:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.promptCacheMode) {
                            Text(l10n.tr("multi-prefix (Caches multiple branches - Recommended)", "multi-prefix (多轮多分支复用 · 默认推荐)")).tag("multi-prefix")
                            Text(l10n.tr("single-prefix (Single branch)", "single-prefix (单分支复用)")).tag("single-prefix")
                            Text(l10n.tr("off (Disabled)", "off (关闭前缀缓存)")).tag("off")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 440)
                        Text(l10n.tr("Caches recurring conversation history; second turn onward responds with near-instant TTFT.", "自动缓存多轮对话的历史前缀，后续对话无需从头计算，首字极速响应。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Prompt Cache RAM Pool:", "前缀缓存内存池:").trimmingCharacters(in: .whitespaces))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.promptCacheMemMib) {
                            Text("128 MiB").tag(128)
                            Text("256 MiB (Default / 默认)").tag(256)
                            Text("512 MiB").tag(512)
                            Text("1024 MiB (1 GiB)").tag(1024)
                            Text("2048 MiB (2 GiB)").tag(2048)
                        }
                        .labelsHidden()
                        .frame(width: 320)
                    }
                }

                GridRow {
                    Text(l10n.tr("Queue Limit:", "请求并发排队上限:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.queueLimit) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("4 (Default / 默认)").tag(4)
                            Text("8").tag(8)
                            Text("16").tag(16)
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Text(l10n.tr("Maximum queued requests before returning HTTP 429.", "排队请求上限，超过此数目直接返回 429 忙碌。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 5. 高级参数 (Advanced / TinyTitan v5.13)
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("Advanced Parameters", "高级参数 (v5.13 新增)"), systemImage: "slider.vertical.3")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Max Concurrent Sequences:", "并行生成序列数:")).font(.subheadline).gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.maxConcurrentSequences) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("4").tag(4)
                            Text("8").tag(8)
                            Text("16").tag(16)
                        }.labelsHidden().frame(width: 220)
                        Text(l10n.tr("Generations served at once (power of two). Above 1 each holds its own KV cache — more memory, slower.", "同时服务的生成数（2 的幂）。大于 1 时每条序列独占 KV 缓存：内存更高、单条更慢。")).font(.caption2).foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Prefill Chunk:", "预填充分块:")).font(.subheadline).gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.prefillChunk) {
                            Text("32").tag(32)
                            Text("64").tag(64)
                            Text("128").tag(128)
                            Text("256").tag(256)
                            Text("512").tag(512)
                            Text("1024").tag(1024)
                            Text("2048").tag(2048)
                            Text("4096 (Default)").tag(4096)
                        }.labelsHidden().frame(width: 220)
                        Text(l10n.tr("Tokens per prefill step; tune TTFT vs throughput.", "每次预填充的 token 数；在首字延迟与吞吐之间权衡。")).font(.caption2).foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Prompt Cache Entries:", "前缀缓存条目数:")).font(.subheadline).gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.promptCacheEntries) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("4 (Default)").tag(4)
                            Text("8").tag(8)
                            Text("16").tag(16)
                            Text("32").tag(32)
                            Text("64").tag(64)
                        }.labelsHidden().frame(width: 220)
                        Text(l10n.tr("Distinct conversation prefixes kept in the in-memory cache.", "内存前缀缓存保留的不同对话前缀数量。")).font(.caption2).foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Prompt Cache Disk Dir:", "前缀缓存落盘目录:")).font(.subheadline).gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(l10n.tr("optional: /path/to/cache", "可选：/路径/到/缓存"), text: $draftConfig.promptCacheDiskDir).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 440)
                        Text(l10n.tr("Pairs with Idle Unload: prefix cache survives an unload instead of a cold prefill.", "与「空闲释放」配合：卸载权重后前缀缓存仍可无感恢复，免去冷启动重算。")).font(.caption2).foregroundColor(.secondary)
                    }
                }

                if !draftConfig.promptCacheDiskDir.trimmingCharacters(in: .whitespaces).isEmpty {
                    GridRow {
                        Text(l10n.tr("Disk Cache Budget:", "落盘缓存预算:")).font(.subheadline).gridColumnAlignment(.trailing)
                        Picker("", selection: $draftConfig.promptCacheDiskMib) {
                            Text("1024 MiB").tag(1024)
                            Text("2048 MiB").tag(2048)
                            Text("4096 MiB").tag(4096)
                            Text("8192 MiB (Default)").tag(8192)
                        }.labelsHidden().frame(width: 320)
                    }
                }
            }
        }
    }

    // MARK: - 底部操作栏
    private var footerBar: some View {
        HStack(spacing: 12) {
            Button(l10n.tr("Restore Defaults", "恢复默认配置")) {
                restoreDefaults()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.subheadline)

            Spacer()

            if manager.state.isRunning {
                Button(l10n.tr("Save & Restart Service", "保存并重启服务")) {
                    saveAndRestart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Button(l10n.tr("Save", "保存")) {
                saveOnly()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - 操作逻辑
    private func restoreDefaults() {
        self.draftConfig = .default
        self.portString = "\(ServerConfiguration.default.port)"
        saveOnly(message: l10n.tr("Restored TinyTitan default settings!", "已重置为 TinyTitan 推荐默认参数并保存！"))
    }

    private func saveOnly(message: String? = nil) {
        if let p = Int(portString), (1024...65535).contains(p) {
            draftConfig.port = p
        }
        manager.applyConfiguration(draftConfig, restartIfRunning: false)
        notifySaved(message: message ?? l10n.tr("✅ Settings saved successfully!", "✅ 配置已成功保存！"))
    }

    private func saveAndRestart() {
        if let p = Int(portString), (1024...65535).contains(p) {
            draftConfig.port = p
        }
        manager.applyConfiguration(draftConfig, restartIfRunning: true)
        notifySaved(message: l10n.tr("🚀 Saved! Service is restarting with new parameters...", "🚀 配置已保存，服务正在以新参数重启..."))
    }

    private func notifySaved(message: String) {
        self.saveNoticeMessage = message
        withAnimation {
            self.showSaveSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                self.showSaveSuccess = false
            }
        }
    }
}
