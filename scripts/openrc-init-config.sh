#!/bin/bash
# OpenRC 初始化配置脚本
# 为 Droidspaces OpenRC 环境配置基础服务和兼容性补丁

set -e

USERNAME="${1:-Gold}"

echo "--> [开启] 配置 OpenRC 初始化环境..."

# 创建必要的目录
mkdir -p /etc/openrc/conf.d
mkdir -p /var/run
mkdir -p /var/lib/openrc

# 1. 配置 rc.conf（OpenRC 主配置文件）
cat > /etc/rc.conf << 'EOF'
# OpenRC Configuration for Droidspaces
hostname="droidspaces-container"
clock="UTC"
clock_systohc="NO"

# 启用远程文件系统支持
rc_sys="container"

# 并行启动服务
rc_parallel="YES"

# 失败服务不阻止启动
rc_depend_strict="NO"

# 禁用不必要的 rc.local 和关闭脚本
rc_hotplug="NO"
EOF

# 2. 配置必要的 OpenRC 服务
echo "--> [步骤] 配置 OpenRC 基础服务..."

# dbus 服务脚本（消息总线）
cat > /etc/init.d/dbus << 'DBUS_EOF'
#!/sbin/openrc-run

description="DBus Service"
pidfile="/var/run/dbus/dbus.pid"

depend() {
    after localmount
    need udev
}

start() {
    ebegin "Starting DBus daemon"
    start-stop-daemon --start --quiet --pidfile "${pidfile}" \
        --exec /usr/bin/dbus-daemon -- --system
    eend $?
}

stop() {
    ebegin "Stopping DBus daemon"
    start-stop-daemon --stop --quiet --pidfile "${pidfile}"
    eend $?
}
DBUS_EOF
chmod +x /etc/init.d/dbus

# udev 服务脚本（设备管理）
cat > /etc/init.d/udev << 'UDEV_EOF'
#!/sbin/openrc-run

description="udev Device Manager"

depend() {
    after localmount
}

start() {
    ebegin "Starting udev daemon"
    /usr/bin/udevd --daemon
    eend $?
}

stop() {
    ebegin "Stopping udev daemon"
    udevadm control --exit
    eend $?
}
UDEV_EOF
chmod +x /etc/init.d/udev

# networking 服务脚本
cat > /etc/init.d/networking << 'NETWORKING_EOF'
#!/sbin/openrc-run

description="Configure network interfaces and bring up networking"

depend() {
    provide net
}

start() {
    ebegin "Starting networking"
    # 启用 DHCP
    if command -v dhclient &> /dev/null; then
        dhclient eth0 eth1 2>/dev/null || true
    fi
    eend 0
}

stop() {
    ebegin "Stopping networking"
    eend 0
}
NETWORKING_EOF
chmod +x /etc/init.d/networking

# sshd 服务脚本
cat > /etc/init.d/sshd << 'SSHD_EOF'
#!/sbin/openrc-run

description="OpenSSH Server"
pidfile="/var/run/sshd.pid"

depend() {
    after networking
}

start() {
    ebegin "Starting SSH Server"
    /usr/sbin/sshd -D &
    echo $! > "$pidfile"
    eend $?
}

stop() {
    ebegin "Stopping SSH Server"
    kill $(cat "$pidfile" 2>/dev/null) 2>/dev/null || true
    rm -f "$pidfile"
    eend 0
}
SSHD_EOF
chmod +x /etc/init.d/sshd

# 3. 启用核心服务
echo "--> [步骤] 启用必要的 OpenRC 服务..."
rc-service udev start 2>/dev/null || true
rc-service dbus start 2>/dev/null || true

# 4. 配置桌面会话启动脚本
mkdir -p /etc/openrc-desktop
cat > /etc/openrc-desktop/desktop-session.sh << 'DESKTOP_EOF'
#!/bin/bash
# OpenRC 桌面会话启动脚本

if [ -f /etc/droidspaces-desktop.conf ]; then
    source /etc/droidspaces-desktop.conf
fi

# 启动 elogind
/usr/libexec/elogind/elogind &

# 等待 elogind 初始化
sleep 2

