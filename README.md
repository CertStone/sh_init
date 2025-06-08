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

## 先决条件

*   一个基于 Debian/Ubuntu 的 Linux 发行版。脚本仅在这两个系统上进行过测试，其他系统可能部分功能不适用。
*   `bash` shell。
*   `sudo` 权限。
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
