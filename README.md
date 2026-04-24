# V6_Shield

> 跨平台、零侵入、极简的 Xray 代理引擎

**只做两件事**：将 VLESS 链接转为配置，然后前台运行 Xray。

## 架构

```
V6_Shield/
├── shield.sh       # 启动脚本（主入口）
├── nodes.sh        # 节点管理交互控制台
├── converter.sh    # VLESS 订阅转换器
├── install_xray.sh # Xray 自动安装器
├── profiles/       # 节点配置仓库
├── run/            # 运行沙箱（仅存放当前 config.json）
└── xray            # Xray Core 二进制
```

三大核心哲学彻底解耦：
- **配置文件物理隔离**：所有的订阅转换沉淀在 `profiles/` 这座兵工厂内。
- **运行沙箱绝对纯净**：真正交给 `shield.sh` 与 `xray` 挂载的只有 `run/config.json` 这一条航线。
- **职责单一**：`converter.sh` 只管转换存档，`shield.sh` 负责激活与托管，`nodes.sh` 负责交互管理。

## 快速开始

### 1. 放置 Xray Core

使用自动化脚本一键安装：

```bash
chmod +x install_xray.sh
./install_xray.sh
```

### 2. 导入节点

```bash
# 转换 VLESS 链接，生成配置存入 profiles/
./converter.sh "vless://uuid@server:443?type=ws&security=tls&path=/ws#MyNode"

# 自定义文件名
./converter.sh "vless://..." -o my_server.json
```

### 3. 极速起航与切换

```bash
# 激活指定节点并启动（自动清洗 run/ 沙箱）
./shield.sh my_server.json

# 直接启动 run/ 中已有的配置
./shield.sh
```

### 4. 使用代理

```bash
# SOCKS5 代理
export ALL_PROXY=socks5://127.0.0.1:37080

# HTTP 代理
export HTTP_PROXY=http://127.0.0.1:37081
export HTTPS_PROXY=http://127.0.0.1:37081

# 测试连通性
curl -x socks5://127.0.0.1:37080 https://ipinfo.io
```

### 5. 停止代理

直接关闭终端窗口即可。进程随窗口生灭，无需额外清理。

## 设计哲学

- **奥卡姆剃刀** — 只保留最纯粹的启动与托管骨架
- **前台运行** — 不做后台守护，不污染系统代理
- **物理隔离** — 配置与运行彻底解耦
- **高位端口** — SOCKS5 `37080`，HTTP `37081`，避免冲突
- **零清理** — 配置固化在 profiles/，无需死后文件清理

## 支持的协议

| 传输 | 安全层 | 状态 |
|------|--------|------|
| WebSocket | TLS | ✅ |
| TCP | Reality | ✅ |
| gRPC | TLS | ✅ |
| TCP | TLS | ✅ |
| TCP | None | ✅ |

## 系统要求

- Bash 4.0+
- Linux / macOS / WSL

## License

[AGPL-3.0](LICENSE)
