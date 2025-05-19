#!/bin/bash

# Author: Benboerba
# Date: 2025-05-17 08:11:43
# Description: 物理机宕机后根据机器名快速定位故障点

# 彩色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# uplink信息获取与后续交换机端口状态查询
uplink_info_get() {
    read -p $'\e[32m请输入要查询的物理机HostName（多个用逗号分隔）:\e[0m' HOSTNAMES

    IFS=',' read -ra HOST_ARR <<< "$HOSTNAMES"

    for HOST in "${HOST_ARR[@]}"; do
        HOST=$(echo "$HOST" | xargs)
        echo -e "${GREEN}${HOST} 的 uplink 信息：${NC}"
        UPLINK_INFO=$(mysql -h 127.0.0.1 -D tianji -sN -e "select uplink_info from machine where machine='$HOST'")
        IFS=';' read -ra UPLINKS <<< "$UPLINK_INFO"
        for idx in "${!UPLINKS[@]}"; do
            UPLINK="${UPLINKS[$idx]}"
            if [[ -n "$UPLINK" ]]; then
                echo "uplink_port_$((idx+1)):"
                # 解析uplink字段
                DSW_INFO=$(echo "$UPLINK" | awk -F"|" '{print $1}')
                ASW_NAME=$(echo "$UPLINK" | awk -F"|" '{print $3}')
                SWITCH_IP=$(echo "$UPLINK" | awk -F"|" '{print $4}')
                ASW_PORT=$(echo "$UPLINK" | awk -F"|" '{print $7}')
                # 获取交换机型号和版本
                SYS_DESCR=$(snmpget -v2c -c public "$SWITCH_IP" SNMPv2-MIB::sysDescr.0 2>/dev/null | awk -F'STRING: ' '{print $2}')
                echo "交换机(${SWITCH_IP})信息: $SYS_DESCR"
                echo "$DSW_INFO"
                echo "ASW信息:${SWITCH_IP}:${ASW_PORT}"
                # 根据交换机型号进行后续查询（举例：仅对H3C S6800-4C执行snmp_check_port）
                if [[ "$SYS_DESCR" =~ "S6800-4C" ]]; then
                    snmp_check_port "$SWITCH_IP" "$ASW_PORT"
                fi
            fi
        done
        echo
    done
}

# H3C S6800-4C端口状态查询
snmp_check_port() {
    local SWITCH_IP="$1"
    local PORT_NAME="$2"

    # 获取 ifIndex
    IFINDEX=$(snmpwalk -v2c -c public "$SWITCH_IP" IF-MIB::ifDescr 2>/dev/null \
        | grep -w "STRING: $PORT_NAME" \
        | awk -F'[. ]+' '{print $(NF-3)}' | head -n1)

    if [[ -z "$IFINDEX" ]]; then
        echo -e "${RED}未找到端口 $PORT_NAME 的 ifIndex，无法查询！${NC}"
        return
    fi

    # 查询端口up/down状态
    STATUS_RAW=$(snmpget -v2c -c public "$SWITCH_IP" IF-MIB::ifOperStatus."$IFINDEX" 2>/dev/null | awk '{print $NF}')
    STATUS=$(echo "$STATUS_RAW" | grep -oP '\(\K[0-9]+')
    if [[ "$STATUS" == "1" ]]; then
        STATUS_MSG="${GREEN}UP${NC}"
    else
        STATUS_MSG="${RED}DOWN${NC}"
    fi

    # 查询端口当前发光功率（RX，OID需根据设备型号调整）
    RX_POWER=$(snmpget -v2c -c public "$SWITCH_IP" 1.3.6.1.4.1.25506.2.70.1.1.1.1.9."$IFINDEX" 2>/dev/null | awk '{print $NF}')
    [[ -z "$RX_POWER" ]] && RX_POWER="N/A"
    if [[ "$RX_POWER" != "N/A" && "$RX_POWER" =~ ^-?[0-9]+$ ]]; then
        RX_POWER_DBM=$(awk "BEGIN{printf \"%.2f\", $RX_POWER/100}")
        RX_RANGE="正常范围约 -8.00 ~ 0.00 dBm"
        RX_POWER_MSG="${RX_POWER_DBM} dBm  （$RX_RANGE）"
    else
        RX_POWER_MSG="N/A"
    fi

    # 查询双工模式
    DUPLEX=$(snmpget -v2c -c public "$SWITCH_IP" 1.3.6.1.4.1.25506.8.35.5.1.4.1.3."$IFINDEX" 2>/dev/null | awk '{print $NF}')
    case "$DUPLEX" in
        1) DUPLEX_MSG="fullDuplex";;
        2) DUPLEX_MSG="halfDuplex";;
        3) DUPLEX_MSG="auto";;
        *) DUPLEX_MSG="unknown";;
    esac

    echo -e "端口: $PORT_NAME (ifIndex: $IFINDEX) 状态: $STATUS_MSG 光功率: $RX_POWER_MSG 双工: $DUPLEX_MSG"
}

# 主程序入口
uplink_info_get

# 后续待验证H3C S6800-4C实际查询结果已启其他型号交换机的OID