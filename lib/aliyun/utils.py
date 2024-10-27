import logging
import json
import os
import traceback
import re
from datetime import datetime

def setup_logging(profile, region):
    logging.basicConfig(filename=get_log_file_path(profile, region), level=logging.INFO,
                        format='%(asctime)s - %(levelname)s - %(message)s',
                        encoding='utf-8')

def log_and_print(message, profile=None, region=None):
    print(message)
    logging.info(message)
    log_file = get_log_file_path(profile, region) if profile and region else 'aliyun_operations.log'
    with open(log_file, 'a', encoding='utf-8') as f:
        f.write(f"{datetime.now().isoformat()} - INFO - {message}\n")

def read_ids(profile=None, region=None):
    if profile and region:
        ids_file = get_ids_file_path(profile, region)
    else:
        ids_file = 'ids.json'  # 使用默认文件名

    if os.path.exists(ids_file):
        with open(ids_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {"ecs": [], "dns": [], "oss": [], "slb": []}

def save_ids(profile, region, **kwargs):
    ids_file = get_ids_file_path(profile, region)
    ids = read_ids(profile, region)
    for key, value in kwargs.items():
        if key not in ids:
            ids[key] = []
        if key == 'oss_bucket':
            # 对于 OSS 存储桶，我们需要去重
            new_buckets = []
            existing_names = set(bucket['name'] for bucket in ids[key])
            if isinstance(value, list):
                for bucket in value:
                    if bucket['name'] not in existing_names:
                        new_buckets.append(bucket)
                        existing_names.add(bucket['name'])
            else:
                if value['name'] not in existing_names:
                    new_buckets.append(value)
            ids[key].extend(new_buckets)
        elif 'overwrite' in kwargs and kwargs['overwrite']:
            ids[key] = [value]
        else:
            # 对于其他类型的资源，检查是否已存在
            if not any(item.get('InstanceId') == value.get('InstanceId') for item in ids[key]):
                ids[key].append(value)

    # 移除 'overwrite' 键，因为它不是实际的资源信息
    if 'overwrite' in ids:
        del ids['overwrite']

    with open(ids_file, 'w', encoding='utf-8') as f:
        json.dump(ids, f, indent=2, ensure_ascii=False)
    log_and_print(f"ID 信息已保存到 {ids_file}")

def read_latest_log(profile, region, lines=20):
    log_file = get_log_file_path(profile, region)
    try:
        with open(log_file, 'r', encoding='utf-8') as f:
            log_content = f.readlines()
        return ''.join(log_content[-lines:])
    except Exception as e:
        return f"读取日志文件时出错: {str(e)}"

def handle_error(e, operation):
    log_and_print(f"{operation}失败: {str(e)}")
    log_and_print(f"错误类型: {type(e).__name__}")
    log_and_print(f"错误堆栈: {traceback.format_exc()}")

def validate_bucket_name(bucket_name):
    if not re.match(r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$', bucket_name):
        log_and_print(f"错误: 无效的存储桶名称 '{bucket_name}'")
        log_and_print("存储桶名称必须符合以下规则:")
        log_and_print("1. 只能包含小写字母、数字和连字符（-）")
        log_and_print("2. 必须以小写字母或数字开头和结尾")
        log_and_print("3. 长度必须在 3-63 个字符之间")
        return False
    return True

def remove_oss_prefix(region):
    return region.replace('oss-', '')

def get_data_dir():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    data_dir = os.path.join(base_dir, 'data')
    if not os.path.exists(data_dir):
        os.makedirs(data_dir)
    return data_dir

def get_ids_file_path(profile, region):
    return os.path.join(get_data_dir(), f'{profile}_{region}_ids.json')

def get_log_file_path(profile, region):
    return os.path.join(get_data_dir(), f'{profile}_{region}_operations.log')

def confirm_action(message):
    while True:
        response = input(f"{message} (yes/no): ").lower()
        if response in ['yes', 'y']:
            return True
        elif response in ['no', 'n']:
            return False
        else:
            print("请输入 'yes' 或 'no'。")

# 其他实用函数可以根据需要添加...
