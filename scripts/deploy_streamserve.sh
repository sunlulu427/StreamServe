#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

abort() {
  log "ERROR: $*"
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    abort "必须以 root 身份运行此脚本（可使用 sudo）。"
  fi
}

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    abort "缺少命令 $1，请确认环境安装完整。"
  fi
}

PACKAGE_INDEX_READY=""
PKG_MANAGER=""
declare -a COMPOSE_BIN
COMPOSE_SUPPORTS_ENVFILE=0
UPDATE_REPO="${UPDATE_REPO:-0}"

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --update)
        UPDATE_REPO=1
        ;;
      --help|-h)
        cat <<'EOF'
用法: deploy_streamserve.sh [--update]

选项:
  --update    若目标目录存在仓库，执行 git fetch/pull 更新代码。
  --help      显示此帮助信息。
EOF
        exit 0
        ;;
      *)
        abort "未知参数: $1 (使用 --help 查看用法)"
        ;;
    esac
    shift
  done
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  else
    abort "未找到受支持的包管理器 (apt 或 yum)。"
  fi
}

package_update_once() {
  if [ -n "$PACKAGE_INDEX_READY" ]; then
    return
  fi
  case "$PKG_MANAGER" in
    apt)
      log "刷新 apt 软件源缓存"
      apt-get update -y
      ;;
    yum)
      log "刷新 yum 软件源缓存"
      yum makecache -y
      ;;
  esac
  PACKAGE_INDEX_READY=1
}

pkg_install() {
  local packages
  packages=("$@")
  [ ${#packages[@]} -gt 0 ] || return
  package_update_once
  log "安装软件包: ${packages[*]}"
  case "$PKG_MANAGER" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
      ;;
    yum)
      yum install -y "${packages[@]}"
      ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "已检测到 Docker ($(docker --version))，跳过安装"
    return
  fi

  case "$PKG_MANAGER" in
    apt)
      pkg_install ca-certificates curl gnupg lsb-release
      install -m 0755 -d /etc/apt/keyrings
      if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
      fi

      local codename
      codename="$(lsb_release -cs)"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "${codename}" stable" >/etc/apt/sources.list.d/docker.list
      PACKAGE_INDEX_READY=""
      pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    yum)
      pkg_install ca-certificates curl gnupg2 yum-utils
      if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        PACKAGE_INDEX_READY=""
      fi
      pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
  esac

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable docker
    systemctl start docker
  fi
}

install_support_tools() {
  case "$PKG_MANAGER" in
    apt)
      pkg_install git gettext-base
      ;;
    yum)
      pkg_install git gettext
      ;;
  esac
}

detect_repo_url() {
  local candidate
  if [ -n "${REPO_URL:-}" ]; then
    return
  fi

  if ! command -v git >/dev/null 2>&1; then
    return
  fi

  candidate="${SCRIPT_ROOT}/.git"
  if [ -d "$candidate" ]; then
    REPO_URL="$(git -C "$SCRIPT_ROOT" config --get remote.origin.url || true)"
  fi
}

sync_repository() {
  if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
  fi

  if [ -d "$TARGET_DIR/.git" ]; then
    if [ "$UPDATE_REPO" != "1" ]; then
      log "检测到仓库已存在，跳过更新 (使用 --update 或设置 UPDATE_REPO=1 以同步最新代码)"
      return
    fi
    log "更新已有仓库 $TARGET_DIR"
    git -C "$TARGET_DIR" fetch --all --prune
    git -C "$TARGET_DIR" checkout "$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH"
  else
    [ -n "${REPO_URL:-}" ] || abort "未找到仓库 URL，请通过环境变量 REPO_URL 指定。"
    log "克隆仓库 $REPO_URL 至 $TARGET_DIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  fi
}

ensure_env_file() {
  if [ -f "$ENV_FILE" ]; then
    log "使用环境文件 $ENV_FILE"
    return
  fi

  if [ -f "$TARGET_DIR/.env.example" ]; then
    log "未发现 $ENV_FILE，拷贝 .env.example 作为初始模板"
    cp "$TARGET_DIR/.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  else
    abort "缺少环境文件，且未找到 .env.example。"
  fi
}

