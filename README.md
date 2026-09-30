<p align="center">
  <img src="App/Resources/AppIcon.icns" alt="TinyTitanBar App Icon" width="128">
</p>

<h1 align="center">TinyTitan Manager (TinyTitanBar)</h1>

<p align="center">
  <strong>Native macOS Menu Bar App & Service Manager for TinyTitan (Qwen 3.8 Flash Next / 125B 4-Bit)</strong><br>
  专为 TinyTitan 深度优化的原生 macOS 状态栏管理应用与全量维护套件
</p>

<p align="center">
  <img alt="Swift 5.9+" src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(M%20Series)-5E5CE6">
  <img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-2ea44f">
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#简体中文">简体中文</a>
</p>

---

<a name="english"></a>

## English

### Overview

**TinyTitan Manager (`TinyTitanBar`)** is a dedicated native macOS menu bar companion specifically engineered for **TinyTitan** — the high-efficiency MoE inference runtime running **Qwen 3.8 Flash Next (125B Total / 6B Active, 4-Bit quantized)** on Apple Silicon Macs.

Forked and evolved from the upstream runtime, TinyTitan introduces cutting-edge memory management, fine-grained reasoning control, idle memory healing, and multi-prefix KV caching. TinyTitan Manager provides an ultra-lightweight, zero-overhead GUI to manage its entire lifecycle directly from your macOS menu bar.

---

### Key Capabilities

#### 1. Silent Zero-Window Menu Bar App (`TinyTitanBar.app`)
- **Pure Accessory App**: Sits quietly in the macOS status bar without taking up Dock space.
- **Instant Silent Launch**: Launches immediately without first-run setup wizards or modal blockers.
- **Dynamic Status Icons**:
  - 🟢 **Sparkles**: Inference server active and healthy (HTTP 200).
  - 🟡 **Spinning Activity**: Initializing or loading weights into unified memory.
  - 🔴 **Bolt Slash**: Service stopped.
  - ⚠️ **Alert**: Missing `~/TinyTitan` directory.

#### 2. Full Adaptation to `server.sh` Parameters
Provides visual configuration for all 12 specialized parameters:
- **Port (`--port`)**: Loopback port (default: `1231`).
- **Model Path (`--model`)**: Path to `.gturbo` model directory.
- **RAM Budget (`--ram-budget`)**: Controls **entire process RSS memory** (e.g. `4G`, `6G`, `8G` recommended for 16GB Macs, `12G`, `16G`, `24G`). Bottom-up formula reserves the resident weights plus runtime floor — about 3.7GB on a Qwen3.8 4-bit install — fitting the routed-expert cache into the exact target.
- **Expert Cache Slots (`--expert-cache-slots`)**: Optional manual override (8 to 256 slots).
- **Max Context (`--max-context`)**: 4K up to 256K native token window (32K default recommended).
- **KV Precision (`--kv-bits`)**: `8` (8-bit quantization - recommended balance), `4` (4-bit compression - cuts memory in half), `16` (FP16).
- **Reasoning Level (`--reasoning`)**: `off` (Direct response with official Qwen Instruct sampling parameters), `on`, `minimal`, `low`, `medium`, `high`, `xhigh` (Qwen3.8 default), `max`.
- **Lazy Load (`--lazy-load`)**: Instantly binds port with only ~20MB RAM; loads 7GB weights on first request.
- **Idle Memory Healing (`--idle-unload-seconds`)**: Unloads 7GB model after inactivity (e.g., 30 mins) dropping RAM to ~20MB, transparently reloaded on next request.
- **Prompt Cache Mode (`--prompt-cache-mode`)**: `multi-prefix` multi-turn conversation caching, `single-prefix`, or `off`.
- **Prompt Cache RAM (`--prompt-cache-memory-mib`)**: Prefix cache memory buffer (128~2048 MiB).
- **Queue Limit (`--queue-limit`)**: Ceiling before returning HTTP 429.

#### 3. Real-Time Telemetry & Status Logs
- Real-time token generation speed metrics (`tok/s`, tokens, duration).
- Direct access to `server.log`.
- One-click copy for API Base URL (`http://127.0.0.1:1231/v1`) and Model ID.

---

### Building & Packaging

```bash
# Compile and build DMG installer
./build_app.sh --adhoc
```
The output will be placed in:
- `TinyTitanBar.app`
- `TinyTitanBar.dmg`

> **Runtime:** TinyTitan Manager is tested against **TinyTitan v5.13**. The `TinyTitanServer` inference binary is *not* bundled — fetch it from the upstream release (`Pummelchen/TinyTitan` → `tinytitan-5.13-macos-arm64.tar.gz`, verify its `.sha256`) and place it under `~/TinyTitan/bin/`.

---

<a name="简体中文"></a>

## 简体中文

### 项目简介

**TinyTitan Manager (`TinyTitanBar`)** 是专为 **TinyTitan** 本地大模型推理内核（面向 **Qwen 3.8 Flash Next / 125B 4-Bit** 深度优化）量身打造的原生 macOS 状态栏管理应用。

区别于初代原型，TinyTitan 内核在进程物理内存控制、思考推理模式、空闲内存自愈释放与多轮前缀复用等方面具备全面突破。TinyTitan Manager 彻底移除了旧项目的重度初始化向导与修复流程，全面依托 `server.sh` 打造纯粹、轻量、开箱即用的运维面板。

---

### 核心特性

1. **纯净常驻状态栏**：不占用 Dock 栏，启动无任何冗余弹窗，仅在右上角状态栏以精致图标指示服务健康状况。
2. **完整参数热生效**：
   - **整机物理内存预算 (`--ram-budget`)**：严格控制进程 RSS 总量，8G 黄金预算下专家缓存稳定在 4GB，峰值不超 7.8GB，杜绝爆内存与 swap。
   - **思考模式细粒度控制 (`--reasoning`)**：支持菜单栏一键切换 `off`（极速响应/挂载 Instruct 采样）、`on`、`minimal`、`low`、`medium`、`high`、`xhigh`、`max`。
   - **Mac 内存自愈神技 (`--idle-unload-seconds`)**：设定空闲超时（如 30 分钟），闲置后自动将 7GB 权重卸载归还系统（内存降回 20MB），再次对话无感秒级热唤醒。
   - **KV 压缩与超长上下文**：支持 8-bit / 4-bit KV 缓存压缩以及 4K ~ 256K 极限上下文窗口。
   - **多轮前缀复用 (`--prompt-cache-mode`)**：智能复用多轮对话历史 KV 状态，首字极速响应。
3. **极速构建与发布**：内置自动化编译与 DMG 打包脚本，支持开源 Ad-hoc 签名与纯个人开发者签名。

---

### 构建与运行

```bash
# 一键编译并生成 DMG 安装包
./build_app.sh --adhoc
```
构建产物位于当前目录：
- `TinyTitanBar.app`：原生可执行应用包
- `TinyTitanBar.dmg`：带 Applications 快捷软链接的发布镜像

> **运行时常驻内核：** TinyTitan Manager 以 **TinyTitan v5.13** 为验证基准。`TinyTitanServer` 推理二进制并不随管理器打包——请从上游发布页（`Pummelchen/TinyTitan` → `tinytitan-5.13-macos-arm64.tar.gz`，并校验其 `.sha256`）下载，放至 `~/TinyTitan/bin/` 即可。
