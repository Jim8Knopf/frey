#!/bin/bash

# Pi5 Hub Health Check Script

echo "🏥 Pi5 Hub Gesundheitscheck..."

# System Load
echo "📊 System Load:"
uptime

# Memory Usage
echo "💾 Memory Usage:"
free -h

# Disk Usage
echo "💽 Disk Usage:"
df -h

# Docker Services
echo "🐳 Docker Services:"
docker compose -f /mnt/ssd/docker/docker-compose.yml ps

# Temperature
echo "🌡️  CPU Temperature:"
vcgencmd measure_temp

echo "✅ Health Check abgeschlossen!"
