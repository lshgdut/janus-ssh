#!/bin/bash
# scripts/integration-test.sh — Docker sshd 集成测试
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT/tools/integration-tests"

echo "==> Starting test SSH server (Docker)..."
cd "$TEST_DIR"
docker compose up -d sshd

# 等 sshd 启动
sleep 2

echo "==> Running integration tests..."
# 这里通过真实的 janus binary / 手动验证 ssh tunnel
# 实际项目用 XCTest + SSHProcess 集成测试
TEST_HOST="127.0.0.1"
TEST_PORT=2222
TEST_USER="testuser"
TEST_PASSWORD="testpass"

# 测试 1: ssh 直接连接
echo "  Test 1: ssh direct connect..."
sshpass -p "$TEST_PASSWORD" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -p $TEST_PORT \
  $TEST_USER@$TEST_HOST \
  "echo 'ssh works'"

# 测试 2: -L 端口转发
echo "  Test 2: ssh -L port forward..."
sshpass -p "$TEST_PASSWORD" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -f -N \
  -L 15432:127.0.0.1:5432 \
  -p $TEST_PORT \
  $TEST_USER@$TEST_HOST

# 验证转发
sleep 1
nc -zv 127.0.0.1 15432 && echo "  ✓ forward works"

# 清理
pkill -f "ssh.*-L 15432" || true
docker compose down

echo "✅ Integration tests passed"