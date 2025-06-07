#!/usr/bin/env bash
#
# 综合优化版 Shell 环境配置脚本
# 旨在提供一个功能完善、体验流畅的自动化 Shell 环境配置方案，
# 特别关注中国大陆用户的网络环境。
#

set -euo pipefail # 发生错误时立即退出，未定义变量时报错，管道中命令失败时报错

# --- 全局颜色定义 ---
COLOR_RESET='\033[0m'

# 提示信息前缀
LOG_PREFIX="[INFO]"

# 日志级别
LOG_LEVEL=3 # 1=错误 2=警告 3=信息

# 日志输出函数
log() {
  local level="$1"
  shift
  if (( level <= LOG_LEVEL )); then
    local color
    case "$level" in
      1) color="\033[31m" ;; # 红色
      2) color="\033[33m" ;; # 黄色
      3) color="\033[32m" ;; # 绿色
      *) color="\033[0m" ;;  # 默认
    esac
    echo -e "${color}${LOG_PREFIX} $*${COLOR_RESET}"
  fi
}

# 错误日志
log_error() {
  log 1 "$@"
}

# 警告日志
log_warning() {
  log 2 "$@"
}

# 信息日志
log_info() {
  log 3 "$@"
}

# 成功日志
log_success() {
  log 3 "$@"
}

# 等待用户输入 Y/N
ask_yes_no() {
  local prompt="$1"
  local default_reply="${2:-N}"
  local reply

  while true; do
    read -rn1 -p "$prompt " reply || true # 读取单个字符，允许Ctrl+C等中断
    echo # 换行
    [[ -z "$reply" ]] && reply="$default_reply"
    case "$reply" in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
      *) log_warning "无效输入，请输入 Y 或 N。" ;;
    esac
  done
}

# 检查命令是否存在
command_exists() {
  command -v "$1" &>/dev/null
}

