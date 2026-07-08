#!/bin/bash
#
# EasyTier 一键部署脚本（Linux，公开版）
#
# 下载 EasyTier 预编译二进制并配置 systemd 开机自启服务。
# 启动参数（easytier-core 之后的全部命令行）完全由用户输入。
#
# 当 GitHub 不可达时，自动探测并切换到镜像站下载。
#
# 用法:
#   sudo ./deploy.sh [install] [安装路径] [选项]
#   sudo ./deploy.sh uninstall
#
# 选项:
#   --exec-args "<args>"   非交互指定启动参数（easytier-core 之后的全部命令行）
#   --no-gh-proxy          强制直连 GitHub，不探测镜像
#   --gh-proxy <URL>       强制使用指定镜像站（拼在 GitHub URL 之前）
#
# 环境变量:
#   EXEC_ARGS              等价于 --exec-args
#   INSTALL_PATH           等价于位置参数 [安装路径]
#
# 仅支持 systemd。需 root、unzip、curl。

set -u

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
RES='\e[0m'

GITHUB_API='https://api.github.com/repos/EasyTier/EasyTier/releases/latest'
GITHUB_DOWNLOAD_BASE='https://github.com/EasyTier/EasyTier/releases/latest/download'

# 自动模式下依次尝试的镜像站（拼在 GitHub URL 之前）
GH_PROXY_LIST=(
  'https://ghfast.top/'
  'https://gh-proxy.com/'
  'https://mirror.ghproxy.com/'
)

PROBE_CONNECT_TIMEOUT=5
PROBE_MAX_TIME=10

# 暂存目录（install 中创建，EXIT trap 兜底清理）
STAGE_DIR=''

HELP() {
  echo -e "\r\n${GREEN}EasyTier 一键部署脚本（公开版）${RES}\r\n"
  echo "下载 EasyTier 并配置 systemd 开机自启，启动参数完全由用户输入。"
  echo
  echo "用法: sudo $0 [command] [安装路径] [options]"
  echo
  echo "Commands:"
  echo "  install    下载并安装 EasyTier，配置开机自启（默认）"
  echo "  uninstall  卸载 EasyTier 及其服务"
  echo "  help       显示本帮助"
  echo
  echo "Options:"
  echo "  --exec-args \"<args>\"  非交互指定启动参数（easytier-core 之后的全部命令行）"
  echo "  --no-gh-proxy          强制直连 GitHub，不探测镜像"
  echo "  --gh-proxy <URL>       强制使用指定镜像站"
  echo
  echo "启动参数示例（--exec-args 的值）："
  echo "  -w udp://your-config-server:65432/your-token --machine-id my-host-001"
  echo "  -p tcp://1.2.3.4:11010 --network-name mynet --network-secret s3cret"
  echo "  -c /opt/easytier/config/default.conf"
  echo
  echo "Examples:"
  echo "  sudo $0 install /opt/easytier --exec-args \"-w udp://host:65432/tok --machine-id id1\""
  echo "  sudo $0 --no-gh-proxy"
  echo "  sudo $0 uninstall"
  echo
  echo "环境变量 EXEC_ARGS / INSTALL_PATH 可替代 --exec-args / 位置参数。"
}

# ---------- 终端工具 ----------
info()  { echo -e "${GREEN}$*${RES}"; }
warn()  { echo -e "${YELLOW}$*${RES}"; }
err()   { echo -e "${RED}$*${RES}" 1>&2; }
die()   { err "$*"; exit 1; }

# ---------- 兜底清理（正常退出 / 中断 / 失败均触发）----------
cleanup() {
  if [ -n "${STAGE_DIR:-}" ] && [ -d "${STAGE_DIR:-}" ]; then
    rm -rf "$STAGE_DIR"
  fi
  rm -f /tmp/easytier_deploy.zip
}
trap cleanup EXIT INT TERM

