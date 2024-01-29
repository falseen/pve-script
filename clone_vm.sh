#!/bin/bash

# 与用户交互获取模板ID、克隆数量和虚拟机名称
read -p "请输入模板虚拟机的ID（默认为100）: " template_id
template_id=${template_id:-100}

read -p "请输入要克隆的虚拟机数量: " num_clones

# 提示用户输入基础名称，如果没有输入，则使用默认的
read -p "请输入虚拟机的基础名称（自动生成编号，留空使用默认值）: " base_name

# 获取模板名称
template_name=$(qm config $template_id | grep '^name:' | awk '{print $2}')

# 尝试创建虚拟机
echo "尝试创建虚拟机："
for ((i=0; i<$num_clones; i++)); do
  next_id=$(pvesh get /cluster/nextid)

  # 打印尝试的虚拟机ID
  echo "尝试的虚拟机ID：$next_id"

  if [ -n "$base_name" ]; then
    new_vm_name="${base_name}-${next_id}"
  else
    new_vm_name="${template_name}-${next_id}"
  fi

  # 使用重定向符号将输出隐藏
  qm clone $template_id $next_id --name "$new_vm_name" > /dev/null 2>&1 && \
  echo "虚拟机克隆完成。克隆虚拟机ID：$next_id，名称：$new_vm_name。"
done

