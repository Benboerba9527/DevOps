#!/bin/bash

# Author: Benboerba
# Date: 2025-05-28
# Description: 物理机宕机后根据机器名快速定位故障点，带菜单和日志保存

# 彩色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 灾备和信创OPS1
zb_ops1="10.9.13.65"
xc_ops1="10.3.13.65"

# 最大并发数
MAX_JOBS=5

# 日志文件
LOG_FILE="$(dirname "$0")/machine_error_$(date +%Y%m%d%H%M).log"

# 错误捕捉
trap 'echo -e "${RED}脚本执行出错，已退出${NC}"; exit 1' ERR
set -e

# 单主机分析函数
analyze_single_host() {
    local HOST="$1"
    {
        echo "========== $(date '+%F %T') $HOST 故障信息 =========="
        if [[ "$HOST" =~ am118|am186 ]]; then
            ssh "$HOST" bash <<'EOF'
                YELLOW='\033[0;33m'
                RED='\033[0;31m'
                NC='\033[0m'
                echo -e "${YELLOW}$(hostname)的故障点如下:${NC}"
                echo -e "${YELLOW}dmesg信息:${NC}"
                dmesg | grep -i "error\|critical" || echo -e "${RED}没有找到相关错误信息${NC}"
                echo -e "${YELLOW}ipmitool sel list信息:${NC}"
                ipmitool sel list | grep -iE "error|critical" || echo -e "${RED}没有找到相关错误信息${NC}"
                echo -e "${YELLOW}/var/log/messages信息(最近5条):${NC}"
                if [ -f /var/log/messages ]; then
                    grep -iE "error|critical" /var/log/messages | tail -n 5 || echo -e "${RED}没有找到相关错误信息${NC}"
                else
                    echo -e "${RED}/var/log/messages文件不存在${NC}"
                fi
EOF
        elif [[ "$HOST" =~ am301 ]]; then
            ssh "$xc_ops1" "ssh $HOST bash -s" <<'EOF'
                YELLOW='\033[0;33m'
                RED='\033[0;31m'
                NC='\033[0m'
                echo -e "${YELLOW}$(hostname)的故障点如下:${NC}"
                echo -e "${YELLOW}dmesg信息:${NC}"
                dmesg | grep -i "error\|critical" || echo -e "${RED}没有找到相关错误信息${NC}"
                echo -e "${YELLOW}ipmitool sel list信息:${NC}"
                ipmitool sel list | grep -iE "error|critical" || echo -e "${RED}没有找到相关错误信息${NC}"
                echo -e "${YELLOW}/var/log/messages信息(最近5条):${NC}"
                if [ -f /var/log/messages ]; then
                    grep -iE "error|critical" /var/log/messages | tail -n 5 || echo -e "${RED}没有找到相关错误信息${NC}"
                else
                    echo -e "${RED}/var/log/messages文件不存在${NC}"
                fi
EOF
        else
            echo -e "${RED}无法识别主机 $HOST 的机房类型，跳过...${NC}"
        fi
        echo
    } >> "$LOG_FILE" 2>&1
}

# 多主机并发分析
analyze_multi_hosts() {
    read -p $'\e[32m请输入要查询的物理机HostName（多个用逗号分隔）:\e[0m' HOSTNAMES
    if [[ -z "$HOSTNAMES" ]]; then
        echo -e "${RED}未输入主机名，脚本退出${NC}"
        exit 1
    fi

    IFS=',' read -ra HOST_ARR <<< "$HOSTNAMES"
    job_count=0
    pids=()

    for HOST in "${HOST_ARR[@]}"; do
        HOST=$(echo "$HOST" | xargs)
        if [[ -z "$HOST" ]]; then
            continue
        fi
        (
            analyze_single_host "$HOST"
        ) &
        pids+=($!)
        ((job_count++))
        if (( job_count % MAX_JOBS == 0 )); then
            wait
        fi
    done
    wait
}

# 物理机上联交换机故障信息
uplink_info_get() {
    read -p $'\e[32m请输入要查询的物理机HostName（多个用逗号分隔）:\e[0m' HOSTNAMES

    IFS=',' read -ra HOST_ARR <<< "$HOSTNAMES"

    for HOST in "${HOST_ARR[@]}"; do
        HOST=$(echo "$HOST" | xargs)
        {
            echo "========== $(date '+%F %T') $HOST 上联交换机信息 =========="
            echo -e "${GREEN}${HOST} 的 uplink 信息：${NC}"
            UPLINK_INFO=$(mysql -h 127.0.0.1 -D tianji -sN -e "select uplink_info from machine where machine='$HOST'")
            IFS=';' read -ra UPLINKS <<< "$UPLINK_INFO"
            for idx in "${!UPLINKS[@]}"; do
                UPLINK="${UPLINKS[$idx]}"
                if [[ -n "$UPLINK" ]]; then
                    echo "uplink_port_$((idx+1)):"
                    DSW_INFO=$(echo "$UPLINK" | awk -F"|" '{print $1}')
                    ASW_NAME=$(echo "$UPLINK" | awk -F"|" '{print $3}')
                    SWITCH_IP=$(echo "$UPLINK" | awk -F"|" '{print $4}')
                    ASW_PORT=$(echo "$UPLINK" | awk -F"|" '{print $7}')
                    SYS_DESCR=$(snmpget -v2c -c public "$SWITCH_IP" SNMPv2-MIB::sysDescr.0 2>/dev/null | awk -F'STRING: ' '{print $2}')
                    echo "交换机(${SWITCH_IP})信息: $SYS_DESCR"
                    echo "$DSW_INFO"
                    echo "ASW信息:${SWITCH_IP}:${ASW_PORT}"
                    if [[ "$SYS_DESCR" =~ "S6800-4C" ]]; then
                        snmp_check_port "$SWITCH_IP" "$ASW_PORT"
                    fi
                fi
            done
            echo
        } >> "$LOG_FILE" 2>&1
    done
}