# ---------- 解析命令 / 选项 ----------
COMMAND=''
if [ $# -ge 1 ] && [ "${1:0:2}" != '--' ]; then
  COMMAND="$1"
  shift
fi
[ -z "$COMMAND" ] && COMMAND='install'

if [ "$COMMAND" = 'help' ]; then
  HELP
  exit 0
fi

EXEC_ARGS_ARG=''
NO_GH_PROXY=false
GH_PROXY_OVERRIDE=''
# 注意：不在此处把 INSTALL_PATH 显式置空，否则会覆盖同名环境变量。
# 解析顺序：命令行位置参数 > 环境变量 INSTALL_PATH > /opt/easytier

# 首个非 -- 开头的位置参数作为安装路径
if [ $# -ge 1 ] && [ "${1:0:2}" != '--' ]; then
  INSTALL_PATH="$1"
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --exec-args)
      [ -z "${2:-}" ] && die '--exec-args 需要一个参数'
      EXEC_ARGS_ARG="$2"; shift 2 ;;
    --exec-args=*)
      EXEC_ARGS_ARG="${1#*=}"; shift ;;
    --no-gh-proxy)
      NO_GH_PROXY=true; shift ;;
    --gh-proxy)
      [ -z "${2:-}" ] && die '--gh-proxy 需要一个 URL'
      GH_PROXY_OVERRIDE="$2"; shift 2 ;;
    --gh-proxy=*)
      GH_PROXY_OVERRIDE="${1#*=}"; shift ;;
    *)
      die "未知选项: $1" ;;
  esac
done

# 安装路径默认值（命令行 > 环境变量 > /opt/easytier）
[ -z "${INSTALL_PATH:-}" ] && INSTALL_PATH='/opt/easytier'
INSTALL_PATH="${INSTALL_PATH%/}"

# ---------- 前置检查 ----------
[ "$(id -u)" != '0' ] && die '本脚本需要以 root 身份运行（请使用 sudo）。'

command -v unzip >/dev/null 2>&1 || die '未安装 unzip，请先安装（如 apt install unzip / yum install unzip）。'
command -v curl   >/dev/null 2>&1 || die '未安装 curl，请先安装（如 apt install curl / yum install curl）。'

if ! command -v systemctl >/dev/null 2>&1; then
  die '未检测到 systemd，本脚本仅支持 systemd 系统。'
fi

# 拒绝危险/过宽安装路径，避免误写系统目录
case "$INSTALL_PATH" in
  ''|'/'|'/usr'|'/usr/'|'/bin'|'/sbin'|'/lib'|'/lib64'|'/etc'|'/etc/'|'/boot'|'/dev'|'/proc'|'/sys'|'/var'|'/var/')
    die "非法或过宽的安装路径: '${INSTALL_PATH}'，拒绝执行。" ;;
esac

# ---------- 架构检测 ----------
if command -v arch >/dev/null 2>&1; then
  platform="$(arch)"
else
  platform="$(uname -m)"
fi

case "$platform" in
  amd64|x86_64)        ARCH='x86_64' ;;
  arm64|aarch64|*armv8*) ARCH='aarch64' ;;
  *armv7*)             ARCH='armv7' ;;
  *arm*)               ARCH='arm' ;;
  mips)                ARCH='mips' ;;
  mipsel)              ARCH='mipsel' ;;
  *)                   ARCH='UNKNOWN' ;;
esac

# ARM hard-float 探测（沿用官方 install.sh 约定）
if [ "$ARCH" = 'armv7' ] || [ "$ARCH" = 'arm' ]; then
  if grep Features /proc/cpuinfo 2>/dev/null | grep -qi 'half'; then
    ARCH="${ARCH}hf"
  fi
fi

[ "$ARCH" = 'UNKNOWN' ] && die "不支持的平台: ${platform}。请手动从 GitHub Releases 下载对应包。"
echo -e "${GREEN}检测到平台: ${ARCH} (${platform})${RES}"

# ---------- 启动参数校验与解析 ----------
# 校验：禁止空值，以及会破坏 systemd unit 文件或 shell 的字符（换行、NUL）。
# 不做字符白名单：easytier 参数含 URL/逗号/冒号/等号/路径等，白名单会过度限制。
validate_exec_args() {
  local args="$1"
  if [ -z "$args" ] || [ -z "$(printf '%s' "$args" | tr -d '[:space:]')" ]; then
    warn '启动参数不能为空（至少需要 -w / -p / -c 之一）。'
    return 1
  fi
  # 含换行会破坏 unit 文件的单行 ExecStart
  case "$args" in
    *$'\n'*|*$'\r'*) warn '启动参数不能包含换行符。'; return 1 ;;
    *\\n*|*\\r*) warn '启动参数不能包含字面 \\n / \\r。'; return 1 ;;
  esac
  return 0
}

