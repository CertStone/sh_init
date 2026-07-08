# EasyTier 一键部署脚本（公开版）

一个用于 Linux（systemd）的 EasyTier 一键部署脚本：下载官方预编译二进制、安装、
配置开机自启服务。**启动参数完全由用户输入**，可用于任意组网场景（配置服务器、
直连 peer、配置文件等）。

> 需 root、`curl`、`unzip`，以及 systemd。

---

## 快速开始

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/CertStone/sh_init/main/easytier/deploy.sh -o deploy.sh
chmod +x deploy.sh

# 安装（交互式输入启动参数）
sudo ./deploy.sh

# 或直接指定启动参数与安装路径
sudo ./deploy.sh install /opt/easytier \
  --exec-args "-w udp://your-config-server:65432/your-token --machine-id my-host-001"

# 升级（只换二进制，保持启动参数不变，不提示输入）
sudo ./deploy.sh update

# 卸载
sudo ./deploy.sh uninstall
```

运行 `sudo ./deploy.sh help` 查看内置帮助。

---

## 用法

```
sudo ./deploy.sh [command] [安装路径] [options]
```

### Commands

| 命令 | 说明 |
|---|---|
| `install` | 下载并安装 EasyTier，配置开机自启（默认，可省略；需要启动参数） |
| `update` | 升级到最新版（只换二进制，**保持启动参数不变，不提示输入**） |
| `uninstall` | 卸载 EasyTier 及其服务、清理文件 |
| `help` | 显示帮助 |

### Options

| 选项 | 说明 |
|---|---|
| `--exec-args "<args>"` | 非交互指定启动参数（`easytier-core` 之后的**全部**命令行） |
| `--no-gh-proxy` | 强制直连 GitHub，不做镜像探测 |
| `--gh-proxy <URL>` | 强制使用指定镜像站（拼在 GitHub URL 之前） |

### 环境变量

| 变量 | 等价于 |
|---|---|
| `EXEC_ARGS` | `--exec-args` |
| `INSTALL_PATH` | 位置参数 `[安装路径]`（默认 `/opt/easytier`） |

### 优先级

- 启动参数：`--exec-args` > `EXEC_ARGS` 环境变量 > 交互式提示
- 安装路径：位置参数 > `INSTALL_PATH` 环境变量 > `/opt/easytier`
- 下载源：`--no-gh-proxy` > `--gh-proxy URL` > 自动探测（见下）

---

## 启动参数（`--exec-args` / `EXEC_ARGS`）

填入 `easytier-core` 命令名**之后**的全部参数，空格分隔。常见模式举例：

**1. Web 配置客户端**（从远程配置服务器拉取网络配置，token 为 URL 末段）：
```bash
--exec-args "-w udp://your-config-server:65432/your-token --machine-id my-host-001"
```

**2. 直连 peer**（点对点组网，两端 network-name/secret 须一致）：
```bash
--exec-args "-p tcp://1.2.3.4:11010 --network-name mynet --network-secret s3cret"
```

**3. 使用本地配置文件**：
```bash
--exec-args "-c /opt/easytier/config/default.conf"
```

> 完整参数列表请运行 `easytier-core --help`，或参考
> [EasyTier 官方文档](https://easytier.cn/)。

校验规则（避免破坏 systemd unit 文件）：**拒绝空值和换行符**，其余字符不做限制
（easytier 参数含 URL、逗号、冒号、等号、路径等，白名单会过度限制）。

---

## 下载源与镜像分流

GitHub 在部分网络环境下不可达，脚本内置自动分流：

1. 若指定 `--no-gh-proxy`：强制直连 GitHub。
2. 若指定 `--gh-proxy URL`：强制使用该镜像。
3. **自动模式（默认）**：
   - 先用 `curl --connect-timeout 5` 探测 `github.com`，可达即直连下载。
   - 不可达时，依次探测镜像站：`ghfast.top`、`gh-proxy.com`、`mirror.ghproxy.com`，
     命中即用并打印当前使用的源。
   - 获取版本号同样有镜像兜底：GitHub API 不通时，依次走镜像站访问 API。
   - 全部不可达则报错退出。

如需使用自定义镜像，例如 `https://your-proxy.com/`：
```bash
sudo ./deploy.sh --gh-proxy https://your-proxy.com/
```

---

## 安装后布局

```
/opt/easytier/
├── easytier-core          # 主程序
├── easytier-cli           # 命令行管理工具
└── easytier.args          # 持久化的启动参数（便于升级/排查）

/etc/systemd/system/
└── easytier.service       # systemd 单元（ExecStart = easytier-core <你的参数>）

/usr/sbin/
├── easytier-core -> /opt/easytier/easytier-core
└── easytier-cli  -> /opt/easytier/easytier-cli
```

systemd 单元示例（`/etc/systemd/system/easytier.service`）：

```ini
[Unit]
Description=EasyTier Service
Wants=network.target
After=network.target network.service

[Service]
Type=simple
WorkingDirectory=/opt/easytier
ExecStart=/opt/easytier/easytier-core <你的启动参数>
Restart=always
RestartSec=1s

[Install]
WantedBy=multi-user.target
```

### 常用服务管理命令

```bash
systemctl status easytier        # 查看状态
systemctl restart easytier       # 重启
systemctl stop easytier          # 停止
journalctl -u easytier -f        # 实时日志
```

---

## 原理说明

脚本提供 `install`（安装/重装）与 `update`（升级）两个命令，区别在于**是否重新获取启动参数**：

| | `install` | `update` |
|---|---|---|
| 启动参数来源 | 用户输入（CLI > 环境变量 > 交互提示） | 复用 `${INSTALL_PATH}/easytier.args`（**不提示输入**） |
| systemd 单元 | 重写（参数可能变了） | 不动（参数未变） |
| 版本对比 | 否（重装即重下） | 是，已是最新则跳过 |
| 适用场景 | 首装、改参数、修复 | 日常升级 |

