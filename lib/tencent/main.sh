# -*- coding: utf-8 -*-
# ... existing code ...

function list_servers() {
    local response
    response=$(curl -s -X GET "https://cvm.api.qcloud.com/v2/index.php?Action=DescribeInstances&Version=2017-03-12&<Your_Parameters>")

    if [[ -z "$response" ]]; then
        echo "错误：无法获取服务器列表。"
        return 1
    fi

    echo "服务器列表："
    echo "$response" | jq '.Response.InstanceSet[] | {InstanceId, InstanceName, Status}'
}

# ... existing code ...
