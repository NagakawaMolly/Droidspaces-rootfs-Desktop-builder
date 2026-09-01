#!/bin/bash
# OpenRC 服务管理工具
# 用于在容器运行时管理 OpenRC 服务

set -e

# 色彩定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 错误处理
error() {
    echo -e "${RED}[错误]${NC} $1" >&2
    exit 1
}

info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 权限检查
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "该脚本必须以 root 身份运行"
    fi
}

# 启动服务
start_service() {
    local service=$1
    if [ -f "/etc/init.d/$service" ]; then
        info "启动服务: $service"
        /etc/init.d/$service start || warn "启动失败或服务已运行: $service"
    else
        error "服务不存在: $service"
    fi
}

# 停止服务
stop_service() {
    local service=$1
    if [ -f "/etc/init.d/$service" ]; then
        info "停止服务: $service"
        /etc/init.d/$service stop || warn "停止失败或服务未运行: $service"
    else
        error "服务不存在: $service"
    fi
}

# 重启服务
restart_service() {
    local service=$1
    if [ -f "/etc/init.d/$service" ]; then
        info "重启服务: $service"
        /etc/init.d/$service restart || warn "重启失败: $service"
    else
        error "服务不存在: $service"
    fi
}

# 启用服务（加入启动级别）
enable_service() {
    local service=$1
    local runlevel=${2:-default}
    
    if [ -f "/etc/init.d/$service" ]; then
        mkdir -p "/etc/runlevels/$runlevel"
        ln -sf "/etc/init.d/$service" "/etc/runlevels/$runlevel/$service"
        info "已启用服务: $service (运行级别: $runlevel)"
    else
        error "服务不存在: $service"
    fi
}

# 禁用服务（从启动级别移除）
disable_service() {
    local service=$1
    local runlevel=${2:-default}
    
    rm -f "/etc/runlevels/$runlevel/$service"
    info "已禁用服务: $service (运行级别: $runlevel)"
}

# 查看服务状态
status_service() {
    local service=$1
    if [ -f "/etc/init.d/$service" ]; then
        /etc/init.d/$service status || true
    else
        error "服务不存在: $service"
    fi
}

# 列出所有服务
list_services() {
    local runlevel=${1:-default}
    
    if [ ! -d "/etc/runlevels/$runlevel" ]; then
        error "运行级别不存在: $runlevel"
    fi
    
    info "运行级别 '$runlevel' 的服务列表:"
    ls -1 "/etc/runlevels/$runlevel" 2>/dev/null || echo "  (无服务)"
}

# 初始化所有核心服务
init_core_services() {
    info "初始化核心 OpenRC 服务..."
    
    # 启动基础服务
    start_service localmount 2>/dev/null || true
    start_service sysfs 2>/dev/null || true
    start_service udev
    start_service dbus
    start_service networking
    
    info "核心服务初始化完成"
}

# 启动桌面环境
start_desktop() {
    info "启动桌面环境..."
    
    if [ ! -f /etc/droidspaces-desktop.conf ]; then
        error "桌面配置文件不存在: /etc/droidspaces-desktop.conf"
    fi
    
    # 确保必要的服务已运行
    start_service udev 2>/dev/null || true
    start_service dbus 2>/dev/null || true
    
    # 启动桌面会话
    start_service desktop-session
    
    info "桌面环境已启动，请检查日志确认状态"
}

# 显示帮助信息
show_help() {
    cat <<'EOF'
OpenRC 服务管理工具 - Droidspaces

用法: openrc-services.sh <命令> [参数]

命令:
  start <service>           启动指定服务
  stop <service>            停止指定服务
  restart <service>         重启指定服务
  status <service>          查看服务状态
  enable <service> [level]  启用服务（加入启动级别，默认: default）
  disable <service> [level] 禁用服务（从启动级别移除，默认: default）
  list [level]              列出指定启动级别的所有服务（默认: default）
  init                      初始化所有核心服务
  desktop                   启动桌面环境
  help                      显示此帮助信息

示例:
  openrc-services.sh start sshd
  openrc-services.sh enable dbus
  openrc-services.sh list default
  openrc-services.sh desktop
  openrc-services.sh init

EOF
}

# 主函数
main() {
    local cmd=$1
    
    case $cmd in
        start)
            check_root
            [ -z "$2" ] && error "缺少服务名参数"
            start_service "$2"
            ;;
        stop)
            check_root
            [ -z "$2" ] && error "缺少服务名参数"
            stop_service "$2"
            ;;
        restart)
            check_root
            [ -z "$2" ] && error "缺少服务名参数"
            restart_service "$2"
            ;;
        status)
            [ -z "$2" ] && error "缺少服务名参数"
            status_service "$2"
            ;;
        enable)
            check_root
            [ -z "$2" ] && error "缺少服务名参数"
            enable_service "$2" "$3"
            ;;
        disable)
            check_root
            [ -z "$2" ] && error "缺少服务名参数"
            disable_service "$2" "$3"
            ;;
        list)
            list_services "$2"
            ;;
        init)
            check_root
            init_core_services
            ;;
        desktop)
            check_root
            start_desktop
            ;;
        help|--help|-h|"")
            show_help
            ;;
        *)
            error "未知命令: $cmd (使用 'help' 查看帮助)"
            ;;
    esac
}

# 运行主函数
main "$@"
