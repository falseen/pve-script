#!/bin/bash

# 定义常量
SNIPPETS_DIR="/var/lib/vz/snippets"
HOOK_SCRIPT_NAME="limit_pppoe_upload.pl"
HOOK_SCRIPT_PATH="$SNIPPETS_DIR/$HOOK_SCRIPT_NAME"
STORAGE_ID="local"
CONFIG_DIR="/etc/pve/qemu-server"

# 函数：设置带宽限制
set_bandwidth_limit() {
    local UPLOAD_RATE_KBIT="$1"
    local DOWNLOAD_RATE_KBIT="$2"
    local VM_FILTER="$3"
    local DEV_SUFFIX="$4"

    # 创建Perl钩子脚本
    cat > "$HOOK_SCRIPT_PATH" <<EOF
#!/usr/bin/perl

use strict;
use warnings;

my \$vmid = shift;
my \$phase = shift;

if (\$phase eq 'post-start') {
    print "\$vmid is starting, setting bandwidth limit.\n";
    my \$DEV = "tap\${vmid}${DEV_SUFFIX}";

    system("tc qdisc del dev \$DEV root 2>/dev/null");
    system("tc qdisc del dev \$DEV ingress 2>/dev/null");

    system("tc qdisc add dev \$DEV root handle 1: htb default 1 r2q 10 direct_qlen 1000");
    system("tc qdisc add dev \$DEV handle ffff: ingress");
    system("tc filter add dev \$DEV parent ffff: protocol all pref 50 basic police rate $UPLOAD_RATE_KBIT burst 1Mb mtu 64Kb action drop");
EOF
    if [[ ! -z "$DOWNLOAD_RATE_KBIT" ]]; then
        cat >> "$HOOK_SCRIPT_PATH" <<EOF
    system("tc class add dev \$DEV parent 1: classid 1:1 htb rate $DOWNLOAD_RATE_KBIT ceil $DOWNLOAD_RATE_KBIT burst 1Mb cburst 1595b");
EOF
    fi
    cat >> "$HOOK_SCRIPT_PATH" <<EOF
}
EOF
    chmod +x "$HOOK_SCRIPT_PATH"

    # 应用带宽限制的函数
    apply_tc_rules() {
        local vmid="$1"
        local DEV="tap${vmid}${DEV_SUFFIX}"

        tc qdisc del dev "$DEV" root 2>/dev/null
        tc qdisc del dev "$DEV" ingress 2>/dev/null

        tc qdisc add dev "$DEV" root handle 1: htb default 1 r2q 10 direct_qlen 1000
        tc qdisc add dev "$DEV" handle ffff: ingress
        tc filter add dev "$DEV" parent ffff: protocol all pref 50 basic police rate "$UPLOAD_RATE_KBIT" burst 1Mb mtu 64Kb action drop
        if [[ ! -z "$DOWNLOAD_RATE_KBIT" ]]; then
            tc class add dev "$DEV" parent 1: classid 1:1 htb rate "$DOWNLOAD_RATE_KBIT" ceil "$DOWNLOAD_RATE_KBIT" burst 1Mb cburst 1595b
        fi
    }

    # 查找匹配的虚拟机并设置钩子和应用规则
    for vm in $(qm list | awk "$VM_FILTER"); do
        VM_STATUS=$(qm status "$vm" | awk '{print $2}')
        echo "正在处理虚拟机 $vm (状态: $VM_STATUS)"
        if [ "$VM_STATUS" = "running" ]; then
            apply_tc_rules "$vm"
        else
            echo "虚拟机 $vm 未运行，将在下次启动时应用规则。"
        fi
        qm set "$vm" --hookscript "$STORAGE_ID:snippets/$HOOK_SCRIPT_NAME"
    done
}

