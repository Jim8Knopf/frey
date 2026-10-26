#!/bin/bash

# Pi5 Hub Performance Optimization Script

echo "⚡ Pi5 Performance Optimierung..."

# GPU Memory Split
sudo raspi-config nonint do_memory_split 16

# Enable SSD TRIM
sudo fstrim -v /mnt/ssd

# Optimize Docker
docker system prune -af

# Clear Logs
sudo journalctl --vacuum-time=7d

echo "✅ Optimierung abgeschlossen!"
