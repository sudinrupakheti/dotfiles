#!/bin/bash

# Create the systemd service file
sudo touch /etc/systemd/system/battery-charge-threshold.service

# Add the service configuration to the file
sudo bash -c "cat >> /etc/systemd/system/battery-charge-threshold.service" << EOF
[Unit]
Description=Set the battery charge threshold
After=multi-user.target

StartLimitBurst=0
[Service]
Type=oneshot
Restart=on-failure

ExecStart=/bin/bash -c 'echo 80 > /sys/class/power_supply/BAT1/charge_control_end_threshold'
[Install]
WantedBy=multi-user.target
EOF

# Enable the service to run at boot
sudo systemctl enable battery-charge-threshold.service
