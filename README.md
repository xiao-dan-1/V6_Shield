# V6_Shield — 极简代理护盾

> **极简 · 优雅 · 零侵入**
> 专为 Linux 终端而生的 Xray 极速分发引擎。

本项目旨在抛弃臃肿的 GUI 客户端与繁琐的依赖，以奥卡姆剃刀原则重构代理管线。

---

## 核心特性

- **🚀 闪电探针**：基于原生 `/dev/tcp` 的毫秒级 Socket 探测，不依赖外部工具即可在菜单中扫视节点存活与延迟。
- **🛡️ 纯净沙箱**：配置存储 (`profiles/`) 与执行环境 (`run/`) 物理隔离。运行期间沙箱内仅存单体配置文件，杜绝误读风险。
- **🔌 深度渗透**：一键接管系统代理。支持 GNOME 桌面环境设置与 Shell 环境（`.bashrc` / `.zshrc`）的幂等持久化注入。
- **⚡ 烘焙路由**：路由规则直接内联至配置流。不再需要外部 `routing.json`，实现 100% 的单体自容错。
- **⚛️ 零依赖**：全量代码基于 Bash 4.0+，无需 Python/NodeJS 等运行库，保持宿主环境绝对纯净。

---

## 架构阵列

```text
V6_Shield/
├── shield.sh       # 启动枢纽（主入口：Fail-Fast 预检 → 沙箱激活 → 宿主托管）
├── nodes.sh        # 交互中枢（节点管理、TCP 闪电测速、动态菜单、热销毁）
├── converter.sh    # 配置引擎（链接解析、多协议分发、内联路由烘焙）
├── proxy.sh        # 代理管线（桌面级/终端级代理同步注入与平滑移除）
├── profiles/       # 节点军火库（存放生成的 JSON 图纸）
├── run/            # 绝对沙箱（运行时的隔离跑道）
└── xray            # Xray Core 二进制
```

---

## 快速上手

### 1. 自动化环境准备
```bash
chmod +x install_xray.sh
./install_xray.sh
```

### 2. 导入节点链接 (支持 VLESS / Trojan)
```bash
# 导入并自动解析备注名
./converter.sh "vless://..."

# 自定义存档名称
./converter.sh "trojan://..." -o my_server.json
```

### 3. 可视化节点管理 (首选方案)
```bash
# 运行交互式控制台，查看实时延迟并切换节点
./nodes.sh
```

### 4. 激活护盾
```bash
# 启动最近一次在 nodes.sh 中选中的节点
./shield.sh

# 或直接指定 profiles/ 中的文件启动
./shield.sh my_server.json
```

### 5. 一键接管系统代理
```bash
./proxy.sh on   # 同时开启终端环境变量 (持久化) 与桌面网络设置
./proxy.sh off  # 平滑移除所有注入标记，还系统一份纯净
```

---

## 支持协议

| 传输管线 | 安全层 | 状态 |
| :--- | :--- | :--- |
| **WebSocket** | TLS | ✅ |
| **TCP** | Reality | ✅ |
| **gRPC** | TLS / Reality | ✅ |
| **TCP** | TLS / HTTP Header | ✅ |
| **Trojan** | TLS | ✅ |

---

## 设计哲学

- **奥卡姆剃刀**：如果不需要，那就删掉它。
- **显式状态机**：通过 `run/` 沙箱和符号链接，让运行状态在文件系统中清晰可见。
- **职责单一**：脚本之间通过文件指针通信，互不耦合。
- **防御性路由**：内置局域网绕过与节点 IP 直连，保护隧道不自噬。

---

## License
[AGPL-3.0](LICENSE)
