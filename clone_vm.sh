#!/bin/bash

# 与用户交互获取模板ID、克隆数量和虚拟机名称
read -p "请输入模板虚拟机的ID（默认为1000）: " template_id
template_id=${template_id:-1000}

read -p "请输入要克隆的虚拟机数量: " num_clones

# 提示用户输入基础名称，如果没有输入，则使用默认的
read -p "请输入虚拟机的基础名称（自动生成编号，留空使用默认值）: " base_name

# 获取模板名称
template_name=$(qm config $template_id | grep '^name:' | awk '{print $2}')

# 打印当前已存在的虚拟机ID
echo "当前已存在的虚拟机ID："
existing_ids=($(find /etc/pve/qemu-server/ -maxdepth 1 -type f -exec basename {} \; | grep -oP '^[0-9]+' | sort -n))
echo "${existing_ids[@]}"

# 打印可用的虚拟机ID范围
echo "可用的虚拟机ID范围："
available_ids=()
for ((i=1000; i<=9999; i++)); do
  if ! echo "${existing_ids[@]}" | grep -q "\<$i\>"; then
    available_ids+=("$i")
  fi
done
echo "${available_ids[@]}"

# 寻找未被使用的虚拟机ID
echo "尝试查找可用的虚拟机ID："
for ((i=1000; i<=$num_clones+999; i++)); do
  new_vm_id=${available_ids[$i-1000]}

  if [ -z "$new_vm_id" ]; then
    echo "错误：无法找到足够数量的可用虚拟机ID。"
    exit 1
  fi

  # 打印尝试的虚拟机ID
  echo "尝试的虚拟机ID：$new_vm_id"

  if [ -n "$base_name" ]; then
    new_vm_name="${base_name}-${new_vm_id}"
  else
    new_vm_name="${template_name}-${new_vm_id}"
  fi

  # 使用重定向符号将输出隐藏
  qm clone $template_id $new_vm_id --name "$new_vm_name" > /dev/null 2>&1 && \
  echo "虚拟机克隆完成。克隆虚拟机ID：$new_vm_id，名称：$new_vm_name。"
done
