#!/bin/sh

# 提示用户输入文件名
read -p "请输入要添加的文件名: " filename

# 提示用户输入提交备注
read -p "请输入提交备注: " commit_message

# 添加文件到暂存区
git add "$filename"

# 提交更改
git commit -m "$commit_message"

# 推送到远程仓库
git push origin main