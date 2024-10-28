import logging
import json
import os
import traceback
import re
from datetime import datetime

def setup_logging(profile, region):
    """设置日志记录"""
    log_file = get_log_file_path(profile, region)
    log_dir = os.path.dirname(log_file)

    # 确保日志目录存在
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)

    logging.basicConfig(
        filename=log_file,
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        encoding='utf-8'
    )

def log_and_print(message, profile=None, region=None):
    """记录日志并打印消息"""
    print(message)
    logging.info(message)

    if profile and region:
        log_file = get_log_file_path(profile, region)
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
    """保存资源 ID 信息到文件"""
    ids_file = get_ids_file_path(profile, region)
    ids = read_ids(profile, region)
    updated = False

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
                        updated = True
            else:
                if value['name'] not in existing_names:
                    new_buckets.append(value)
                    updated = True

            if new_buckets:  # 只有当有新的存储桶时才更新
                ids[key].extend(new_buckets)

        elif 'overwrite' in kwargs and kwargs['overwrite']:
            ids[key] = [value]
            updated = True
        else:
            # 对于其他类型的资源，检查是否已存在
            if not any(item.get('InstanceId') == value.get('InstanceId') for item in ids[key]):
                ids[key].append(value)
                updated = True

    # 移除 'overwrite' 键，因为它不是实际的资源信息
    if 'overwrite' in ids:
        del ids['overwrite']

    # 只有在有更新时才写入文件和输出日志
    if updated:
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
    """获取数据目录路径"""
    # 获取当前脚本所在目录的父目录的父目录（即 deploy.sh）
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    data_dir = os.path.join(base_dir, 'data')
    if not os.path.exists(data_dir):
        os.makedirs(data_dir)
    return data_dir

def get_ids_file_path(profile, region):
    """获取 ids.json 文件路径"""
    return os.path.join(get_data_dir(), f'{profile}_{region}_ids.json')

def get_log_file_path(profile, region):
    """获取日志文件路径"""
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