# 批量安装缺失的软件包 (Debian/Ubuntu)
install_pkgs_if_needed() {
  local missing_pkgs=()
  for pkg in "$@"; do
    # 修正 “if! dpkg” 语法，添加空格
    if ! dpkg -s "$pkg" &>/dev/null; then # MODIFIED
      missing_pkgs+=("$pkg")
    fi
  done

  if ((${#missing_pkgs[@]} > 0)); then
    log_info "准备安装缺失的软件包: ${missing_pkgs[*]}"
    if ask_yes_no "是否继续安装这些软件包?[Y/n]" "Y"; then
      # 将管道改为逻辑或，避免把输出当作下一命令 stdin
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq || \
        log_warning "APT 更新失败，请检查网络或手动执行。"
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing_pkgs[@]}"
      log_success "软件包 ${missing_pkgs[*]} 安装完成。"
    else
      log_warning "用户选择跳过安装缺失软件包: ${missing_pkgs[*]}"
      return 1 # 表示用户跳过
    fi
  else
    log_info "所有必需的软件包均已安装。"
  fi
}

# --- Git 仓库镜像选择 ---
# 定义 Git 镜像站点，用于加速国内访问
# 格式: "描述=URL前缀" 或 "描述=完整URL" (用于特定脚本)
# 注意：ghproxy.net 等代理有时会附加.git 后缀，使用时需注意
declare -A GIT_MIRROR_SITES=(
  ["GitHub (官方)"]="https://github.com/"
  ["ghproxy.net"]="https://ghproxy.net/https://github.com/"
  ["hub.gitmirror.com"]="https://hub.gitmirror.com/https://github.com/"
  ["mirror.ghproxy.com"]="https://mirror.ghproxy.com/https://github.com/"
  ["github.moeyy.xyz"]="https://github.moeyy.xyz/https://github.com/"
  ["gh.xmly.dev"]="https://gh.xmly.dev/https://github.com/"
  ["gh.api.99988866.xyz"]="https://gh.api.99988866.xyz/https://github.com/"
  ["ghfast.top"]="https://ghfast.top/https://github.com/"
)
# Oh My Zsh 安装脚本的特殊处理
# declare -A OMZ_INSTALL_SOURCES=(
#   ["GitHub (官方)"]="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
#   ["Gitee (镜像)"]="https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh"
# )
OMZ_INSTALL_DESCRIPTIONS=(
  "GitHub (官方)"
  "Gitee (镜像)"
)
OMZ_INSTALL_URLS=(
  "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
  "https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh"
)
OMZ_REPO_CLONE_URLS=(
  "https://github.com/ohmyzsh/ohmyzsh.git"  # 对应 "GitHub (官方)"
  "https://gitee.com/mirrors/oh-my-zsh.git" # 对应 "Gitee (镜像)"
)
# 选择 Git 克隆源
# 参数1: 仓库路径 (例如 romkatv/powerlevel10k)
# 参数2: 目标目录 (可选, 如果为空则使用仓库名)
# 参数3: 是否为.git 后缀的仓库 (true/false, 默认为 true)
# 返回选择的克隆 URL
select_git_clone_source() {
  local repo_path="$1"
  local suffix=".git"
  [[ "${3:-true}" != "true" ]] && suffix=""

  local options=() urls=()
  log_info "为 '$repo_path' 选择 Git 克隆源:" >&2 # 重定向到 stderr

  # 添加 Gitee 上的已知镜像/复刻 (如果适用)
  if [[ "$repo_path" == "romkatv/powerlevel10k" ]]; then
    options+=("Gitee (镜像)")
    urls+=("https://gitee.com/romkatv/powerlevel10k${suffix}") # 官方维护的 Gitee 仓库
  fi

  for descr in "${!GIT_MIRROR_SITES[@]}"; do
    if [[ "$descr" == "Gitee (镜像)" && "$repo_path" != "romkatv/powerlevel10k" ]]; then # MODIFIED: Added spaces around !=
        continue
    fi
    options+=("$descr")
    urls+=("${GIT_MIRROR_SITES[$descr]}${repo_path}${suffix}")
  done

  PS3="请选择数字: "
  select opt in "${options[@]}"; do
    # 修正条件判断与数组索引
    if [[ -n "$opt" ]]; then
      chosen_url="${urls[$((REPLY-1))]}" # MODIFIED: Corrected array indexing
      log_info "选择源: $opt ($chosen_url)" >&2 # 重定向到 stderr
      echo "$chosen_url" # 输出到 stdout，由 $() 捕获
      return 0
    elif [[ -z "$REPLY" ]]; then # MODIFIED: Completed elif condition
      chosen_url="${urls[0]}" # MODIFIED: Corrected array indexing for default
      log_info "选择默认源: ${options[0]} ($chosen_url)" >&2 # 重定向到 stderr
      echo "$chosen_url" # 输出到 stdout，由 $() 捕获
      return 0
    else
      log_warning "无效选择，请重试。" >&2 # 重定向到 stderr
    fi
  done

  log_warning "未能选择有效的 Git 源, 将尝试使用官方 GitHub 源。" >&2 # 重定向到 stderr
  echo "https://github.com/${repo_path}${suffix}" # 输出到 stdout，由 $() 捕获
}


# --- 更换 APT 源 (Debian/Ubuntu) ---
use_china_apt_mirror() {
  log_info "开始配置国内 APT 镜像源..."
  install_pkgs_if_needed lsb-release # 确保 lsb-release 可用

  local codename
  codename=$(lsb_release -sc)
  if [[ -z "$codename" ]]; then
    log_error "无法获取系统代号 (codename)，跳过 APT 镜像配置。"
    return 1
  fi
  log_info "当前系统代号: $codename"

  local mirrors=(
    "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
    "https://mirrors.aliyun.com/ubuntu/"
    "https://mirrors.ustc.edu.cn/ubuntu/"
    "http://mirrors.163.com/ubuntu/"
    "http://cn.archive.ubuntu.com/ubuntu/" # 官方中国镜像
  )
  local mirror_descs=(
    "清华大学 TUNA 镜像"
    "阿里云镜像"
    "中国科学技术大学镜像"
    "网易镜像"
    "Ubuntu 官方中国镜像"
  )
  local chosen_mirror

  PS3="请选择 APT 镜像源编号 (默认为 1. 清华大学): "
  select desc in "${mirror_descs[@]}"; do
    if [[ -n "$desc" ]]; then
      chosen_mirror="${mirrors[$((REPLY-1))]}"
      log_info "选择的 APT 镜像: ${mirror_descs[$((REPLY-1))]} ($chosen_mirror)"
      break
    elif [[ -z "$REPLY" ]]; then
      chosen_mirror="${mirrors[0]}" # 默认清华源
      log_info "选择默认镜像: ${mirror_descs[0]} ($chosen_mirror)"
      break
    else
      log_warning "无效选择，请重新输入。"
    fi
  done

  local sources_list_target="/etc/apt/sources.list" # 默认目标文件
  local is_deb822_format=false

  # 函数：检查文件是否为 DEB822 格式
  check_deb822_format() {
    local file_to_check="$1"
    if [[ ! -f "$file_to_check" ]] || [[ ! -s "$file_to_check" ]]; then
      return 1 # 文件不存在或为空
    fi
    # 读取文件，跳过空行和注释行，检查第一个有效行
    while IFS= read -r line || [[ -n "$line" ]]; do
      # 去除行首空格
      shopt -s extglob
      line="${line##*( )}"
      shopt -u extglob
      if [[ -n "$line" ]] && [[ ! "$line" =~ ^# ]]; then # 非空且非注释行
        if [[ "$line" =~ ^Types: ]]; then
          return 0 # 是 DEB822 格式
        else
          return 1 # 不是 DEB822 格式
        fi
      fi
    done < "$file_to_check"
    return 1 # 如果文件只包含空行或注释行，则认为不是 DEB822
  }

  # 优先检查 /etc/apt/sources.list.d/ 中的标准 .sources 文件
  local primary_dist_sources_file=""
  if [[ -f "/etc/apt/sources.list.d/ubuntu.sources" ]] && check_deb822_format "/etc/apt/sources.list.d/ubuntu.sources"; then
    primary_dist_sources_file="/etc/apt/sources.list.d/ubuntu.sources"
  elif [[ -f "/etc/apt/sources.list.d/debian.sources" ]] && check_deb822_format "/etc/apt/sources.list.d/debian.sources"; then
    primary_dist_sources_file="/etc/apt/sources.list.d/debian.sources"
  fi

  if [[ -n "$primary_dist_sources_file" ]]; then
    is_deb822_format=true
    sources_list_target="$primary_dist_sources_file"
    log_info "系统主要使用 DEB822 格式，目标文件: $sources_list_target"
  else
    # 如果 .sources 文件不存在或不是 DEB822，再检查 /etc/apt/sources.list
    if check_deb822_format "$sources_list_target"; then
      is_deb822_format=true
      log_info "检测到 $sources_list_target 使用 DEB822 格式。"
    elif [[ -f "$sources_list_target" ]] && [[ -s "$sources_list_target" ]]; then
      # 文件存在但不符合DEB822（可能是传统格式，或仅含注释）
      # 如果文件只包含注释，我们仍然倾向于认为系统可能依赖 .d/ 目录下的文件，
      # 但如果没有找到有效的 .sources 文件，我们只能假设它是传统格式或需要被替换。
      # 此时，如果用户选择替换，我们会用新格式覆盖它。
      log_info "检测到 $sources_list_target 使用传统格式或其内容将被替换。"
      # is_deb822_format 保持 false，除非用户明确要用 DEB822 格式写入空的或仅注释的 sources.list
      # 实际上，如果 /etc/apt/sources.list 仅含注释，且没有 .sources 文件，
      # 那么生成传统格式的内容到 /etc/apt/sources.list 是一个合理的行为。
      # 如果用户希望强制使用 DEB822，他们可以手动创建空的 ubuntu.sources 文件。
      # 为了简化，我们这里如果 /etc/apt/sources.list 不是有效的 DEB822，就按传统格式处理。
    else
      log_info "$sources_list_target 为空或不存在。将为 $sources_list_target 生成传统格式。"
      # is_deb822_format 保持 false
    fi
  fi


  # 备份逻辑
  local backup_file_path="${sources_list_target}.bak.$(date +%Y%m%d-%H%M%S)"
  local backup_dir_path
  backup_dir_path=$(dirname "$sources_list_target")
  local backup_file_prefix
  backup_file_prefix="$(basename "$sources_list_target").bak."
  local max_backups=5

  # 清理旧备份
  (ls -1t "${backup_dir_path}/${backup_file_prefix}"* 2>/dev/null || true) | tail -n +$((max_backups + 1)) | xargs -r sudo rm -f

  log_info "备份当前的 $sources_list_target 到 $backup_file_path..."
  if [[ -f "$sources_list_target" ]]; then # 仅当目标文件存在时才备份
    sudo cp "$sources_list_target" "$backup_file_path" || { log_error "备份 $sources_list_target 失败!"; return 1; }
  else
    log_info "$sources_list_target 不存在，无需备份。"
  fi


  log_info "正在写入新的 $sources_list_target..."
  local sources_content=""

  # 再次确认是否应该使用 DEB822 格式写入
  # 如果目标是 .sources 文件，则强制 DEB822
  if [[ "$sources_list_target" == *.sources ]]; then
      is_deb822_format=true
      log_info "目标文件是 ${sources_list_target}，将强制使用 DEB822 格式。"
  fi


  if $is_deb822_format; then
    local os_id
    os_id=$(lsb_release -is 2>/dev/null || echo "Unknown")
    local keyring_path=""

    if [[ "$os_id" == "Ubuntu" ]] && [[ -f "/usr/share/keyrings/ubuntu-archive-keyring.gpg" ]]; then
      keyring_path="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
    elif [[ "$os_id" == "Debian" ]] && [[ -f "/usr/share/keyrings/debian-archive-keyring.gpg" ]]; then
      keyring_path="/usr/share/keyrings/debian-archive-keyring.gpg"
    else
      # 尝试通用回退密钥环路径
      if [[ -f "/usr/share/keyrings/ubuntu-archive-keyring.gpg" ]]; then
          keyring_path="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
          log_warning "操作系统为 '$os_id'。使用 Ubuntu 密钥环作为回退: $keyring_path"
      elif [[ -f "/usr/share/keyrings/debian-archive-keyring.gpg" ]]; then
          keyring_path="/usr/share/keyrings/debian-archive-keyring.gpg"
          log_warning "操作系统为 '$os_id'。使用 Debian 密钥环作为回退: $keyring_path"
      fi
    fi

    local signed_by_line=""
    if [[ -n "$keyring_path" ]]; then
        signed_by_line="Signed-By: ${keyring_path}"
    else
        log_warning "无法自动确定或找到 GPG 密钥环路径。生成的 DEB822 配置中将省略 'Signed-By'。"
        log_warning "这可能导致 APT 无法验证仓库。您可能需要手动编辑 $sources_list_target 并添加正确的 'Signed-By' 行。"
    fi

    sources_content=$(cat <<EOF
# Source: Script generated by configuration script
Types: deb
URIs: ${chosen_mirror}
Suites: ${codename} ${codename}-updates ${codename}-security ${codename}-backports
Components: main restricted universe multiverse
${signed_by_line}
Architectures: $(dpkg --print-architecture)

# Uncomment the following entry to enable source packages
# Types: deb-src
# URIs: ${chosen_mirror}
# Suites: ${codename} ${codename}-updates ${codename}-security ${codename}-backports
# Components: main restricted universe multiverse
# ${signed_by_line}
# Architectures: $(dpkg --print-architecture)
EOF
)
  else # 传统格式
    sources_content=$(cat <<EOF
deb ${chosen_mirror} ${codename} main restricted universe multiverse
deb ${chosen_mirror} ${codename}-updates main restricted universe multiverse
deb ${chosen_mirror} ${codename}-security main restricted universe multiverse
deb ${chosen_mirror} ${codename}-backports main restricted universe multiverse
# deb-src ${chosen_mirror} ${codename} main restricted universe multiverse
# deb-src ${chosen_mirror} ${codename}-updates main restricted universe multiverse
# deb-src ${chosen_mirror} ${codename}-security main restricted universe multiverse
# deb-src ${chosen_mirror} ${codename}-backports main restricted universe multiverse
EOF
)
  fi

  # 创建目标目录以防万一（主要针对 .list.d/ 中的文件）
  sudo mkdir -p "$(dirname "$sources_list_target")"
  echo "$sources_content" | sudo tee "$sources_list_target" >/dev/null || { log_error "写入 $sources_list_target 失败!"; return 1; }

  log_info "更新 APT 软件包列表..."
  sudo apt-get update -qq || { log_warning "APT 更新失败，可能是镜像源问题或网络问题。请检查 $sources_list_target 或稍后手动执行 'sudo apt-get update'。"; return 1; }
  log_success "APT 镜像源配置完成并已更新。"
}

# --- 配置开发语言镜像 ---
configure_lang_mirrors() {
  log_info "开始配置开发语言镜像..."

  if command_exists pip3 || command_exists pip; then # MODIFIED: Correct use of || in if
    if ask_yes_no "是否配置 pip 阿里云源?[Y/n]" "Y"; then
      local pip_conf_file="$HOME/.pip/pip.conf"
      local aliyun_pip_mirror_host="mirrors.aliyun.com"
      local aliyun_pip_mirror_url="http://${aliyun_pip_mirror_host}/pypi/simple/"
      
      if [[ -f "$pip_conf_file" ]] && grep -q "index-url *= *${aliyun_pip_mirror_url}" "$pip_conf_file"; then
        log_info "pip 镜像已配置为阿里云，跳过。"
      else
        if [[ -f "$pip_conf_file" ]]; then
            if ! ask_yes_no "检测到现有 pip 配置文件 $pip_conf_file。是否覆盖以配置阿里云镜像?[y/N]" "N"; then
                log_info "保留现有 pip 配置。"
                # Skip pip configuration for this run if user says no to overwrite
            else
                 mkdir -p ~/.pip
                 cat > "$pip_conf_file" <<EOF
[global]
index-url = ${aliyun_pip_mirror_url}

[install]
trusted-host=${aliyun_pip_mirror_host}
EOF
                 log_success "pip 镜像源已配置为阿里云源。"
            fi
        else
            mkdir -p ~/.pip
            cat > "$pip_conf_file" <<EOF
[global]
index-url = ${aliyun_pip_mirror_url}

[install]
trusted-host=${aliyun_pip_mirror_host}
EOF
            log_success "pip 镜像源已配置为阿里云源。"
        fi
      fi
    else
      log_info "跳过 pip 镜像配置。"
    fi
  fi

  if command_exists go; then
    if ask_yes_no "是否设置 GOPROXY 为国内镜像 (goproxy.cn)?[Y/n]" "Y"; then
      go env -w GOPROXY=https://goproxy.cn,direct
      go env -w GOSUMDB=sum.golang.google.cn # 推荐配合goproxy.cn使用
      log_success "GOPROXY 已配置为 goproxy.cn, GOSUMDB 已配置为 sum.golang.google.cn。"
    else
      log_info "跳过 Go Proxy 配置。"
    fi
  fi

  if command_exists npm; then
    if ask_yes_no "是否配置 npm 中国镜像 (淘宝 npmmirror)?[Y/n]" "Y"; then
      npm config set registry https://registry.npmmirror.com
      log_success "npm 镜像源已配置为淘宝 npmmirror。"
    else
      log_info "跳过 npm 镜像配置。"
    fi
  fi
  log_info "开发语言镜像配置流程结束。"
}

# --- 安装 Zsh & Oh-My-Zsh ---
install_zsh_and_omz() {
  log_info "开始安装 Zsh 和 Oh-My-Zsh..."
  install_pkgs_if_needed zsh git curl wget

  # 修正 “[[-d” 语法，添加空格
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then # MODIFIED
    log_info "Oh-My-Zsh 未安装，准备进行安装。"
    
    local omz_install_url
    local omz_repo_remote_url # 新增变量，用于存储选择的远程克隆 URL

    PS3="请选择 Oh-My-Zsh 安装脚本源 (默认为 1. ${OMZ_INSTALL_DESCRIPTIONS[0]}): " # MODIFIED
    select opt in "${OMZ_INSTALL_DESCRIPTIONS[@]}"; do # MODIFIED
      if [[ -n "$opt" ]]; then
        local selected_index=$((REPLY-1))
        omz_install_url="${OMZ_INSTALL_URLS[$selected_index]}"
        omz_repo_remote_url="${OMZ_REPO_CLONE_URLS[$selected_index]}" # 从新数组获取克隆 URL
        log_info "选择的源: $opt ($omz_install_url)"
        log_info "将使用 Git 远程仓库进行克隆: $omz_repo_remote_url" # 增加日志提示
        break
      elif [[ -z "$REPLY" ]]; then 
        local selected_index=0 # 默认选择第一个
        omz_install_url="${OMZ_INSTALL_URLS[$selected_index]}"
        omz_repo_remote_url="${OMZ_REPO_CLONE_URLS[$selected_index]}" # 默认克隆 URL
        log_info "选择默认源: ${OMZ_INSTALL_DESCRIPTIONS[$selected_index]} ($omz_install_url)"
        log_info "将使用 Git 远程仓库进行克隆: $omz_repo_remote_url" # 增加日志提示
        break
      else
        log_warning "无效选择，请重试。"
      fi
    done

    log_info "使用安装脚本: $omz_install_url"
    # 在执行安装脚本时，通过 REMOTE 环境变量传递选择的克隆 URL
    if REMOTE="$omz_repo_remote_url" RUNZSH=no CHSH=no sh -c "$(curl -fsSL "$omz_install_url")"; then
      log_success "Oh-My-Zsh 安装成功。"
    else
      log_error "Oh-My-Zsh 安装失败。"
      return 1
    fi
  else
    log_info "检测到 ~/.oh-my-zsh 目录已存在，跳过安装。"
  fi

  # 提示用户手动更改默认 shell
  if [[ "$SHELL" != *zsh* ]]; then # MODIFIED
    local zsh_path
    zsh_path=$(command -v zsh)
    if [[ -n "$zsh_path" ]]; then
      log_warning "当前默认 Shell 不是 Zsh。"
      log_info "要将 Zsh 设置为默认 Shell, 请手动执行以下命令:"
      log_info "  sudo chsh -s \"$zsh_path\" \"$(whoami)\""
      log_info "更改后需要重新登录或重启终端才能生效。"
    else
      log_error "未找到 Zsh 执行路径，无法提示更改默认 Shell。"
    fi
  else
    log_info "Zsh 已经是当前默认 Shell。"
  fi
  log_info "Zsh 和 Oh-My-Zsh 配置流程结束。"
}

# --- Zsh 主题配置 ---
set_zsh_theme() {
  log_info "开始配置 Zsh 主题..."
  local ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM_DIR/themes"

  local themes_options=("haoomz" "powerlevel10k" "ys" "robbyrussell" "agnoster" "skip")
  local themes_names=(
    "haoomz (简洁高效)"
    "powerlevel10k (强大, 需额外配置, 推荐 Nerd Font)"
    "ys (Oh-My-Zsh 经典)"
    "robbyrussell (Oh-My-Zsh 默认)"
    "agnoster (经典 Powerline 风格, 需 Powerline 字体)"
    "跳过主题设置/保持当前主题"
  )
  local chosen_theme_key
  local chosen_theme_name

  PS3="请选择 Zsh 主题 (默认为 1. haoomz): "
  select name in "${themes_names[@]}"; do
    if [[ -n "$name" ]]; then
      chosen_theme_key="${themes_options[$((REPLY-1))]}" # MODIFIED
      chosen_theme_name="$name"
      break
    elif [[ -z "$REPLY" ]]; then # MODIFIED
      chosen_theme_key="${themes_options[0]}" # 默认 haoomz # MODIFIED
      chosen_theme_name="${themes_names[0]}" # MODIFIED
      log_info "选择默认主题: $chosen_theme_name"
      break
    else
      log_warning "无效选择，请重新输入。"
    fi
  done

  log_info "选择的主题: $chosen_theme_name (key: $chosen_theme_key)"

  if [[ "$chosen_theme_key" == "skip" ]]; then
    log_info "用户选择跳过主题设置。"
    return 0
  fi

  local theme_to_set_in_zshrc="$chosen_theme_key"

  case "$chosen_theme_key" in
    haoomz)
      local haoomz_url="https://cdn.haoyep.com/gh/leegical/Blog_img/zsh/haoomz.zsh-theme"
      local haoomz_path="$ZSH_CUSTOM_DIR/themes/haoomz.zsh-theme"
      log_info "下载 haoomz 主题到 $haoomz_path..."
      if curl -fsSL -o "$haoomz_path" "$haoomz_url"; then
        log_success "haoomz 主题下载成功。"
      else
        log_error "haoomz 主题下载失败。请检查网络或 URL: $haoomz_url"
        return 1
      fi
      ;;
    powerlevel10k)
      local p10k_repo_path="romkatv/powerlevel10k"
      local p10k_target_dir="$ZSH_CUSTOM_DIR/themes/powerlevel10k"
      if [[ -d "$p10k_target_dir" ]]; then
        log_info "Powerlevel10k 目录已存在，跳过克隆。"
      else
        local p10k_clone_url
        p10k_clone_url=$(select_git_clone_source "$p10k_repo_path")
        log_info "克隆 Powerlevel10k 主题从 $p10k_clone_url 到 $p10k_target_dir..."
        if git clone --depth=1 "$p10k_clone_url" "$p10k_target_dir"; then
          log_success "Powerlevel10k 主题克隆成功。"
        else
          log_error "Powerlevel10k 主题克隆失败。请检查网络或 Git 源。"
          return 1
        fi
      fi
      theme_to_set_in_zshrc="powerlevel10k/powerlevel10k"
      log_info "Powerlevel10k 主题安装后，建议运行 'p10k configure' 进行个性化配置。"
      log_info "为获得最佳 Powerlevel10k 显示效果，请确保已安装并配置 Nerd Font (如 MesloLGS NF)。"
      ;;
  esac

  # 修改 ~/.zshrc 中的 ZSH_THEME
  local zshrc_file="$HOME/.zshrc"
  if [[ -f "$zshrc_file" ]]; then
    log_info "正在设置 ZSH_THEME=\"$theme_to_set_in_zshrc\" 到 $zshrc_file..."
    # 使用 sed 进行替换，如果 ZSH_THEME 行存在则替换，不存在则追加
    if grep -q '^ZSH_THEME=' "$zshrc_file"; then
      sed -i.bak -e "s|^ZSH_THEME=.*|ZSH_THEME=\"$theme_to_set_in_zshrc\"|" "$zshrc_file"
    else
      echo -e "\n# Set Zsh theme\nZSH_THEME=\"$theme_to_set_in_zshrc\"" >> "$zshrc_file"
    fi
    log_success "ZSH_THEME 已在 $zshrc_file 中设置。"
  else
    log_warning "$zshrc_file 未找到。Oh-My-Zsh 可能未正确初始化。请检查 Oh-My-Zsh 安装步骤。"
    return 1
  fi
  log_info "Zsh 主题配置完成。"
}

# --- Zsh 插件安装与配置 ---
install_zsh_plugins() {
  log_info "开始配置 Zsh 插件..."
  local ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM_DIR/plugins"

  # 核心插件列表 (OMZ 内建或需克隆)
  # 格式: plugin_name[:repo_path_if_external]
  # repo_path_if_external 是 user/repo 格式
  local core_plugins=(
    "git"  # OMZ 内建
    "z"    # OMZ 内建 (替代 fasd/autojump)
    "extract" # OMZ 内建 (快速解压任意压缩包)
    "zsh-autosuggestions:zsh-users/zsh-autosuggestions"
    "zsh-syntax-highlighting:zsh-users/zsh-syntax-highlighting"
  )
  # 增强插件列表 (OMZ 内建)
  local enhanced_plugins_omz=(
    "colored-man-pages"
    "colorize"
    "cp" # 带进度条的 cp
    "sudo" # 双击 Esc 快速加 sudo
    "command-not-found" # 友好提示未找到命令的包
    "history" # 共享历史等
    "history-substring-search:zsh-users/zsh-history-substring-search" # OMZ 内建版本可能较旧，这里用外部确保最新
    "python" # virtualenv 自动激活等
  )

  local final_plugins_list=()

  # 添加核心插件
  for p_info in "${core_plugins[@]}"; do
    final_plugins_list+=("${p_info%%:*}") # 只取插件名
  done

  if ask_yes_no "是否启用一组增强型 Zsh 插件?[Y/n]" "Y"; then
    for p_info in "${enhanced_plugins_omz[@]}"; do
      final_plugins_list+=("${p_info%%:*}")
    done
    log_info "已选择启用增强插件集。"
  else
    log_info "未启用增强插件集。"
  fi

  log_info "最终插件列表: ${final_plugins_list[*]}"

  # 克隆缺失的外部插件
  local all_plugins_to_check=("${core_plugins[@]}" "${enhanced_plugins_omz[@]}")
  for p_info in "${all_plugins_to_check[@]}"; do
    if [[ "$p_info" == *":"* ]]; then # 是外部插件
      local plugin_name="${p_info%%:*}"
      local plugin_repo_path="${p_info#*:}"
      local plugin_target_dir="$ZSH_CUSTOM_DIR/plugins/$plugin_name"

      if [[ -d "$plugin_target_dir" ]]; then
        log_info "插件 '$plugin_name' 目录已存在，跳过克隆。"
      else
        # 检查 final_plugins_list 是否包含此插件，避免不必要的下载
        local should_clone=false
        for item in "${final_plugins_list[@]}"; do
            if [[ "$item" == "$plugin_name" ]]; then
                should_clone=true
                break
            fi
        done

        if ! $should_clone; then # MODIFIED
            log_info "插件 '$plugin_name' 未被选中，跳过下载。"
            continue
        fi
        
        local plugin_clone_url
        plugin_clone_url=$(select_git_clone_source "$plugin_repo_path" "$plugin_name")
        log_info "克隆插件 '$plugin_name' 从 $plugin_clone_url 到 $plugin_target_dir..."
        if git clone --depth=1 "$plugin_clone_url" "$plugin_target_dir"; then
          log_success "插件 '$plugin_name' 克隆成功。"
        else
          log_error "插件 '$plugin_name' 克隆失败。请检查网络或 Git 源。"
          # 即使单个插件失败，也继续尝试其他插件和配置
        fi
      fi
    fi
  done

  # 更新 ~/.zshrc 中的 plugins 数组
  local zshrc_file="$HOME/.zshrc"
  if [[ -f "$zshrc_file" ]]; then
    log_info "正在更新 $zshrc_file 中的 plugins 列表..."
    local plugins_string="plugins=(${final_plugins_list[*]})"
    # 使用 sed 进行替换，如果 plugins= 行存在则替换，不存在则追加
    # 需要处理 plugins=(...) 和 plugins=(... ) 等多种格式
    if grep -q -E '^\s*plugins=\(.*' "$zshrc_file"; then
      sed -i.bak -E "s|^\s*plugins=\([^)]*\)|${plugins_string}|" "$zshrc_file"
    else
      echo -e "\n# Set Zsh plugins\n${plugins_string}" >> "$zshrc_file"
    fi
    log_success "plugins 列表已在 $zshrc_file 中更新。"
  else
    log_warning "$zshrc_file 未找到。无法配置插件。请检查 Oh-My-Zsh 安装。"
    return 1
  fi
  log_info "Zsh 插件配置完成。"
}

# --- 追加代理辅助函数到.zshrc ---
ensure_proxy_functions() {
  log_info "检查并配置代理辅助函数..."
  local zshrc_file="$HOME/.zshrc"
  if ! grep -q '^# === Proxy helpers ===' "$zshrc_file" 2>/dev/null; then # MODIFIED
    if ask_yes_no "是否添加 proxy/unproxy 辅助函数到 $zshrc_file (SOCKS5 127.0.0.1:1089)?[Y/n]" "Y"; then
      cat >> "$zshrc_file" <<'EOF'

# === Proxy helpers ===
# 设置 SOCKS5 代理 (默认 127.0.0.1:1089)
proxy() {
  export ALL_PROXY="socks5://127.0.0.1:1089"
  export HTTP_PROXY="http://127.0.0.1:1080" # 假设 HTTP 代理端口为 1080
  export HTTPS_PROXY="http://127.0.0.1:1080" # 假设 HTTPS 代理端口为 1080
  # 对于某些应用，可能还需要设置 http_proxy 和 https_proxy (小写)
  export http_proxy="$HTTP_PROXY"
  export https_proxy="$HTTPS_PROXY"
  echo "代理已启用: ALL_PROXY=$ALL_PROXY, HTTP(S)_PROXY=$HTTP_PROXY"
  echo "提示: 某些应用可能需要不同的代理端口或类型，请按需修改此函数。"
}

# 取消代理
unproxy() {
  unset ALL_PROXY HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
  echo "代理已禁用。"
}
EOF
      log_success "proxy/unproxy 辅助函数已添加到 $zshrc_file。"
      log_info "默认 SOCKS5 代理设置为 127.0.0.1:1089, HTTP/HTTPS 代理设置为 127.0.0.1:1080。"
      log_info "您可以编辑 $zshrc_file 中的 proxy 函数以修改默认端口。"
    else
      log_info "跳过添加 proxy/unproxy 辅助函数。"
    fi
  else
    log_info "检测到 proxy/unproxy 辅助函数已存在于 $zshrc_file，跳过添加。"
  fi
}

install_docker_and_config() {
  log_info "开始安装 Docker CE 并配置镜像加速..."
  sudo apt-get update -qq
  install_pkgs_if_needed apt-transport-https ca-certificates curl gnupg-agent software-properties-common jq # ADDED jq as a dependency for daemon.json merging

  # 选择 Docker CE APT 安装源
  if ask_yes_no "是否使用国内 Docker CE APT 镜像源安装 Docker CE?[Y/n]" "Y"; then
    local sources=("阿里云" "清华 TUNA" "中科大 USTC" "官方")
    local urls=(
      "https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
      "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu"
      "https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu"
      "https://download.docker.com/linux/ubuntu"
    )
    PS3="请选择 Docker CE APT 源 (默认 阿里云): "
    select src in "${sources[@]}"; do
      if [[ -n "$src" ]]; then
        mirror_base="${urls[$REPLY-1]}"
        break
      elif [[ -z "$REPLY" ]]; then
        mirror_base="${urls[0]}"
        src="${sources[0]}"
        break
      else
        log_warning "无效选择，请重新输入。"
      fi
    done
    log_info "添加 Docker CE 源: $src ($mirror_base)"
    
    # 创建keyrings目录
    sudo mkdir -p /etc/apt/keyrings
    # 下载并安装GPG密钥到keyrings目录
    curl -fsSL "$mirror_base/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
      || { log_error "添加 Docker GPG key 失败"; return 1; }
    # 使用signed-by选项引用密钥
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] $mirror_base $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null \
      || { log_error "添加 Docker apt 源失败"; return 1; }
  else
    log_info "使用官方 Docker CE APT 源安装。"
    # 创建keyrings目录
    sudo mkdir -p /etc/apt/keyrings
    # 下载并安装GPG密钥到keyrings目录
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
      || { log_error "添加官方 Docker GPG key 失败"; return 1; }
    # 使用signed-by选项引用密钥
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null \
      || { log_error "添加官方 Docker apt 源失败"; return 1; }
  fi

  sudo apt-get update -qq
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    || { log_error "Docker 安装失败"; return 1; }
  log_success "Docker CE 安装完成。"

  # 选择是否配置镜像加速
  if ask_yes_no "是否配置 Docker 镜像加速 (镜像 Hub)?[Y/n]" "Y"; then
    local default_mirror="https://docker.1panel.live" # Example, can be changed
    local mirror_url
    if ask_yes_no "是否使用默认镜像加速 ${default_mirror}?[Y/n]" "Y"; then
      mirror_url="$default_mirror"
    else
      read -rp "请输入自定义镜像加速地址 (例如 https://dockerhub.azk8s.cn): " mirror_url
      if [[ -z "$mirror_url" ]]; then
        log_warning "未输入镜像地址，跳过 Docker 镜像加速配置。"
        return
      fi
    fi

    local docker_daemon_json="/etc/docker/daemon.json"
    sudo mkdir -p /etc/docker

    if command_exists jq; then
      log_info "使用 jq 合并 Docker 镜像配置到 $docker_daemon_json..."
      local temp_json
      temp_json=$(mktemp)
      # Create a basic JSON if the file doesn't exist or is empty
      if [[ ! -s "$docker_daemon_json" ]]; then
        echo '{}' | sudo tee "$docker_daemon_json" > /dev/null
      fi
      # Merge new mirror. This will add or replace the registry-mirrors key.
      # If registry-mirrors exists and is not an array, it will be overwritten.
      # A more robust jq script could merge into an existing array if needed.
      sudo jq --arg new_mirror "$mirror_url" '.["registry-mirrors"] = if .["registry-mirrors"] | type == "array" then .["registry-mirrors"] | if any(. == $new_mirror) then . else . + [$new_mirror] end else [$new_mirror] end' "$docker_daemon_json" > "$temp_json" && \
      sudo mv "$temp_json" "$docker_daemon_json"
      if [[ -f "$temp_json" ]]; then rm -f "$temp_json"; fi # Clean up temp file
    else
      log_warning "jq 命令未找到。将直接覆盖 $docker_daemon_json (如果存在会备份)。"
      if [[ -f "$docker_daemon_json" ]]; then
        sudo cp "$docker_daemon_json" "${docker_daemon_json}.bak.$(date +%Y%m%d-%H%M%S)"
        log_info "已备份现有 $docker_daemon_json 为 ${docker_daemon_json}.bak..."
      fi
      sudo tee "$docker_daemon_json" > /dev/null <<EOF
{
  "registry-mirrors": ["$mirror_url"]
}
EOF
    fi
    sudo systemctl daemon-reload && sudo systemctl restart docker || { log_error "Docker 服务重载或重启失败。"; return 1; }
    log_success "Docker 镜像加速已配置: $mirror_url"
  else
    log_info "跳过 Docker 镜像加速配置。"
  fi
}

# --- Function to ensure sudo privileges ---
ensure_sudo_privileges() {
  log_info "检查 sudo 权限..."
  if ! command_exists sudo; then
    log_error "sudo 命令未找到。请安装 sudo。"
    exit 1
  fi
  if ! sudo -v; then
    log_error "无法获取 sudo 权限。脚本需要 sudo 权限来执行某些操作。"
    log_info "请输入您的密码以授予 sudo 权限，或以 root 用户身份运行此脚本。"
    # Attempt to get sudo password explicitly if -v fails silently
    if ! sudo -p "请输入 sudo 密码: " true; then
        log_error "获取 sudo 权限失败。正在退出。"
        exit 1
    fi
  fi
  # Keep sudo alive in background (optional, can be complex to manage robustly)
  # (while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &)
  log_success "Sudo 权限已确认。"
}


# --- 主流程 ---
main() {
  ensure_sudo_privileges # 首先获取并保持 sudo 权限

  log_info "欢迎使用综合优化版 Shell 环境配置脚本！"
  log_info "本脚本将引导您完成一系列配置。"
  echo # 空行增加可读性

  if [[ "$(uname -s)" != "Linux" ]]; then # MODIFIED
      log_warning "本脚本主要为 Linux (特别是 Ubuntu ) 设计。"
      ask_yes_no "您的系统不是 Linux，是否仍要继续 (某些功能可能不适用)?[y/N]" "N" || exit 0 # MODIFIED: Corrected pipe to OR
  fi

  if ask_yes_no "是否替换为国内 APT 镜像源 (推荐国内用户)?[Y/n]" "Y"; then
    use_china_apt_mirror
  else
    log_info "跳过替换 APT 镜像源。"
  fi
  echo # 分隔

  if ask_yes_no "是否配置常用开发语言的国内镜像 (Python/Go/Node.js)?[Y/n]" "Y"; then
    configure_lang_mirrors
  else
    log_info "跳过配置开发语言镜像。"
  fi
  echo # 分隔

  if ask_yes_no "是否安装 Docker 并配置镜像加速?[Y/n]" "Y"; then
    install_docker_and_config
  else
    log_info "跳过 Docker 安装及镜像加速配置。"
  fi
  echo # 分隔

  if ask_yes_no "是否安装 Zsh 和 Oh-My-Zsh (强大的 Zsh 配置框架)?[Y/n]" "Y"; then
    if install_zsh_and_omz; then
      if ask_yes_no "是否选择并设置 Zsh 主题?[Y/n]" "Y"; then
        set_zsh_theme
      else
        log_info "跳过 Zsh 主题设置。"
      fi
      echo # 分隔

      if ask_yes_no "是否配置 Zsh 插件 (增强 Shell 功能)?[Y/n]" "Y"; then
        install_zsh_plugins
      else
        log_info "跳过 Zsh 插件配置。"
      fi
      echo # 分隔
      
      ensure_proxy_functions

      echo # 分隔
      log_info "Zsh 和 Oh-My-Zsh 相关配置已完成。"
    else
      log_warning "Oh-My-Zsh 安装未成功完成，后续 Zsh 相关配置已跳过。"
    fi
  else
    log_info "跳过安装 Zsh 和 Oh-My-Zsh 及其相关配置。"
  fi
  echo # 分隔

  log_success "Shell 环境配置流程已全部完成！"
  log_info "请注意以下后续步骤："
  log_info "1. 如果您安装或更改了 Zsh 设置，请运行 'exec zsh' 或重新打开终端使配置生效。"
  log_info "2. 如果 Zsh 不是您的默认 Shell，并且您希望将其设为默认，请按照之前的提示执行 'chsh' 命令。"
  log_info "3. 如果您安装了 Powerlevel10k 主题，强烈建议在新 Zsh 会话中运行 'p10k configure' 进行个性化配置。"
}

# --- 脚本执行入口 ---
main "$@"