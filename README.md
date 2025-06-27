# 综合优化版 Shell 环境配置脚本

本项目提供一个功能完善、体验流畅的自动化 Shell/Linux 环境配置脚本 ([`sh_init.sh`](https://raw.githubusercontent.com/GitHubsAdministrator/sh_init/main/sh_init.sh))，特别关注中国大陆用户的网络环境，旨在简化和加速 Linux (尤其是 Ubuntu/Debian) 环境的初始化配置过程。

**请注意：此脚本主要为作者个人使用和学习目的创建，不保证进行持续的公开维护和更新，请您了解并自行评估风险。**

## 主要功能

*   **APT 镜像源更换**: 自动检测系统版本，并允许用户选择国内主流的 APT 镜像源 (如清华、阿里、中科大等)，加速软件包下载。支持传统格式和 DEB822 格式的 `sources.list`。
*   **开发语言镜像配置**:
    *   **Python**: 配置 pip 使用阿里云镜像。
    *   **Go**: 配置 `GOPROXY` 为 `goproxy.cn` 和 `GOSUMDB` 为 `sum.golang.google.cn`。
    *   **Node.js**: 配置 npm 使用淘宝 npmmirror 镜像。
*   **Zsh 和 Oh-My-Zsh 安装与配置**:
    *   自动安装 Zsh、Git、Curl、Wget (如果缺失)。
    *   提供从 GitHub 官方或 Gitee 镜像安装 Oh-My-Zsh 的选项。
    *   提示用户如何将 Zsh 设置为默认 Shell。
*   **Zsh 主题选择与配置**:
    *   内置多种流行主题供用户选择 (如 haoomz, powerlevel10k, ys, robbyrussell, agnoster)。
    *   自动下载和配置所选主题，对于 powerlevel10k 会从用户选择的 Git 镜像源克隆。
*   **Zsh 插件安装与配置**:
    *   预设核心插件列表 (git, z, extract, zsh-autosuggestions, zsh-syntax-highlighting)。
    *   可选启用一组增强型插件 (colored-man-pages, colorize, cp, sudo, command-not-found, history, history-substring-search, python)。
    *   自动从用户选择的 Git 镜像源克隆外部插件。
*   **代理辅助函数**: 可选在 `.zshrc` 中添加 `proxy` 和 `unproxy` 函数，方便快速启停终端代理 (默认 SOCKS5 127.0.0.1:1089, HTTP/HTTPS 127.0.0.1:1080)。
*   **Docker CE 安装与镜像加速**:
    *   可选使用国内 Docker CE APT 镜像源或官方源安装 Docker CE。
    *   可选配置 Docker Hub 镜像加速器，支持默认或自定义地址，并能通过 `jq` 合并到现有 `daemon.json` 配置。
*   **用户交互**: 通过清晰的提示和 `Y/N` 选择引导用户完成配置。
*   **日志系统**: 不同级别的彩色日志输出 (信息、警告、错误)。
*   **依赖检查与安装**: 自动检查并提示安装必要的依赖包 (如 `lsb-release`, `jq` 等)。
*   **Sudo 权限管理**: 脚本开始时检查并请求 sudo 权限。
*   **幂等性设计**: 脚本设计考虑了幂等性，多次运行脚本通常不会导致错误或重复配置，而是会跳过已完成的步骤或安全地更新现有配置。

## 先决条件

*   一个基于 Debian/Ubuntu 的 Linux 发行版。脚本仅在这两个系统上进行过测试，其他系统可能部分功能不适用。
*   `bash` shell。
*   当前账户具有 `sudo` 权限。
*   网络连接，用于下载软件包和配置文件。
*   `curl` 或 `wget` 用于一键执行或下载脚本。

## 使用方法

### 一键执行 (推荐)

您可以使用以下任一命令直接下载并执行脚本：

*   **使用 curl (GitHub):**
    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/GitHubsAdministrator/sh_init/main/sh_init.sh)
    ```
*   **使用 wget (GitHub):**
    ```bash
    bash <(wget -qO- https://raw.githubusercontent.com/GitHubsAdministrator/sh_init/main/sh_init.sh)
    ```
*   **使用 curl (Gitee 镜像 - 中国大陆用户推荐):**
    ```bash
    bash <(curl -fsSL https://gitee.com/wo99/sh_init/raw/main/sh_init.sh)
    ```
*   **使用 wget (Gitee 镜像 - 中国大陆用户推荐):**
    ```bash
    bash <(wget -qO- https://gitee.com/wo99/sh_init/raw/main/sh_init.sh)
    ```
    

### 分步执行

1.  **下载脚本**:
    *   通过 Git 克隆:
        ```bash
        git clone https://github.com/GitHubsAdministrator/sh_init.git
        cd sh_init
        ```
    *   或者直接下载脚本文件 (假设脚本位于 `main` 分支):
        ```bash
        curl -o sh_init.sh https://raw.githubusercontent.com/GitHubsAdministrator/sh_init/main/sh_init.sh
        # 或者使用 wget:
        # wget -O sh_init.sh https://raw.githubusercontent.com/GitHubsAdministrator/sh_init/main/sh_init.sh
        chmod +x sh_init.sh
        ```
        *(如果您的默认分支不是 `main`，请将上述 URL 中的 `main` 替换为正确的分支名，例如 `master`)*

2.  **运行脚本**:
    ```bash
    ./sh_init.sh
    ```
    脚本将引导您完成各个配置步骤。请根据提示进行选择。

3.  **后续步骤**:
    *   如果安装或更改了 Zsh 设置，请运行 `exec zsh` 或重新打开终端使配置生效。
    *   如果 Zsh 不是您的默认 Shell，并且您希望将其设为默认，请按照脚本末尾的提示执行 `chsh` 命令。
    *   如果您安装了 Powerlevel10k 主题，强烈建议在新 Zsh 会话中运行 `p10k configure` 进行个性化配置。


## 注意事项

*   脚本会修改系统配置文件 (如 `/etc/apt/sources.list`, `~/.pip/pip.conf`, `~/.zshrc`, `/etc/docker/daemon.json` 等)。在修改前，脚本会尝试备份原文件 (例如 `sources.list.bak.YYYYMMDD-HHMMSS`)。
*   请仔细阅读脚本中的提示信息，并根据自己的需求进行选择。
*   虽然脚本力求稳定，但在关键系统上运行前，建议您了解脚本将执行的操作，并自行承担风险。

## 贡献

欢迎通过 [Issues](https://github.com/GitHubsAdministrator/sh_init/issues) 或 [Pull Requests](https://github.com/GitHubsAdministrator/sh_init/pulls) 来改进此脚本。

## 特别感谢

*   Gemini 2.5 Pro (Preview)

## 其他脚本

一键安装tailscale+derper：https://gitee.com/wo99/sh_init/tree/main/tailscale

## 运行日志概览

以下是一次典型的脚本运行交互和主要输出的概览（已省略部分详细的软件包安装过程）：

```bash
$ bash <(wget -qO- https://gitee.com/wo99/sh_init/raw/main/sh_init.sh)
[INFO ] 检查 sudo 权限...
[INFO ] Sudo 权限已确认。
[INFO ] 欢迎使用综合优化版 Shell 环境配置脚本！
[INFO ] 本脚本将引导您完成一系列配置。

是否替换为国内 APT 镜像源 (推荐国内用户)?[Y/n] Y
[INFO ] 开始配置国内 APT 镜像源...
[INFO ] 所有必需的软件包均已安装。
[INFO ] 当前系统代号: plucky
1) 清华大学 TUNA 镜像	 3) 中国科学技术大学镜像  5) Ubuntu 官方中国镜像
2) 阿里云镜像		 4) 网易镜像
请选择 APT 镜像源编号 (默认为 1. 清华大学): 3
[INFO ] 选择的 APT 镜像: 中国科学技术大学镜像 (https://mirrors.ustc.edu.cn/ubuntu/)
[INFO ] 系统主要使用 DEB822 格式，目标文件: /etc/apt/sources.list.d/ubuntu.sources
[INFO ] 备份当前的 /etc/apt/sources.list.d/ubuntu.sources 到 /etc/apt/sources.list.d/ubuntu.sources.bak.20250608-102306...
[INFO ] 正在写入新的 /etc/apt/sources.list.d/ubuntu.sources...
[INFO ] 更新 APT 软件包列表...
[INFO ] APT 镜像源配置完成并已更新。

是否配置常用开发语言的国内镜像 (Python/Go/Node.js)?[Y/n] Y
[INFO ] 开始配置开发语言镜像...
是否配置 pip 阿里云源?[Y/n] Y
[INFO ] pip 镜像源已配置为阿里云源。
[INFO ] 开发语言镜像配置流程结束。

是否安装 Docker 并配置镜像加速?[Y/n] Y
[INFO ] 开始安装 Docker CE 并配置镜像加速...
[INFO ] 准备安装缺失的软件包: apt-transport-https curl gnupg-agent
是否继续安装这些软件包?[Y/n] Y
[INFO ] 软件包 apt-transport-https curl gnupg-agent 安装完成。
是否使用国内 Docker CE APT 镜像源安装 Docker CE?[Y/n] Y
1) 阿里云
2) 清华 TUNA
3) 中科大 USTC
4) 官方
请选择 Docker CE APT 源 (默认 阿里云): 2
[INFO ] 添加 Docker CE 源: 清华 TUNA (https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu)
[INFO ] Docker CE 安装完成。
是否配置 Docker 镜像加速 (镜像 Hub)?[Y/n] Y
是否使用默认镜像加速 https://docker.1panel.live?[Y/n] Y
[INFO ] 使用 jq 合并 Docker 镜像配置到 /etc/docker/daemon.json...
[INFO ] Docker 镜像加速已配置: https://docker.1panel.live