resolve_exec_args() {
  local args="$EXEC_ARGS_ARG"
  [ -z "$args" ] && args="${EXEC_ARGS:-}"

  if [ -n "$args" ]; then
    if ! validate_exec_args "$args"; then
      die '通过 --exec-args / EXEC_ARGS 传入的值非法，已退出。'
    fi
    EXEC_ARGS="$args"
    return
  fi

  # 交互式提示，输入为空或非法则重试
  cat <<TIP

${YELLOW}请输入 easytier-core 的启动参数${RES}
（即 easytier-core 命令名之后的全部命令行，空格分隔）。例如：
  -w udp://your-config-server:65432/your-token --machine-id my-host-001
  -p tcp://1.2.3.4:11010 --network-name mynet --network-secret s3cret
  -c /opt/easytier/config/default.conf

TIP
  while true; do
    printf '%b启动参数> %b' "${YELLOW}" "${RES}"
    # read 遇到 EOF（非交互/管道输入已耗尽）返回非零，避免死循环
    if ! read -r args; then
      echo
      die '无法读取输入（非交互式终端或输入已结束）。请用 --exec-args 或 EXEC_ARGS 环境变量指定。'
    fi
    if validate_exec_args "$args"; then
      EXEC_ARGS="$args"
      return
    fi
  done
}

# ---------- 原子写文件（先写临时文件再 mv）----------
write_atomic() {
  local dest="$1"; shift
  local tmp="${dest}.tmp.$$"
  if ! printf '%s' "$*" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$dest"
}

# ---------- GitHub 可达性 / 镜像分流 ----------
# 判断给定 URL 是否在超时内可达
probe_url() {
  local url="$1"
  curl -fsSL --connect-timeout "$PROBE_CONNECT_TIMEOUT" --max-time "$PROBE_MAX_TIME" \
       -o /dev/null -I "$url" 2>/dev/null
}

# 获取最新版本号；GitHub API 不通时依次走镜像站。成功置 VERSION 并返回 0。
fetch_latest_version() {
  local resp proxy
  resp="$(curl -fsSL --connect-timeout "$PROBE_CONNECT_TIMEOUT" --max-time 30 "$GITHUB_API" 2>/dev/null || true)"
  VERSION="$(printf '%s\n' "$resp" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '[:space:]')"
  if [ -n "$VERSION" ]; then
    info "最新版本: ${VERSION}"
    return 0
  fi

  if $NO_GH_PROXY; then return 1; fi

  warn '无法通过 GitHub API 获取版本号，尝试镜像站...'
  for proxy in "${GH_PROXY_LIST[@]}"; do
    resp="$(curl -fsSL --connect-timeout "$PROBE_CONNECT_TIMEOUT" --max-time 30 "${proxy}${GITHUB_API}" 2>/dev/null || true)"
    VERSION="$(printf '%s\n' "$resp" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '[:space:]')"
    if [ -n "$VERSION" ]; then
      info "通过镜像 ${proxy} 获取到版本: ${VERSION}"
      return 0
    fi
  done
  return 1
}

# 根据策略解析出实际下载 URL；成功置 DOWNLOAD_URL 并返回 0
resolve_download_url() {
  local asset="easytier-linux-${ARCH}-${VERSION}.zip"
  local direct="${GITHUB_DOWNLOAD_BASE}/${asset}"

  # 1) 强制直连
  if $NO_GH_PROXY; then
    DOWNLOAD_URL="$direct"
    info '已指定 --no-gh-proxy，强制直连 GitHub。'
    return 0
  fi

  # 2) 强制指定镜像
  if [ -n "$GH_PROXY_OVERRIDE" ]; then
    DOWNLOAD_URL="${GH_PROXY_OVERRIDE}${direct}"
    info "已指定镜像站: ${GH_PROXY_OVERRIDE}"
    return 0
  fi

  # 3) 自动模式：只探测下载主机 github.com（下载最终经其 302 跳转到
  #    objects.githubusercontent.com，故以 github.com 的可达性为准）
  info '正在探测 GitHub 连通性...'
  if probe_url 'https://github.com'; then
    DOWNLOAD_URL="$direct"
    info 'GitHub 可达，使用直连下载。'
    return 0
  fi
  warn 'GitHub 不可达，尝试使用镜像站...'

  # 4) 依次尝试镜像站
  local proxy
  for proxy in "${GH_PROXY_LIST[@]}"; do
    local cand="${proxy}${direct}"
    info "  探测镜像: ${proxy}"
    if probe_url "$cand"; then
      DOWNLOAD_URL="$cand"
      info "镜像可用: ${proxy}"
      return 0
    fi
    warn "  镜像不可用: ${proxy}"
  done

  err '所有下载源均不可达。请检查网络，或使用 --gh-proxy 指定可用镜像。'
  return 1
}

