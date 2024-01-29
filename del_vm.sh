#!/bin/bash

# 获取所有虚拟机的名称、vmid
vm_info=$(qm list | awk 'NR>1 {print $2 ":" $1}')

# 交互式输入基础名字
read -p "请输入要匹配的虚拟机基础名字（模糊匹配）: " base_name

# 进行模糊匹配
matched_vms=$(echo "$vm_info" | grep "$base_name")

# 如果没有匹配的虚拟机，退出脚本
if [ -z "$matched_vms" ]; then
    echo "没有找到匹配的虚拟机."
    exit 1
fi

# 过滤掉模板并打印匹配到的虚拟机列表
echo "匹配到的虚拟机列表:"
while IFS=":" read -r vm_name vmid; do
    conf_file="/etc/pve/qemu-server/$vmid.conf"
    if [ -f "$conf_file" ] && ! grep -qP '^template:\s*1' "$conf_file"; then
        echo "$vmid ($vm_name)"
    fi
done <<< "$matched_vms"

# 确认用户是否真的要删除所有匹配的虚拟机
read -p "确定要删除所有匹配的虚拟机吗？ (y/n): " confirm
if [ "$confirm" == "y" ]; then
    # 循环删除所有匹配的虚拟机
    for vm in $matched_vms; do
        IFS=":" read -r vm_name vmid <<< "$vm"

        # 停止虚拟机
        qm stop $vmid

        # 删除虚拟机
        qm destroy $vmid

        echo "虚拟机 $vmid ($vm_name) 已删除."
    done
else
    echo "已取消删除操作."
fi