是否安装 Zsh 和 Oh-My-Zsh (强大的 Zsh 配置框架)?[Y/n] Y
[INFO ] 开始安装 Zsh 和 Oh-My-Zsh...
[INFO ] 准备安装缺失的软件包: zsh
是否继续安装这些软件包?[Y/n] Y
[INFO ] 软件包 zsh 安装完成。
[INFO ] Oh-My-Zsh 未安装，准备进行安装。
1) GitHub (官方)
2) Gitee (镜像)
请选择 Oh-My-Zsh 安装脚本源 (默认为 1. GitHub (官方)): 2
[INFO ] 选择的源: Gitee (镜像) (https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh)
[INFO ] 将使用 Git 远程仓库进行克隆: https://gitee.com/mirrors/oh-my-zsh.git
[INFO ] 使用安装脚本: https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh
Cloning Oh My Zsh...
... (Oh My Zsh 安装过程) ...
                        /____/                       ....is now installed!
[INFO ] Oh-My-Zsh 安装成功。
[WARN ] 当前默认 Shell 不是 Zsh。
[INFO ] 要将 Zsh 设置为默认 Shell, 请手动执行以下命令:
[INFO ]   sudo chsh -s "/usr/bin/zsh" "username"
[INFO ] 更改后需要重新登录或重启终端才能生效。
[INFO ] Zsh 和 Oh-My-Zsh 配置流程结束。
是否选择并设置 Zsh 主题?[Y/n] Y
[INFO ] 开始配置 Zsh 主题...
1) haoomz (简洁高效)
2) powerlevel10k (强大, 需额外配置, 推荐 Nerd Font)
...
请选择 Zsh 主题 (默认为 1. haoomz): 2
[INFO ] 选择的主题: powerlevel10k (强大, 需额外配置, 推荐 Nerd Font) (key: powerlevel10k)
[INFO ] 为 'romkatv/powerlevel10k' 选择 Git 克隆源:
1) Gitee (镜像) ...
请选择数字: 1
[INFO ] 选择源: Gitee (镜像) (https://gitee.com/romkatv/powerlevel10k.git)
[INFO ] 克隆 Powerlevel10k 主题从 https://gitee.com/romkatv/powerlevel10k.git 到 /home/username/.oh-my-zsh/custom/themes/powerlevel10k...
[INFO ] Powerlevel10k 主题克隆成功。
[INFO ] Powerlevel10k 主题安装后，建议运行 'p10k configure' 进行个性化配置。
[INFO ] 正在设置 ZSH_THEME="powerlevel10k/powerlevel10k" 到 /home/username/.zshrc...
[INFO ] ZSH_THEME 已在 /home/username/.zshrc 中设置。
[INFO ] Zsh 主题配置完成。

是否配置 Zsh 插件 (增强 Shell 功能)?[Y/n] Y
[INFO ] 开始配置 Zsh 插件...
是否启用一组增强型 Zsh 插件?[Y/n] Y
[INFO ] 已选择启用增强插件集。
[INFO ] 最终插件列表: git z extract zsh-autosuggestions zsh-syntax-highlighting colored-man-pages colorize cp sudo command-not-found history history-substring-search python
[INFO ] 为 'zsh-users/zsh-autosuggestions' 选择 Git 克隆源:
...
请选择数字: 6
[INFO ] 选择源: ghfast.top (https://ghfast.top/https://github.com/zsh-users/zsh-autosuggestions.git)
[INFO ] 克隆插件 'zsh-autosuggestions' 从 ...
[INFO ] 插件 'zsh-autosuggestions' 克隆成功。
[INFO ] 为 'zsh-users/zsh-syntax-highlighting' 选择 Git 克隆源:
...
请选择数字: 6
[INFO ] 选择源: ghfast.top (https://ghfast.top/https://github.com/zsh-users/zsh-syntax-highlighting.git)
[INFO ] 克隆插件 'zsh-syntax-highlighting' 从 ...
[INFO ] 插件 'zsh-syntax-highlighting' 克隆成功。
[INFO ] 为 'zsh-users/zsh-history-substring-search' 选择 Git 克隆源:
...
请选择数字: 6
[INFO ] 选择源: ghfast.top (https://ghfast.top/https://github.com/zsh-users/zsh-history-substring-search.git)
[INFO ] 克隆插件 'history-substring-search' 从 ...
[INFO ] 插件 'history-substring-search' 克隆成功。
[INFO ] 正在更新 /home/username/.zshrc 中的 plugins 列表...
[INFO ] plugins 列表已在 /home/username/.zshrc 中更新。
[INFO ] Zsh 插件配置完成。

[INFO ] 检查并配置代理辅助函数...
是否添加 proxy/unproxy 辅助函数到 /home/username/.zshrc (SOCKS5 127.0.0.1:1089)?[Y/n] y
[INFO ] proxy/unproxy 辅助函数已添加到 /home/username/.zshrc。
[INFO ] 默认 SOCKS5 代理设置为 127.0.0.1:1089, HTTP/HTTPS 代理设置为 127.0.0.1:1080。
... (用法说明) ...
[INFO ] Zsh 和 Oh-My-Zsh 相关配置已完成。

[INFO ] Shell 环境配置流程已全部完成！
[INFO ] 请注意以下后续步骤：
[INFO ] 1. 如果您安装或更改了 Zsh 设置，请运行 'exec zsh' 或重新打开终端使配置生效。
[INFO ] 2. 如果 Zsh 不是您的默认 Shell，并且您希望将其设为默认，请按照之前的提示执行 'chsh' 命令。
[INFO ] 3. 如果您安装了 Powerlevel10k 主题，强烈建议在新 Zsh 会话中运行 'p10k configure' 进行个性化配置。
```