# ---------- 下载并暂存（不触碰安装目录）----------
# 成功后：$STAGE_BIN_DIR 指向含 easytier-core 的目录。
download_to_stage() {
  local tmp_zip="${STAGE_DIR}/easytier.zip"
  local curl_bar=''
  curl --help 2>/dev/null | grep -q -- '--progress-bar' && curl_bar='--progress-bar'

  info "下载到暂存目录: ${STAGE_DIR}"
  if ! curl -fSL $curl_bar -o "$tmp_zip" "$DOWNLOAD_URL"; then
    err '下载失败，请检查网络或更换镜像（--gh-proxy URL）。'
    return 1
  fi

  info '解压中...'
  if ! unzip -o "$tmp_zip" -d "$STAGE_DIR/" >/dev/null; then
    err '解压失败，下载包可能已损坏。'
    return 1
  fi
  rm -f "$tmp_zip"

  # 定位内层 easytier-linux-${ARCH}/ 子目录
  local inner="${STAGE_DIR}/easytier-linux-${ARCH}"
  if [ -d "$inner" ]; then
    STAGE_BIN_DIR="$inner"
  else
    STAGE_BIN_DIR="$STAGE_DIR"
  fi

  if [ ! -f "${STAGE_BIN_DIR}/easytier-core" ]; then
    err "下载包内未找到 easytier-core（架构 ${ARCH} 可能不匹配）。"
    return 1
  fi
  chmod +x "${STAGE_BIN_DIR}/easytier-core"
  [ -f "${STAGE_BIN_DIR}/easytier-cli" ] && chmod +x "${STAGE_BIN_DIR}/easytier-cli"
  return 0
}

# ---------- 验证服务确实起来了 ----------
verify_service_running() {
  local i st
  # Type=simple 下 systemctl restart 立即返回，不代表进程稳定；轮询 is-active
  for ((i = 0; i < 10; i++)); do
    st="$(systemctl is-active easytier 2>/dev/null || true)"
    if [ "$st" = 'active' ]; then
      info '✓ 服务已启动 (active)'
      return 0
    fi
    sleep 1
  done
  st="$(systemctl is-active easytier 2>/dev/null || true)"
  if [ "$st" = 'active' ]; then
    info '✓ 服务已启动 (active)'
    return 0
  fi
  err "⚠ 服务未进入 active 状态（当前: ${st}）。可能配置服务器连接失败或启动参数有误。"
  err '  最近日志:'
  journalctl -u easytier -n 20 --no-pager 1>&2 || true
  return 1
}