# H3C S6800-4C端口状态查询
snmp_check_port() {
    local SWITCH_IP="$1"
    local PORT_NAME="$2"

    IFINDEX=$(snmpwalk -v2c -c public "$SWITCH_IP" IF-MIB::ifDescr 2>/dev/null \
        | grep -w "STRING: $PORT_NAME" \
        | awk -F'[. ]+' '{print $(NF-3)}' | head -n1)

    if [[ -z "$IFINDEX" ]]; then
        echo -e "${RED}未找到端口 $PORT_NAME 的 ifIndex，无法查询！${NC}"
        return
    fi

    STATUS_RAW=$(snmpget -v2c -c public "$SWITCH_IP" IF-MIB::ifOperStatus."$IFINDEX" 2>/dev/null | awk '{print $NF}')
    STATUS=$(echo "$STATUS_RAW" | grep -oP '\(\K[0-9]+')
    if [[ "$STATUS" == "1" ]]; then
        STATUS_MSG="${GREEN}UP${NC}"
    else
        STATUS_MSG="${RED}DOWN${NC}"
    fi

# 光模块发生紧急故障时产生告警OID：1.3.6.1.4.1.25506.2.6.4.0.49	

    RX_POWER=$(snmpget -v2c -c public "$SWITCH_IP" 1.3.6.1.4.1.25506.2.70.1.1.1.1.9."$IFINDEX" 2>/dev/null | awk '{print $NF}')
    [[ -z "$RX_POWER" ]] && RX_POWER="N/A"
    if [[ "$RX_POWER" != "N/A" && "$RX_POWER" =~ ^-?[0-9]+$ ]]; then
        RX_POWER_DBM=$(awk "BEGIN{printf \"%.2f\", $RX_POWER/100}")
        RX_RANGE="正常范围约 -8.00 ~ 0.00 dBm"
        RX_POWER_MSG="${RX_POWER_DBM} dBm  （$RX_RANGE）"
    else
        RX_POWER_MSG="N/A"
    fi

    DUPLEX=$(snmpget -v2c -c public "$SWITCH_IP" 1.3.6.1.4.1.25506.8.35.5.1.4.1.3."$IFINDEX" 2>/dev/null | awk '{print $NF}')
    case "$DUPLEX" in
        1) DUPLEX_MSG="fullDuplex";;
        2) DUPLEX_MSG="halfDuplex";;
        3) DUPLEX_MSG="auto";;
        *) DUPLEX_MSG="unknown";;
    esac

    echo -e "端口: $PORT_NAME (ifIndex: $IFINDEX) 状态: $STATUS_MSG 光功率: $RX_POWER_MSG 双工: $DUPLEX_MSG"
}

# 查询物理机所属产品日志（示例实现，可根据实际需求完善）
query_product_log() {
    read -p $'\e[32m请输入要查询的物理机HostName:\e[0m' HOST
    if [[ -z "$HOST" ]]; then
        echo -e "${RED}未输入主机名，脚本退出${NC}"
        exit 1
    fi
    {
        echo "========== $(date '+%F %T') $HOST 所属产品日志 =========="
        # 假设日志路径为 /var/log/product.log
        ssh "$HOST" "tail -n 100 /var/log/product.log 2>/dev/null || echo '未找到产品日志文件'" 
        echo
        } >> "$LOG_FILE" 2>&1
}

# 菜单
show_menu() {
    echo -e "${BLUE}========== 物理机故障诊断工具 ==========${NC}"
    echo -e "${YELLOW}1、查询单台物理机故障信息${NC}"
    echo -e "${YELLOW}2、查询多台物理机故障信息${NC}"
    echo -e "${YELLOW}3、查询物理机上联交换机故障信息${NC}"
    echo -e "${YELLOW}4、查询物理机所属产品日志${NC}"
    echo -e "${YELLOW}5、退出脚本${NC}"
}

# 主循环
while true; do
    show_menu
    read -p $'\e[32m请选择功能编号:\e[0m' CHOICE
    case "$CHOICE" in
        1)
            read -p $'\e[32m请输入要查询的物理机HostName:\e[0m' HOST
            if [[ -z "$HOST" ]]; then
                echo -e "${RED}未输入主机名，脚本退出${NC}"
                exit 1
            fi
            analyze_single_host "$HOST"
            ;;
        2)
            analyze_multi_hosts
            ;;
        3)
            uplink_info_get
            ;;
        4)
            query_product_log
            ;;
        5)
            echo -e "${GREEN}脚本已退出。日志保存在：$LOG_FILE${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新输入！${NC}"
            ;;
    esac
done
