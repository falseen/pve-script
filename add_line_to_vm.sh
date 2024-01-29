#!/bin/bash

#给所有的虚拟机加一个去除虚拟化的命令

# 获取所有虚拟机的ID列表
vm_ids=$(qm list | awk '!/VMID/ {print $1}')

# 遍历每个虚拟机ID
for id in $vm_ids
do
    # 检查虚拟机是否为模板
    is_template=$(qm config "$id" | grep "template" | awk '{print $2}')
    if [[ "$is_template" == "1" ]]; then
        echo "跳过模板虚拟机 $id"
        continue
    fi

    # 获取虚拟机的配置文件路径
    config_file="/etc/pve/qemu-server/${id}.conf"

    # 检查配置文件是否存在
    if [ -f "$config_file" ]; then
        # 在配置文件的末尾添加一行内容
        echo "args: -cpu 'host,-hypervisor,+kvm_pv_unhalt,+kvm_pv_eoi,hv_spinlocks=0x1fff,hv_vapic,hv_time,hv_reset,hv_vpindex,hv_runtime,hv_relaxed,kvm=off,hv_vendor_id=intel'" >> "$config_file"
        echo "在虚拟机 ${id} 的配置文件中添加了一行内容。"
    else
        echo "虚拟机 ${id} 的配置文件不存在。"
    fi
done