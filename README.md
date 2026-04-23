# V6_Shield

> 跨平台、零侵入、极简的 Xray 代理引擎

**只做两件事**：将 VLESS 链接转为配置，然后前台运行 Xray。

## 架构

```
V6_Shield/
├── shield.sh       # 启动脚本（主入口）
├── converter.sh    # VLESS 订阅转换器
├── profiles/       # 节点配置存放目录
│   └── *.json      # 自动生成的 Xray 配置
└── xray            # Xray Core 二进制（需自行放置）
```

三大组件完全解耦：
- **converter.sh** — 订阅转换，纯 Bash，零依赖
- **shield.sh** — 环境校验 + 前台托管
- **profiles/** — 配置物理隔离

## 快速开始

### 1. 放置 Xray Core

使用自动化脚本一键安装：

```bash
chmod +x install_xray.sh
./install_xray.sh
```

### 2. 导入节点

```bash
# 转换 VLESS 链接为配置文件
./converter.sh "vless://uuid@server:443?type=ws&security=tls&path=/ws#MyNode"

# 自定义输出文件名
./converter.sh "vless://..." -o my_server.json
```

### 3. 启动代理

```bash
# 自动加载最新配置
./shield.sh

# 手动指定配置文件
./shield.sh my_server.json
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