### install 流程

```
┌─ 前置检查（root / curl / unzip / systemd / 平台）
├─ 解析启动参数（CLI > 环境变量 > 交互提示）
├─ 获取最新版本号（GitHub API → 镜像站兜底）
├─ 解析下载源（强制直连 / 强制镜像 / 自动探测 GitHub 可达性）
├─ 下载到暂存目录（mktemp，不触碰安装目录）
│    └─ 解压、校验 easytier-core 存在
├─ 原子交换：mv 暂存内容 → 安装目录
├─ 原子写入 easytier.args 与 systemd 单元（先写 .tmp 再 mv）
├─ 停用官方脚本遗留的 easytier@* 模板实例（避免双开抢端口）
├─ daemon-reload → enable → restart
└─ 轮询 is-active 验证服务（失败则打印 journalctl 日志并退出非零）
```

### update 流程

```
┌─ 前置检查（同 install）
├─ 复用持久化参数（读 easytier.args；无则报错引导用 install）
├─ 读取本地版本（easytier-core --version）+ 获取最新版本
├─ 版本对比：相同则直接退出（无需升级）
├─ 解析下载源 → 下载到暂存目录 → 校验
├─ 原子替换二进制（mv；systemd 单元不动）
├─ 刷新 /usr/sbin 软链 → daemon-reload → restart
└─ 轮询 is-active 验证服务
```

### 关键设计

- **暂存目录隔离**：下载和解压在 `mktemp -d` 创建的私有目录中完成，确认二进制
  完整后才一次性 `mv` 进安装目录。下载阶段被 Ctrl+C 中断**不会污染**既有安装。
- **原子写文件**：systemd 单元和 `easytier.args` 都先写 `*.tmp.$$` 再 `mv` 替换，
  避免中断留下截断文件导致开机加载失败。
- **EXIT/INT/TERM trap 兜底清理**：无论正常退出、Ctrl+C、还是失败，都会清理暂存目录。
- **镜像自动探测**：解决 GitHub 在国内等网络不可达的问题，仅在直连失败时才走镜像。
- **服务状态验证**：`Type=simple` 下 `restart` 立即返回不代表进程稳定，脚本会轮询
  `is-active`，失败时打印最近日志，**不谎报成功**。
- **幂等**：`install` 重复运行会重新下载、原子覆盖二进制、重写单元、重启服务；
  `update` 重复运行时若版本未变则直接跳过。
- **参数持久化**：`install` 把启动参数写入 `${INSTALL_PATH}/easytier.args`，
  供 `update` 复用——升级时无需重传参数。
- **危险路径守卫**：拒绝 `/`、`/usr`、`/etc`、`/var` 等系统目录作为安装路径。
- **与官方 install.sh 兼容**：停用其模板化 `easytier@*` 实例，避免两个 easytier
  进程同时运行抢端口。

### 平台支持

复用官方 `install.sh` 的架构映射（含 ARM hard-float 探测）：

| `uname -m` | 架构标识 |
|---|---|
| `x86_64` / `amd64` | `x86_64` |
| `aarch64` / `arm64` / `armv8*` | `aarch64` |
| `armv7*` | `armv7`（+ `hf` 若支持硬浮点） |
| `arm*` | `arm`（+ `hf` 若支持硬浮点） |
| `mips` / `mipsel` | `mips` / `mipsel` |

下载资源命名 `easytier-linux-${ARCH}-${VERSION}.zip`，来自
`https://github.com/EasyTier/EasyTier/releases/latest`。

---

## 常见问题

**Q: 提示"无法读取输入（非交互式终端或输入已结束）"**

非交互环境（SSH 管道、CI、`<<EOF`）下 `read` 遇到 EOF 会退出。请改用：
```bash
sudo ./deploy.sh --exec-args "..."     # 或
EXEC_ARGS="..." sudo -E ./deploy.sh
```

**Q: 提示"所有下载源均不可达"**

网络完全不通。尝试指定镜像：`sudo ./deploy.sh --gh-proxy https://ghfast.top/`。

**Q: 安装完成但服务未正常运行（状态非 active）**

通常是启动参数有误或配置服务器连接失败。查看日志：
```bash
journalctl -u easytier -n 50 --no-pager
```
修正参数后无需重装，直接改 `/etc/systemd/system/easytier.service` 的 `ExecStart`，
或重跑 `sudo ./deploy.sh --exec-args "新参数"` 覆盖。

**Q: 如何修改启动参数？**

直接重跑安装并指定新参数即可（会原子覆盖单元文件并重启服务）：
```bash
sudo ./deploy.sh --exec-args "新的启动参数"
```

**Q: 与官方 `script/install.sh` 冲突吗？**

官方脚本装的是模板化 `easytier@<config>.service`（基于配置文件），本脚本装的是
单实例 `easytier.service`（基于用户输入的启动参数）。本脚本安装时会停用官方脚本
遗留的 `easytier@*` 实例，避免双开抢端口。如需切回官方模式，先 `sudo ./deploy.sh uninstall`。

**Q: 如何升级 EasyTier？**

- **保持原启动参数升级**（推荐）：`sudo ./deploy.sh update`
  脚本读取上次持久化的 `easytier.args`，下载最新版原子替换二进制并重启服务，**全程不提示输入参数**。已是最新版会自动跳过。
- **同时改启动参数**：用 `install` 重装并指定新参数：
  ```bash
  sudo ./deploy.sh --exec-args "新的启动参数"
  ```
  这会重写 systemd 单元并重启。

---


