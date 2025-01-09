#!/bin/bash
#pve虚拟机流量镜像


# 显示菜单
show_menu() {
    echo "请选择操作:"
    echo "1) 镜像流量"
    echo "2) 移除镜像"
    echo "3) 退出"
}

# 显示网卡列表并让用户选择
select_nic() {
    local prompt="$1"
    local nics=("$@")
    shift # 移除 prompt

    if [[ ${#nics[@]} -eq 0 ]]; then
        echo "没有找到可用的网卡。"
        return 1
    fi

    echo "$prompt"
    for i in "${!nics[@]}"; do
        echo "$((i+1))) ${nics[$i]}"
    done

    while true; do
        read -p "请输入网卡编号 (1-${#nics[@]}): " nic_choice
        if [[ "$nic_choice" =~ ^[0-9]+$ ]] && ((nic_choice >= 1 && nic_choice <= ${#nics[@]})); then
            REPLY="${nics[$nic_choice - 1]}"
            return 0
        else
            echo "无效选择，请重新输入。"
        fi
    done
}

# 获取网卡在宿主机上的接口名称(直接构造tap接口名)
get_host_iface_from_vm_nic() {
    local vm_id="$1"
    local vm_nic="$2"
    echo "tap${vm_id}i${vm_nic}"
}

# 获取 eno 开头的网络接口
get_vmbr_nics() {
    ip link show | awk '/^ *[0-9]+: eno/ {print $2}'
}


# 使用 tc 设置流量镜像 (镜像所有流量)
mirror_traffic() {
    local host_nic="$1"
    local vm_id="$2"
    local vm_nic="$3"
    local vm_iface=$(get_host_iface_from_vm_nic "$vm_id" "$vm_nic")

    if ! ip link show "$vm_iface" > /dev/null 2>&1; then
        echo "错误：虚拟机 '$vm_id' 的网卡 '$vm_nic' 对应的 tap 接口 '$vm_iface' 不存在。"
        return 1
    fi

    tc qdisc del dev "$host_nic" root &>/dev/null
    tc qdisc del dev "$host_nic" ingress &>/dev/null

    tc qdisc add dev "$host_nic" handle 1: root prio
    if [[ $? -ne 0 ]]; then
        echo "错误：添加 prio qdisc 失败"
        return 1
    fi

    tc filter add dev "$host_nic" parent 1: protocol all u32 match u8 0 0 action mirred egress mirror dev "$vm_iface"
    if [[ $? -ne 0 ]]; then
        echo "错误：添加 egress filter 失败"
        tc qdisc del dev "$host_nic" root &>/dev/null
        return 1
    fi

    tc qdisc add dev "$host_nic" handle ffff: ingress
    if [[ $? -ne 0 ]]; then
        echo "错误：添加 ingress qdisc 失败"
        tc qdisc del dev "$host_nic" root &>/dev/null
        return 1
    fi
    tc filter add dev "$host_nic" parent ffff: protocol all u32 match u8 0 0 action mirred egress mirror dev "$vm_iface"
    if [[ $? -ne 0 ]]; then
        echo "错误：添加 ingress filter 失败"
        tc qdisc del dev "$host_nic" root &>/dev/null
        tc qdisc del dev "$host_nic" ingress &>/dev/null
        return 1
    fi

    echo "开始双向镜像来自 '$host_nic' 的所有流量到虚拟机 '$vm_id' 的网卡 '$vm_nic' (宿主机接口: $vm_iface)。"
}

remove_mirror() {
    local host_nic="$1"

    tc qdisc del dev "$host_nic" root &>/dev/null
    tc qdisc del dev "$host_nic" ingress &>/dev/null

    echo "镜像已停止。"
}


main() {
    local selected_host_nic
    local selected_vm_id
    local selected_vm_nic
    local selected_vm_iface
    local vmbr_nics

    vmbr_nics=($(get_vmbr_nics))

    if [[ ${#vmbr_nics[@]} -eq 0 ]];then
        echo "没有找到vmbr开头的网卡"
        exit 1
    fi

    if ! select_nic "请选择宿主机网卡:" "${vmbr_nics[@]}"; then
        exit 1 # 如果选择网卡失败，则退出
    fi
    selected_host_nic="$REPLY"
    echo "选择的宿主机网卡是: $selected_host_nic"


    show_menu
    read -p "请输入选项: " option

    case $option in
        1)
            read -p "请输入目标虚拟机 ID: " selected_vm_id
            if ! [[ "$selected_vm_id" =~ ^[0-9]+$ ]]; then
                echo "无效的虚拟机 ID，必须是数字。"
                exit 1 # 直接退出
            fi

            read -p "请输入目标虚拟机网卡编号 (例如 0, 1, 2...): " selected_vm_nic
            if ! [[ "$selected_vm_nic" =~ ^[0-9]+$ ]]; then
                echo "无效的虚拟机网卡编号，必须是数字。"
                exit 1 # 直接退出
            fi
            selected_vm_iface=$(get_host_iface_from_vm_nic "$selected_vm_id" "$selected_vm_nic")
            mirror_traffic "$selected_host_nic" "$selected_vm_id" "$selected_vm_nic"
            exit 0
            ;;
        2)

            remove_mirror "$selected_host_nic"
            exit 0
            ;;
        3)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新选择。"
            exit 1 # 无效选项也退出，防止无限循环
            ;;
    esac
}

main


main