load_env() {
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

require_env() {
  local name
  name="$1"
  if [ -z "${!name:-}" ]; then
    abort "环境变量 $name 未设置，请在 $ENV_FILE 中配置。"
  fi
}

render_template() {
  local tpl_file output_file
  tpl_file="$1"
  output_file="$2"
  if [ ! -f "$tpl_file" ]; then
    abort "模板文件不存在: $tpl_file"
  fi
  log "渲染模板 $tpl_file -> $output_file"
  envsubst <"$tpl_file" >"$output_file"
}

render_nginx_configs() {
  mkdir -p "$TARGET_DIR/nginx/conf.d"
  if [ -f "$TARGET_DIR/nginx/nginx.conf.tpl" ]; then
    render_template "$TARGET_DIR/nginx/nginx.conf.tpl" "$TARGET_DIR/nginx/nginx.conf"
  fi
  if [ -f "$TARGET_DIR/nginx/conf.d/rtmp.conf.tpl" ]; then
    render_template "$TARGET_DIR/nginx/conf.d/rtmp.conf.tpl" "$TARGET_DIR/nginx/conf.d/rtmp.conf"
  fi
}

render_rtmp_allowlist() {
  local allow_file entries entry trimmed
  allow_file="$TARGET_DIR/nginx/conf.d/rtmp-allow.conf"
  IFS=',' read -r -a entries <<<"$RTMP_ALLOWED_IPS"
  {
    printf "    # 由 deploy_streamserve.sh 自动生成，请勿手动修改\n"
    for entry in "${entries[@]}"; do
      trimmed="$(printf '%s' "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [ -n "$trimmed" ]; then
        printf "    allow publish %s;\n" "$trimmed"
      fi
    done
    printf "    deny publish all;\n"
  } >"$allow_file"
}

prepare_directories() {
  mkdir -p "$TARGET_DIR/assets/hls"
  mkdir -p "$TARGET_DIR/assets/stat"
}

docker_compose() {
  if [ "$COMPOSE_SUPPORTS_ENVFILE" -eq 1 ]; then
    (cd "$TARGET_DIR" && "${COMPOSE_BIN[@]}" --env-file "$ENV_FILE" "$@")
  else
    (cd "$TARGET_DIR" && "${COMPOSE_BIN[@]}" "$@")
  fi
}

deploy_stack() {
  log "启动 StreamServe 容器"
  docker_compose --env-file "$ENV_FILE" up -d --build streamserve
}

verify_runtime() {
  log "执行 nginx 配置校验"
  docker_compose exec -T streamserve nginx -t
  log "当前容器状态"
  docker_compose ps streamserve
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    log "配置 UFW 端口开放 (22, 80, 1935)"
    ufw allow 22/tcp >/dev/null 2>&1 || true
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 1935/tcp >/dev/null 2>&1 || true
  elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log "配置 firewalld 端口开放 (22, 80, 1935)"
    firewall-cmd --permanent --add-service=ssh || true
    firewall-cmd --permanent --add-service=http || true
    firewall-cmd --permanent --add-port=1935/tcp || true
    firewall-cmd --reload || true
  else
    log "未检测到受支持的防火墙工具，跳过端口配置"
  fi
}

main() {
  require_root

  SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  TARGET_DIR="${TARGET_DIR:-/opt/streamserve}"
  ENV_FILE="${ENV_FILE:-$TARGET_DIR/.env}"
  BRANCH="${BRANCH:-main}"

  parse_args "$@"
  detect_package_manager
  install_docker
  install_support_tools
  if [ ! -d "$TARGET_DIR/.git" ] || [ "$UPDATE_REPO" = "1" ]; then
    detect_repo_url
  fi
  ensure_command docker
  ensure_command envsubst
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN=(docker compose)
    COMPOSE_SUPPORTS_ENVFILE=1
  elif command -v docker-compose >/dev/null 2>&1; then
    log "检测到 docker compose 插件缺失，将回退使用 docker-compose 二进制"
    COMPOSE_BIN=(docker-compose)
    COMPOSE_SUPPORTS_ENVFILE=0
  else
    abort "未找到 docker compose 或 docker-compose，请检查 Docker 安装。"
  fi
  sync_repository
  ensure_env_file
  load_env

  require_env STREAMSERVE_DOMAIN
  require_env SSL_CERT_PATH
  require_env PUSH_KEY
  require_env RTMP_ALLOWED_IPS

  prepare_directories
  render_nginx_configs
  render_rtmp_allowlist
  configure_firewall
  deploy_stack
  verify_runtime

  log "部署完成。可使用 ${COMPOSE_BIN[*]} logs -f streamserve 查看运行日志。"
}

main "$@"
