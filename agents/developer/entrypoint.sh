#!/bin/bash
# entrypoint.sh — 启动 Gateway 并自动审批所有待配对设备

# 后台循环：每 3 秒检查并自动审批所有 pending 设备
auto_approve() {
  sleep 5  # 等待 gateway 启动
  while true; do
    # 获取所有 pending request ID 并逐一审批
    openclaw devices list 2>/dev/null \
      | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
      | while read -r rid; do
          openclaw devices approve "$rid" 2>/dev/null && \
            echo "[auto-approve] approved device $rid"
        done
    sleep 3
  done
}

auto_approve &

# 前台启动 gateway（PID 1，接收信号）
exec openclaw gateway run --port 18789 --bind lan --allow-unconfigured "$@"

