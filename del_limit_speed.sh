#!/bin/bash



read -p "请输入虚拟机的VMID（留空以选择所有虚拟机）:" VMID

remove_hook() {
    local VMID=$1
    CONFIG_FILE="/etc/pve/qemu-server/${VMID}.conf"

    # 检查配置文件是否存在
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Configuration file for VMID ${VMID} does not exist."
        exit 1
    fi

    # 创建备份
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # 删除包含 'hookscript' 的行
    sed -i '/hookscript/d' "$CONFIG_FILE"

    echo "Hookscript entry removed from VMID ${VMID}."
}

# 应用带宽限制的函数
del_tc_rules() {
    local vmid=$1
    local rate=$2
    local DEV="tap${vmid}i0"

	# 应用带宽限制
	# 删除已存在的HTB队列规则（如果存在）
	echo "删除 $DEV 上的现有HTB队列规则..."
	tc qdisc del dev $DEV root 2>/dev/null || echo "HTB队列规则不存在，继续..."

	# 删除已存在的ingress队列规则（如果存在）
	echo "删除 $DEV 上的现有ingress队列规则..."
	tc qdisc del dev $DEV ingress 2>/dev/null || echo "ingress队列规则不存在，继续..."

}

# 设置钩子脚本并立即应用带宽限制
if [ -z "$VMID" ]; then
    # 为所有运行的虚拟机设置并应用带宽限制
    for vm in $(qm list | awk '{print $1}' | grep -oP '\d+'); do
        VM_STATUS=$(qm status $vm | awk '{print $2}')
        if [ "$VM_STATUS" = "running" ]; then
            del_tc_rules $vm
        else
            echo "虚拟机 $vm 未开机"
        fi
        echo "虚拟机 $VMID 删除钩子文件"
        remove_hook $vm
    done
else
    # 检查指定虚拟机是否开机
    VM_STATUS=$(qm status $VMID | awk '{print $2}')
    if [ "$VM_STATUS" = "running" ]; then
        del_tc_rules $VMID
    else
        echo "虚拟机 $VMID 未开机"
    fi
    echo "虚拟机 $VMID 删除钩子文件"
    remove_hook $VMID

fi

echo "带宽限制删除完成。"
