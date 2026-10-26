#!/bin/bash

# Pi5 Hub Maintenance Script

echo "🔧 Pi5 Hub Wartung gestartet..."

# Docker Cleanup
echo "🐳 Docker Cleanup..."
docker system prune -f
docker image prune -f

# Update System
echo "📦 System Updates..."
sudo apt update && sudo apt upgrade -y

# Check Disk Space
echo "💾 Speicherplatz prüfen..."
df -h /mnt/ssd

# Service Status
echo "⚙️  Service Status..."
docker compose -f /mnt/ssd/docker/docker-compose.yml ps

echo "✅ Wartung abgeschlossen!"
