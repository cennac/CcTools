#!/bin/bash
############################  用户可调区域  ############################
IPS=(10.0.11.105 10.0.111.82 10.0.12.43)          # 要检测的 IP 列表
LOG="/var/log/ping_monitor.log"          # 普通日志
ALERT_LOG="/var/log/ping_alert.log"      # 只记录“状态变化”
PIDFILE="/var/run/ping_monitor.pid"
INTERVAL=5                              # 检测间隔（秒）
ALERT_EMAIL=""            # 留空则不发邮件
############################  用户可调结束  ############################

# 状态文件：记录每个 IP 上一次状态，/tmp 重启自动清
STATE_DIR="/tmp/ping_monitor_states"
mkdir -p "$STATE_DIR"

# 发告警函数
send_alert(){
    local ip=$1 new=$2
    local msg="$(date '+%F %T') - $ip 网络$new"
    echo "$msg" >> "$ALERT_LOG"
    [ -n "$ALERT_EMAIL" ] && echo "$msg" | mail -s "网络$new: $ip" "$ALERT_EMAIL"
}

# 单次检测
check_once(){
    for ip in "${IPS[@]}"; do
        statefile="$STATE_DIR/$ip"
        last_state=$(cat "$statefile" 2>/dev/null || echo "unknown")

        if ping -c1 -W2 "$ip" >/dev/null 2>&1; then
            new_state="正常"
        else
            new_state="故障"
        fi

        # 写全量日志（可选注释掉）
        echo "$(date '+%F %T') - $ip - $new_state" >> "$LOG"

        # 状态变化才写 alert 并发邮件
        if [ "$last_state" != "$new_state" ]; then
            send_alert "$ip" "$new_state"
            echo "$new_state" > "$statefile"
        fi
    done
}

# 后台主循环
daemon(){
    while :; do
        check_once
        sleep "$INTERVAL"
    done
}

# 启动
do_start(){
    [ -s "$PIDFILE" ] && echo "已在运行 PID:$(cat $PIDFILE)" && exit 0
    echo "启动 ping_monitor …"
    # ===== 重置状态文件 =====
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR"
    # ======================
    nohup bash -c 'exec "$0" daemon' "$0" >>"$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    echo "已启动 PID:$(cat $PIDFILE)"
}

# 停止
do_stop(){
    [ -s "$PIDFILE" ] || { echo "未运行"; exit 0; }
    kill "$(cat "$PIDFILE")" && rm -f "$PIDFILE"
    echo "已停止"
}

# 状态
do_status(){
    if [ -s "$PIDFILE" ]; then
        ps -p "$(cat "$PIDFILE")" >/dev/null && \
            echo "运行中 PID:$(cat "$PIDFILE")" || \
            { echo "PID 文件存在但进程已死"; rm -f "$PIDFILE"; }
    else
        echo "未运行"
    fi
}

case "${1:-}" in
    start)   do_start ;;
    stop)    do_stop  ;;
    status)  do_status;;
    restart) do_stop; sleep 1; do_start ;;  # <-- 新增
    daemon)  daemon   ;;   # 仅供内部 nohup 调用
    *)       echo "用法: $0 {start|stop|restart|status}"; exit 1 ;;
esac