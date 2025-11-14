#!/bin/bash

printf "%-50s %-20s %-15s %-10s\n" "REPOSITORY" "TAG" "IMAGE ID" "ARCHITECTURE" && \
docker images --format "{{.Repository}} {{.Tag}} {{.ID}}" | \
while read repo tag id; do
  arch=$(docker inspect --format '{{.Architecture}}' "$id" 2>/dev/null || echo "unknown")
  # 按固定宽度输出，-表示左对齐，数字为列宽（可根据需求调整）
  printf "%-50s %-20s %-15s %-10s\n" "$repo" "$tag" "$id" "$arch"
done
