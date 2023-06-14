#!/usr/bin/env bash

set -xe

cat <<EOF
kubectl config use-context arn:aws:eks:ap-southeast-1:11111111:cluster/ccp
k port-forward -n dbs pod/redisha-server-0 6380:6379
kubectl config use-context arn:aws:eks:ap-east-1:11111111:cluster/ccphk
k port-forward -n dbs pod/redisha-server-0 6381:6379
EOF

read -rp 'pause...'
redis-cli -p 6381 -n 0 flushall

redis-cli -p 6380 -n 0 keys '*' | while read -r key; do
    redis-cli -p 6380 -n 0 --raw dump "$key" | head -c-1 | redis-cli -p 6381 -n 0 -x restore "$key" 0
    # echo "migrate key $key"
done