# 函数：移除带宽限制和钩子
remove_bandwidth_limit() {
    local VM_FILTER="$1"

    remove_hook() {
        local VMID="$1"
        local CONFIG_FILE="$CONFIG_DIR/${VMID}.conf"

        if [ ! -f "$CONFIG_FILE" ]; then
            echo "虚拟机 ${VMID} 的配置文件不存在。"
            return 1
        fi

        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        sed -i '/hookscript/d' "$CONFIG_FILE"

        echo "已从虚拟机 ${VMID} 的配置中移除 hookscript 条目。"
        return 0
    }

    del_tc_rules() {
        local vmid="$1"
        local DEV="tap${vmid}i0"

        echo "正在删除 $DEV 上的 tc 规则..."
        tc qdisc del dev "$DEV" root 2>/dev/null
        tc qdisc del dev "$DEV" ingress 2>/dev/null
        echo "已删除 $DEV 上的 tc 规则。"
    }

    for vm in $(qm list | awk "$VM_FILTER"); do
        VM_STATUS=$(qm status "$vm" | awk '{print $2}')
        echo "正在处理虚拟机 $vm (状态: $VM_STATUS)"

        if [ "$VM_STATUS" = "running" ]; then
            del_tc_rules "$vm"
        else
            echo "虚拟机 $vm 未运行，无需删除 tc 规则。"
        fi

        if remove_hook "$vm"; then
            echo "成功移除虚拟机 $vm 的 hookscript。"
        else
            echo "移除虚拟机 $vm 的 hookscript 失败（可能配置文件不存在）。"
        fi
    done
}

# 主菜单
show_menu() {
    echo "请选择操作："
    echo "1. 设置带宽限制"
    echo "2. 移除带宽限制"
    echo "q. 退出"
}

# 主程序
while true; do
    show_menu

    read -p "请输入选项：" choice

    case $choice in
        1) # 设置带宽限制
            read -p "请输入上传带宽限制（例如 '10Mbit'）:" UPLOAD_RATE
            if [[ ! "$UPLOAD_RATE" =~ ^[0-9]+(Mbit)?$ ]]; then
                echo "无效的上传带宽格式。请使用例如 '10Mbit' 或 '10' 的格式。"
                continue
            fi
            UPLOAD_RATE_KBIT=$(( ${UPLOAD_RATE%%Mbit} * 1024 ))Kbit

            read -p "请输入下载带宽限制（例如 '100Mbit'，留空则不限制）:" DOWNLOAD_RATE
            if [[ ! -z "$DOWNLOAD_RATE" ]]; then
                if [[ ! "$DOWNLOAD_RATE" =~ ^[0-9]+(Mbit)?$ ]]; then
                    echo "无效的下载带宽格式。请使用例如 '100Mbit' 或 '100' 的格式。"
                    continue
                fi
                DOWNLOAD_RATE_KBIT=$(( ${DOWNLOAD_RATE%%Mbit} * 1024 ))Kbit
            fi

            read -p "请输入虚拟机前缀名称（例如 'test'，留空则匹配所有虚拟机）:" VM_PREFIX
            if [ -z "$VM_PREFIX" ]; then
                echo "未输入虚拟机前缀，将匹配所有虚拟机。"
                VM_FILTER='{print $1}'
            else
                VM_FILTER='$2 ~ /^'"$VM_PREFIX"'/ {print $1}'
            fi
            read -p "请选择网卡（1表示第一张网卡，2表示第二张网卡）:" NIC_CHOICE
            if [ "$NIC_CHOICE" = "1" ]; then
                DEV_SUFFIX="i0"
            elif [ "$NIC_CHOICE" = "2" ]; then
                DEV_SUFFIX="i1"
            else
                echo "无效的网卡选择。"
                continue
            fi
            set_bandwidth_limit "$UPLOAD_RATE_KBIT" "$DOWNLOAD_RATE_KBIT" "$VM_FILTER" "$DEV_SUFFIX"
            echo "带宽限制设置完成。"
            ;;
        2) # 移除带宽限制
            read -p "请输入虚拟机前缀名称（例如 'test'，留空则匹配所有虚拟机）:" VM_PREFIX
            if [ -z "$VM_PREFIX" ]; then
                echo "未输入虚拟机前缀，将匹配所有虚拟机。"
                VM_FILTER='{print $1}'
            else
                VM_FILTER='$2 ~ /^'"$VM_PREFIX"'/ {print $1}'
            fi
            remove_bandwidth_limit "$VM_FILTER"
            echo "带宽限制移除完成。"
            ;;
        q) # 退出
            echo "退出。"
            break
            ;;
        *) # 无效选项
            echo "无效选项，请重新选择。"
            ;;
    esac
done