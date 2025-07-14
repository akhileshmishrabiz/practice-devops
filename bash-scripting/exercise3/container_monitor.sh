#!/bin/bash
# Container Performance Monitor - Track CPU, memory, latency & health

CONTAINER_NAME="${1:-my-app}"
CPU_THRESHOLD=80
MEM_THRESHOLD=85
LATENCY_THRESHOLD=500

alert() {
    echo "🚨 ALERT: $1 - $(date)"
}

check_container() {
    if ! docker ps --format "table {{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        alert "Container '$CONTAINER_NAME' is not running!"
        return 1
    fi
    return 0
}

get_metrics() {
    docker stats "$CONTAINER_NAME" --no-stream --format \
    "{{.CPUPerc}}|{{.MemPerc}}|{{.MemUsage}}" 2>/dev/null
}

check_health() {
    local status=$(docker inspect "$CONTAINER_NAME" --format='{{.State.Health.Status}}' 2>/dev/null)
    [[ "$status" == "healthy" ]] && echo "✅ Healthy" || echo "❌ Unhealthy ($status)"
}

test_latency() {
    local port="${2:-8080}"
    local response_time=$(curl -s -w "%{time_total}" -o /dev/null "http://localhost:$port/health" 2>/dev/null || echo "0")
    local ms=$(echo "$response_time * 1000" | bc 2>/dev/null || echo "0")
    echo "${ms%.*}"
}

monitor() {
    echo "🔍 Monitoring container: $CONTAINER_NAME"
    
    check_container || return 1
    
    local metrics=$(get_metrics)
    [[ -z "$metrics" ]] && { alert "Failed to get container metrics"; return 1; }
    
    IFS='|' read -r cpu_pct mem_pct mem_usage <<< "$metrics"
    
    cpu_val=$(echo "$cpu_pct" | tr -d '%')
    mem_val=$(echo "$mem_pct" | tr -d '%')
    health=$(check_health)
    latency=$(test_latency)
    
    echo "📊 CPU: $cpu_pct | MEM: $mem_pct ($mem_usage) | Health: $health | Latency: ${latency}ms"
    
    [[ "${cpu_val%.*}" -gt "$CPU_THRESHOLD" ]] && alert "High CPU usage: $cpu_pct"
    [[ "${mem_val%.*}" -gt "$MEM_THRESHOLD" ]] && alert "High memory usage: $mem_pct"
    [[ "$latency" -gt "$LATENCY_THRESHOLD" ]] && alert "High latency: ${latency}ms"
    [[ "$health" == *"Unhealthy"* ]] && alert "Container health check failed"
}

logs() {
    echo "📋 Recent logs from $CONTAINER_NAME:"
    docker logs --tail 10 "$CONTAINER_NAME" 2>/dev/null || echo "No logs available"
}

restart_container() {
    echo "🔄 Restarting $CONTAINER_NAME..."
    docker restart "$CONTAINER_NAME" && echo "✅ Restarted" || echo "❌ Failed to restart"
}

menu() {
    echo -e "\n🐳 Container Monitor: 1)Check 2)Logs 3)Restart 4)Continuous 5)Exit"
    read -p "? " c
    case $c in
        1) monitor; menu ;;
        2) logs; menu ;;
        3) restart_container; menu ;;
        4) echo "Monitoring every 30s (Ctrl+C to stop)"; 
           while true; do monitor; sleep 30; done ;;
        5) exit ;;
        *) menu ;;
    esac
}

case "$1" in
    check) monitor ;;
    logs) logs ;;
    restart) restart_container ;;
    monitor) while true; do monitor; sleep 30; done ;;
    *) [[ -z "$1" ]] && { echo "Usage: $0 <container_name> [command]"; exit 1; }
       menu ;;
esac