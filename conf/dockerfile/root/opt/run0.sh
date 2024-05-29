#!/usr/bin/env bash

## 初始化程序
[ -f /opt/init.sh ] && bash /opt/init.sh
[ -f /app/init.sh ] && bash /app/init.sh

su -l spring -c "bash /opt/run.sh"
