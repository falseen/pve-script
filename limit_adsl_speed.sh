#!/bin/bash

# 定义钩子脚本存储路径和名称
SNIPPETS_DIR="/var/lib/vz/snippets"
HOOK_SCRIPT_NAME="limit_pppoe_upload.pl"
HOOK_SCRIPT_PATH="$SNIPPETS_DIR/$HOOK_SCRIPT_NAME"
STORAGE_ID="local"

# 检查并创建snippets存储目录
mkdir -p $SNIPPETS_DIR

# 请求用户输入带宽限制和虚拟机ID
read -p "请输入上传带宽限制（例如 '10Mbit'）:" UPLOAD_RATE
UPLOAD_RATE_KBIT=$((${UPLOAD_RATE} * 1024))Kbit

read -p "请输入下载带宽限制（例如 '100Mbit'，留空则不限制）:" DOWNLOAD_RATE
DOWNLOAD_RATE_KBIT=$((${DOWNLOAD_RATE} * 1024))Kbit

echo "上传带宽限制被设置为: $UPLOAD_RATE_KBIT"
echo "下载带宽限制被设置为: $DOWNLOAD_RATE_KBIT"
read -p "请输入虚拟机的VMID（留空以选择所有虚拟机）:" VMID
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
cat > $HOOK_SCRIPT_PATH <<EOF
#!/usr/bin/perl

use strict;
use warnings;

my \$vmid = shift;
my \$phase = shift;

if (\$phase eq 'post-start') {
    print "\$vmid is starting, setting upload bandwidth limit to $UPLOAD_RATE_KBIT.\n";
    my \$DEV = "tap\${vmid}${DEV_SUFFIX}";
    
    # 删除旧的带宽限制规则
    system("tc qdisc del dev \$DEV root 2>/dev/null || echo 'HTB is not exist, continue...'");
    system("tc qdisc del dev \$DEV ingress 2>/dev/null || echo 'ingress is not exist, continue...'");
    
    # 应用上传带宽限制
    system("tc qdisc add dev \$DEV root handle 1: htb default 1 r2q 10 direct_qlen 1000");
    system("tc qdisc add dev \$DEV handle ffff: ingress");
    system("tc filter add dev \$DEV parent ffff: protocol all pref 50 basic police rate $UPLOAD_RATE_KBIT burst 1Mb mtu 64Kb action drop");
    
EOF

# 如果设置了下载带宽限制，则添加相关的tc命令
if [ ! -z "$DOWNLOAD_RATE_KBIT" ]; then
cat >> $HOOK_SCRIPT_PATH <<EOF
    print "\$vmid is starting, setting download bandwidth limit to ${DOWNLOAD_RATE_KBIT}.\n";
    system("tc class add dev \$DEV parent 1: classid 1:1 htb rate ${DOWNLOAD_RATE_KBIT} ceil ${DOWNLOAD_RATE_KBIT} burst 1Mb cburst 1595b");
EOF
fi

# 结束Perl脚本
cat >> $HOOK_SCRIPT_PATH <<EOF
}
EOF

# 为钩子脚本赋予执行权限
chmod +x $HOOK_SCRIPT_PATH

# 应用带宽限制的函数
apply_tc_rules() {
    local vmid=$1
    local rate=$2
    local DEV="tap${vmid}${DEV_SUFFIX}"

	# 应用带宽限制
	# 删除已存在的HTB队列规则（如果存在）
	#echo "删除 $DEV 上的现有HTB队列规则..."
	tc qdisc del dev $DEV root 2>/dev/null || echo "HTB队列规则不存在，继续..."

	# 删除已存在的ingress队列规则（如果存在）
	#echo "删除 $DEV 上的现有ingress队列规则..."
	tc qdisc del dev $DEV ingress 2>/dev/null || echo "ingress队列规则不存在，继续..."

	# 添加HTB队列规则
	#echo "添加HTB队列规则到 $DEV..."
	tc qdisc add dev $DEV root handle 1: htb default 1 r2q 10 direct_qlen 1000

	# 添加ingress队列规则
	#echo "添加ingress队列规则到 $DEV..."
	tc qdisc add dev $DEV handle ffff: ingress

	# 添加过滤器规则
	#echo "添加上传过滤器规则到 $DEV..."
	tc filter add dev $DEV parent ffff: protocol all pref 50 basic police rate $UPLOAD_RATE_KBIT burst 1Mb mtu 64Kb action drop
	echo "带宽限制 $rate 已应用于虚拟机 $vmid 的接口 $iface."
	if [ -n "$DOWNLOAD_RATE_KBIT" ]; then
		#限制下载
		echo "添加下载过滤器规则到 $DEV..."
		tc class add dev $DEV parent 1: classid 1:1 htb rate $DOWNLOAD_RATE_KBIT ceil $DOWNLOAD_RATE_KBIT burst 1Mb cburst 1595b
	fi
}

# 设置钩子脚本并立即应用带宽限制
if [ -z "$VMID" ]; then
    # 为所有运行的虚拟机设置并应用带宽限制
    for vm in $(qm list | awk '{print $1}' | grep -oP '\d+'); do
        VM_STATUS=$(qm status $vm | awk '{print $2}')
        if [ "$VM_STATUS" = "running" ]; then
            apply_tc_rules $vm $UPLOAD_RATE_KBIT 
        else
            echo "虚拟机 $vm 未开机，tc命令将在下次开机时应用。"
        fi
        echo "虚拟机 $VMID 设置钩子文件"
        qm set $vm --hookscript $STORAGE_ID:snippets/$HOOK_SCRIPT_NAME
    done
else
    # 检查指定虚拟机是否开机
    VM_STATUS=$(qm status $VMID | awk '{print $2}')
    if [ "$VM_STATUS" = "running" ]; then
        apply_tc_rules $VMID $UPLOAD_RATE_KBIT
    else
        echo "虚拟机 $VMID 未开机，tc命令将在下次开机时应用。"
    fi
    echo "虚拟机 $VMID 设置钩子文件"
    qm set $VMID --hookscript $STORAGE_ID:snippets/$HOOK_SCRIPT_NAME
fi

echo "带宽限制设置完成。"