# ---------- 安装 ----------
install() {
  resolve_exec_args
  info "启动参数: easytier-core ${EXEC_ARGS}"

  # 创建暂存目录（EXIT trap 兜底清理）
  STAGE_DIR="$(mktemp -d /tmp/easytier_stage.XXXXXX)"

  # 1) 获取版本 + 解析下载源
  fetch_latest_version || die '所有源均无法获取最新版本号。请检查网络，或使用 --gh-proxy 指定可用镜像。'
  resolve_download_url || die '无法确定可用的下载源，已退出。'
  info "下载地址: ${DOWNLOAD_URL}"

  # 2) 下载到暂存目录（此阶段被中断不会污染安装目录）
  download_to_stage || die '下载/解压失败，安装未改动（既有安装目录与服务未被触碰）。'

  # 3) 交换：把暂存内容移入安装目录（单文件 rename，原子替换）
  mkdir -p "$INSTALL_PATH"
  # 清理可能的旧子目录残留（来自历史版本或官方 install.sh 残留）
  rm -rf "${INSTALL_PATH}/easytier-linux-${ARCH}"
  info "安装到 ${INSTALL_PATH} ..."
  mv -f "${STAGE_BIN_DIR}"/* "$INSTALL_PATH/" 2>/dev/null || true
  chmod +x "${INSTALL_PATH}/easytier-core" 2>/dev/null || true
  [ -f "${INSTALL_PATH}/easytier-cli" ] && chmod +x "${INSTALL_PATH}/easytier-cli"

  local core_bin="${INSTALL_PATH}/easytier-core"
  local cli_bin="${INSTALL_PATH}/easytier-cli"
  [ -f "$core_bin" ] || die '安装后仍未找到 easytier-core，安装失败。'

  # 4) 持久化启动参数（原子写，便于后续升级/复用）
  write_atomic "${INSTALL_PATH}/easytier.args" \
    "${core_bin} ${EXEC_ARGS}"$'\n' \
    || warn 'easytier.args 写入失败（不影响运行）。'

  # 5) 原子写入 systemd 单元
  local unit='/etc/systemd/system/easytier.service'
  local unit_tmp="${unit}.tmp.$$"
  cat >"$unit_tmp" <<UNIT
[Unit]
Description=EasyTier Service
Wants=network.target
After=network.target network.service

[Service]
Type=simple
WorkingDirectory=${INSTALL_PATH}
ExecStart=${core_bin} ${EXEC_ARGS}
Restart=always
RestartSec=1s

[Install]
WantedBy=multi-user.target
UNIT
  mv -f "$unit_tmp" "$unit"

  # 6) 与官方 install.sh 模板单元共存处理：停用其所有实例，避免双开抢端口
  systemctl stop 'easytier@*' >/dev/null 2>&1 || true
  systemctl disable 'easytier@*' >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/easytier.service.bak

  # 7) 启用并启动
  systemctl daemon-reload
  systemctl enable easytier >/dev/null 2>&1 || warn 'systemctl enable 失败，请手动检查单元文件。'
  systemctl restart easytier || warn 'systemctl restart 失败。'

  # 8) 软链到 /usr/sbin
  ln -sf "$core_bin" /usr/sbin/easytier-core
  [ -f "$cli_bin" ] && ln -sf "$cli_bin" /usr/sbin/easytier-cli

  # 9) 释放暂存目录（不必等 EXIT trap）
  rm -rf "$STAGE_DIR"; STAGE_DIR=''

  # 10) 验证 & 汇报（诚实反映服务状态）
  echo
  info '✓ 文件安装完成'
  echo -e "  安装路径: ${GREEN}${INSTALL_PATH}${RES}"
  echo -e "  启动参数: ${GREEN}easytier-core ${EXEC_ARGS}${RES}"
  echo

  if verify_service_running; then
    echo
    echo -e "  查看状态: ${GREEN}systemctl status easytier${RES}"
    echo -e "  重启:     ${GREEN}systemctl restart easytier${RES}"
    echo -e "  停止:     ${GREEN}systemctl stop easytier${RES}"
    echo -e "  查看日志: ${GREEN}journalctl -u easytier -f${RES}"
    echo
    info '✓ EasyTier 安装并启动成功！'
  else
    echo
    err '⚠ 安装完成但服务未正常运行。请用 journalctl -u easytier 排查。'
    exit 1
  fi
}

# ---------- 卸载 ----------
uninstall() {
  info '正在卸载 EasyTier ...'
  if systemctl list-unit-files 2>/dev/null | grep -q 'easytier'; then
    systemctl disable --now easytier >/dev/null 2>&1 || true
    systemctl stop 'easytier@*' >/dev/null 2>&1 || true
    systemctl disable 'easytier@*' >/dev/null 2>&1 || true
  fi

  rm -f /etc/systemd/system/easytier.service
  rm -f /etc/systemd/system/easytier@.service
  systemctl daemon-reload

  rm -rf "$INSTALL_PATH"
  rm -f /usr/sbin/easytier-core /usr/sbin/easytier-cli
  # 兼容历史路径
  rm -f /usr/bin/easytier-core /usr/bin/easytier-cli

  info '✓ EasyTier 已卸载。'
}

# ---------- 入口 ----------
case "$COMMAND" in
  install)   install ;;
  uninstall) uninstall ;;
  *)
    err "未知命令: ${COMMAND}"
    HELP
    exit 1 ;;
esac
