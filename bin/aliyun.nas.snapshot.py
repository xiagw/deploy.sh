#!/usr/bin/env python3
# python3 -m pip install aliyun-python-sdk-nas
# jq -r '.profiles[] | select(.name == "flyh6") | .access_key_id' ~/.aliyun/config.json
# jq -r '.profiles[] | select(.name == "flyh6") | .access_key_secret' ~/.aliyun/config.json

import json
import os
import sys

from aliyunsdkcore.client import AcsClient
from aliyunsdknas.request.v20170626.CreateFileSystemRequest import CreateFileSystemRequest

aliyun_config = os.getenv('HOME') + "/.aliyun/config.json"
with open(aliyun_config, 'r', encoding='utf8')as fp:
    data = json.load(fp)
    for i in data['profiles']:
        if i['name'] == 'flyh6':
            profile_key_id = i['access_key_id']
            profile_key_secret = i['access_key_secret']
            break

## aliyun 极速型 NAS 创建的快照 id s-extreme-00848852jodmpq6w
if os.getenv('ALIYUN_NAS_SNAP_ID'):
    snapshot_id = os.getenv('ALIYUN_NAS_SNAP_ID')
else:
    snapshot_id = sys.argv[1]

def create_file_system():
    client = AcsClient(profile_key_id, profile_key_secret, 'cn-hangzhou')
    request = CreateFileSystemRequest()
    request.set_accept_format('json')
    request.set_StorageType("advance")
    request.set_ProtocolType("NFS")
    request.set_FileSystemType("extreme")
    request.set_Capacity("200")
    request.set_ZoneId("cn-hangzhou-h")
    request.set_SnapshotId(snapshot_id)

    response = client.do_action_with_exception(request)
    res = json.loads(response)
    print(res)


create_file_system()

## miniconda; conda activate myenv
# proxy off
# python aliyun.nas.snap.py