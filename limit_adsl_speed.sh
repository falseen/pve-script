#!/bin/bash

# 定义钩子脚本存储路径和名称
SNIPPETS_DIR="/var/lib/vz/snippets"
HOOK_SCRIPT_NAME="limit_pppoe_upload.pl"
HOOK_SCRIPT_PATH="$SNIPPETS_DIR/$HOOK_SCRIPT_NAME"
STORAGE_ID="local"

# 检查并创建snippets存储目录
mkdir -p "$SNIPPETS_DIR"

# 请求用户输入上传带宽限制
read -p "请输入上传带宽限制（例如 '10Mbit'）:" UPLOAD_RATE
# 转换为Kbit，并进行输入验证，只允许数字和可选的 "Mbit" 后缀
if [[ ! "$UPLOAD_RATE" =~ ^[0-9]+(Mbit)?$ ]]; then
    echo "无效的上传带宽格式。请使用例如 '10Mbit' 或 '10' 的格式。"
    exit 1
fi
UPLOAD_RATE_KBIT=$(( ${UPLOAD_RATE%%Mbit} * 1024 ))Kbit #移除Mbit后缀并乘以1024转换为Kbit

# 请求用户输入下载带宽限制
read -p "请输入下载带宽限制（例如 '100Mbit'，留空则不限制）:" DOWNLOAD_RATE
if [[ ! -z "$DOWNLOAD_RATE" ]]; then # 如果输入了下载带宽
    if [[ ! "$DOWNLOAD_RATE" =~ ^[0-9]+(Mbit)?$ ]]; then # 验证下载带宽格式
        echo "无效的下载带宽格式。请使用例如 '100Mbit' 或 '100' 的格式。"
        exit 1
    fi
    DOWNLOAD_RATE_KBIT=$(( ${DOWNLOAD_RATE%%Mbit} * 1024 ))Kbit #移除Mbit后缀并乘以1024转换为Kbit
fi

# 输出设置的带宽限制
echo "上传带宽限制被设置为: $UPLOAD_RATE_KBIT"
if [[ ! -z "$DOWNLOAD_RATE_KBIT" ]]; then
    echo "下载带宽限制被设置为: $DOWNLOAD_RATE_KBIT"
else
    echo "未设置下载带宽限制"
fi

# 请求用户输入虚拟机前缀名称
read -p "请输入虚拟机前缀名称（例如 'test'，留空则匹配所有虚拟机）:" VM_PREFIX

# 根据是否输入前缀设置 awk 命令的过滤器
if [ -z "$VM_PREFIX" ]; then
    echo "未输入虚拟机前缀，将匹配所有虚拟机。"
    VM_FILTER='{print $1}' # 匹配所有虚拟机
else
    VM_FILTER='$2 ~ /^'"$VM_PREFIX"'/ {print $1}' # 匹配以指定前缀开头的虚拟机
fi

# 请求用户选择网卡
read -p "请选择网卡（1表示第一张网卡，2表示第二张网卡）:" NIC_CHOICE
if [ "$NIC_CHOICE" = "1" ]; then
    DEV_SUFFIX="i0"
elif [ "$NIC_CHOICE" = "2" ]; then
    DEV_SUFFIX="i1"
else
    echo "无效的网卡选择。"
    exit 1
fi

# 创建Perl钩子脚本
cat > "$HOOK_SCRIPT_PATH" <<EOF
#!/usr/bin/perl

use strict;
use warnings;

my \$vmid = shift; # 第一个参数是虚拟机ID
my \$phase = shift; # 第二个参数是钩子阶段

if (\$phase eq 'post-start') { # 如果是虚拟机启动后阶段
    print "\$vmid is starting, setting bandwidth limit.\n";
    my \$DEV = "tap\${vmid}${DEV_SUFFIX}"; # 构建网络设备名称

    # 删除旧的带宽限制规则，忽略错误
    system("tc qdisc del dev \$DEV root 2>/dev/null");
    system("tc qdisc del dev \$DEV ingress 2>/dev/null");

    # 应用上传带宽限制
    system("tc qdisc add dev \$DEV root handle 1: htb default 1 r2q 10 direct_qlen 1000");
    system("tc qdisc add dev \$DEV handle ffff: ingress");
    system("tc filter add dev \$DEV parent ffff: protocol all pref 50 basic police rate $UPLOAD_RATE_KBIT burst 1Mb mtu 64Kb action drop");

EOF

if [[ ! -z "$DOWNLOAD_RATE_KBIT" ]]; then # 如果设置了下载带宽限制
cat >> "$HOOK_SCRIPT_PATH" <<EOF
    # 应用下载带宽限制
    system("tc class add dev \$DEV parent 1: classid 1:1 htb rate $DOWNLOAD_RATE_KBIT ceil $DOWNLOAD_RATE_KBIT burst 1Mb cburst 1595b");
EOF
fi

cat >> "$HOOK_SCRIPT_PATH" <<EOF
}
EOF

# 为钩子脚本赋予执行权限
chmod +x "$HOOK_SCRIPT_PATH"

# 应用带宽限制的函数
apply_tc_rules() {
    local vmid="$1"
    local DEV="tap${vmid}${DEV_SUFFIX}" # 构建网络设备名称

    # 删除旧的带宽限制规则，忽略错误
    tc qdisc del dev "$DEV" root 2>/dev/null
    tc qdisc del dev "$DEV" ingress 2>/dev/null

    # 应用带宽限制
    tc qdisc add dev "$DEV" root handle 1: htb default 1 r2q 10 direct_qlen 1000
    tc qdisc add dev "$DEV" handle ffff: ingress
    tc filter add dev "$DEV" parent ffff: protocol all pref 50 basic police rate "$UPLOAD_RATE_KBIT" burst 1Mb mtu 64Kb action drop
    if [[ ! -z "$DOWNLOAD_RATE_KBIT" ]]; then # 如果设置了下载带宽限制
      tc class add dev "$DEV" parent 1: classid 1:1 htb rate "$DOWNLOAD_RATE_KBIT" ceil "$DOWNLOAD_RATE_KBIT" burst 1Mb cburst 1595b
    fi
}

# 查找匹配的虚拟机并设置钩子和应用规则
for vm in $(qm list | awk "$VM_FILTER"); do # 使用 awk 命令过滤虚拟机列表
    VM_STATUS=$(qm status "$vm" | awk '{print $2}') # 获取虚拟机状态
    echo "正在处理虚拟机 $vm (状态: $VM_STATUS)"
    if [ "$VM_STATUS" = "running" ]; then # 如果虚拟机正在运行
        apply_tc_rules "$vm" # 立即应用带宽限制
    else
        echo "虚拟机 $vm 未运行，将在下次启动时应用规则。"
    fi
    qm set "$vm" --hookscript "$STORAGE_ID:snippets/$HOOK_SCRIPT_NAME" # 设置钩子脚本
done

echo "带宽限制设置完成。"