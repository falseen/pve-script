#!/bin/bash

# 与用户交互获取模板ID、克隆数量和虚拟机名称

# 提示用户输入模板虚拟机的ID，默认为100
read -p "请输入模板虚拟机的ID（默认为100）: " template_id
template_id=${template_id:-100}

# 提示用户输入要克隆的虚拟机数量
read -p "请输入要克隆的虚拟机数量: " num_clones

# 提示用户输入虚拟机的基础名称
read -p "请输入虚拟机的基础名称（自动生成编号，留空使用默认值）: " base_name

# 提示用户输入起始编号
read -p "请输入起始编号（三位数，如001）: " start_number

# 获取模板名称
template_name=$(qm config $template_id | grep '^name:' | awk '{print $2}')

# 尝试创建虚拟机
echo "尝试创建虚拟机："
for ((i=0; i<$num_clones; i++)); do
  next_id=$(pvesh get /cluster/nextid)

  # 根据起始编号生成虚拟机编号
  printf -v vm_number "%03d" "$((start_number + i))"

  if [ -n "$base_name" ]; then
    new_vm_name="${base_name}${vm_number}"
  else
    new_vm_name="${template_name}${vm_number}"
  fi

  # 使用重定向符号将输出隐藏
  qm clone $template_id $next_id --name "$new_vm_name" > /dev/null 2>&1 && \
  echo "虚拟机克隆完成。克隆虚拟机ID：$next_id，名称：$new_vm_name。"
done