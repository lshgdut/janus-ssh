#!/bin/bash
# scripts/test.sh — 跑 Tunnel Engine 单元测试 + verify 可执行
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/JanusSSHTunnelEngine"

echo "==> Building Tunnel Engine..."
cd "$ENGINE"
swift build

echo ""
echo "==> Running verify executable..."
mkdir -p .build
swiftc -parse-as-library -o .build/verify \
  Sources/JanusSSHTunnelEngine/Domain/*.swift \
  Sources/JanusSSHTunnelEngine/Validation/*.swift \
  Sources/JanusSSHTunnelEngine/Persistence/*.swift \
  Sources/JanusSSHTunnelEngine/Settings/*.swift \
  Sources/JanusSSHTunnelEngine/SSH/*.swift \
  Sources/JanusSSHTunnelEngine/Tunnel/*.swift \
  Sources/JanusSSHTunnelEngine/Network/*.swift \
  Sources/JanusSSHTunnelEngine/Services/*.swift \
  verify/verify.swift
.build/verify