# 根据配置启动桌面
case "$DESKTOP_SESSION" in
    kde-x11)
        export DISPLAY=:5
        exec startplasma-x11
        ;;
    kde-wayland)
        exec startplasma-wayland
        ;;
    kde-mobile)
        exec startplasmamobile
        ;;
    gnome)
        exec gnome-session --session=gnome
        ;;
    *)
        echo "No desktop session configured"
        exec /bin/bash
        ;;
esac
DESKTOP_EOF
chmod +x /etc/openrc-desktop/desktop-session.sh

# 5. 创建 OpenRC 桌面启动服务
cat > /etc/init.d/desktop-session << 'DESKTOP_SERVICE_EOF'
#!/sbin/openrc-run

description="Droidspaces Desktop Session"
pidfile="/var/run/desktop-session.pid"

depend() {
    need dbus udev elogind
}

start() {
    ebegin "Starting Desktop Session"
    start-stop-daemon --start --make-pidfile --pidfile "$pidfile" \
        --user 1000 \
        --exec /etc/openrc-desktop/desktop-session.sh
    eend $?
}

stop() {
    ebegin "Stopping Desktop Session"
    start-stop-daemon --stop --pidfile "$pidfile"
    eend $?
}
DESKTOP_SERVICE_EOF
chmod +x /etc/init.d/desktop-session

# 6. 配置默认启动级别
mkdir -p /etc/runlevels/default
ln -sf /etc/init.d/dbus /etc/runlevels/default/dbus 2>/dev/null || true
ln -sf /etc/init.d/udev /etc/runlevels/default/udev 2>/dev/null || true
ln -sf /etc/init.d/networking /etc/runlevels/default/networking 2>/dev/null || true
ln -sf /etc/init.d/sshd /etc/runlevels/default/sshd 2>/dev/null || true

# 7. elogind 配置
mkdir -p /etc/elogind/user-session
cat > /etc/elogind/user-session/session.conf << 'ELOGIND_EOF'
[General]
Session=openrc
Type=x11
EOF

# 8. 创建启动脚本
cat > /sbin/rc << 'RC_EOF'
#!/bin/bash
# 简单的 OpenRC 运行级别管理

RUNLEVEL="${1:-default}"
export OPENRC_RUNLEVEL="$RUNLEVEL"

# 启动 localmount 和 sysfs
rc-service localmount start 2>/dev/null || true
rc-service sysfs start 2>/dev/null || true

# 启动指定运行级别的所有服务
if [ -d "/etc/runlevels/$RUNLEVEL" ]; then
    for service in /etc/runlevels/$RUNLEVEL/*; do
        if [ -x "$service" ]; then
            basename "$service" | xargs rc-service start 2>/dev/null || true
        fi
    done
fi

# 如果指定了桌面自启动，启动桌面会话
if [ -f /etc/droidspaces-desktop.conf ] && grep -q "DESKTOP_AUTOSTART=true" /etc/droidspaces-desktop.conf; then
    rc-service desktop-session start
fi
RC_EOF
chmod +x /sbin/rc

# 9. 兼容性补丁
echo "--> [步骤] 应用 Android 容器兼容性补丁..."

# 配置 /etc/fstab
cat > /etc/fstab << 'FSTAB_EOF'
proc		/proc		proc		defaults	0 0
sysfs		/sys		sysfs		defaults	0 0
tmpfs		/dev/shm	tmpfs		defaults	0 0
tmpfs		/run		tmpfs		defaults	0 0
FSTAB_EOF

# 配置 cgroup 支持
mkdir -p /sys/fs/cgroup
mkdir -p /run/cgroup

# 日志轮转配置
mkdir -p /etc/logrotate.d
cat > /etc/logrotate.d/openrc << 'LOGROTATE_EOF'
/var/log/messages
/var/log/wtmp
/var/log/btmp
{
    maxsize 50M
    rotate 3
    daily
    missingok
    notifempty
    sharedscripts
}
LOGROTATE_EOF

# 用户权限配置
mkdir -p /etc/sudoers.d
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME
chmod 440 /etc/sudoers.d/$USERNAME

echo "--> [完成] OpenRC 初始化配置已完成"
