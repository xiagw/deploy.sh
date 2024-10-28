import oss2
import re
from datetime import datetime
from .utils import log_and_print, save_ids, read_ids, get_ids_file_path
from .config import Config
import json
import os
import concurrent.futures
from tqdm import tqdm
import queue
import threading

class OSSManager:
    def __init__(self, access_key_id, access_key_secret, region, profile='default'):
        self.auth = oss2.Auth(access_key_id, access_key_secret)
        self.region = region
        self.profile = profile
        self.endpoint = f'http://oss-{region}-internal.aliyuncs.com'

    def create_bucket(self, bucket_name):
        # 验证存储桶名称
        if not re.match(r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$', bucket_name):
            log_and_print(f"错误: 无效的存储桶名称 '{bucket_name}'")
            log_and_print("存储桶名称必须符合以下规则:")
            log_and_print("1. 只能包含小写字母、数字和连字符（-）")
            log_and_print("2. 必须以小写字母或数字开头和结尾")
            log_and_print("3. 长度必须在 3-63 个字符之间")
            return False

        bucket = oss2.Bucket(self.auth, self.endpoint, bucket_name)

        try:
            log_and_print(f"尝试创建 OSS 存储桶 '{bucket_name}' 在 {self.endpoint}", self.profile, self.region)
            bucket.create_bucket()
            log_and_print(f"OSS 存储桶 '{bucket_name}' 创建成功", self.profile, self.region)

            # 获取 bucket 的域名
            bucket_domain = f"{bucket_name}.{self.endpoint.replace('http://', '')}"
            log_and_print(f"OSS 存储桶域名: {bucket_domain}", self.profile, self.region)

            # 保存 bucket 名字和域名
            oss_info = {"name": bucket_name, "domain": bucket_domain}
            save_ids(self.profile, self.region, oss_bucket=oss_info)
            log_and_print(f"OSS 存储桶信息已保存: {oss_info}", self.profile, self.region)

            return True
        except Exception as e:
            log_and_print(f"创建 OSS 存储桶失败: {str(e)}", self.profile, self.region)
            return False

    def delete_bucket(self, bucket_name):
        bucket = oss2.Bucket(self.auth, self.endpoint, bucket_name)

        try:
            # 使用较小的批量大小（每批100个对象）
            batch_size = 100
            deleted_count = 0

            while True:
                # 列出存储桶中的对象，每次最多1000个
                objects = list(oss2.ObjectIterator(bucket, max_keys=1000))
                if not objects:
                    break

                # 分批处理对象
                for i in range(0, len(objects), batch_size):
                    batch = objects[i:i + batch_size]
                    keys = [obj.key for obj in batch]

                    try:
                        # 批量删除对象
                        bucket.batch_delete_objects(keys)
                        deleted_count += len(keys)
                        log_and_print(f"已删除 {len(keys)} 个对象（总计: {deleted_count}）", self.profile, self.region)
                    except oss2.exceptions.ServerError as e:
                        # 如果批量删除失败，尝试逐个删除
                        log_and_print(f"批量删除失败，切换到单个删除模式", self.profile, self.region)
                        for key in keys:
                            try:
                                bucket.delete_object(key)
                                deleted_count += 1
                                if deleted_count % 10 == 0:  # 每删除10个对象输出一次日志
                                    log_and_print(f"已删除 {deleted_count} 个对象", self.profile, self.region)
                            except Exception as e:
                                log_and_print(f"删除对象 {key} 失败: {str(e)}", self.profile, self.region)

            # 删除存储桶
            try:
                bucket.delete_bucket()
                log_and_print(f"OSS 存储桶 '{bucket_name}' 删除成功", self.profile, self.region)
            except oss2.exceptions.BucketNotEmpty:
                # 如果存储桶不为空，再次尝试列出和删除对象
                log_and_print(f"存储桶仍不为空，进行最后一次清理", self.profile, self.region)
                objects = list(oss2.ObjectIterator(bucket))
                if objects:
                    for obj in objects:
                        try:
                            bucket.delete_object(obj.key)
                        except Exception as e:
                            log_and_print(f"删除对象 {obj.key} 失败: {str(e)}", self.profile, self.region)
                # 再次尝试删除存储桶
                bucket.delete_bucket()
                log_and_print(f"OSS 存储桶 '{bucket_name}' 删除成功", self.profile, self.region)

        except oss2.exceptions.NoSuchBucket:
            log_and_print(f"警告: OSS 存储桶 '{bucket_name}' 不存在，可能已被删除", self.profile, self.region)
        except Exception as e:
            log_and_print(f"删除 OSS 存储桶失败: {str(e)}", self.profile, self.region)
            return False

        # 无论存储桶是否存在，都尝试从本地记录中移除
        self.remove_bucket_from_ids(bucket_name)
        return True

    def list_buckets(self):
        service = oss2.Service(self.auth, self.endpoint)

        log_and_print(f"正在连接到 OSS 服务，endpoint: {self.endpoint}", self.profile, self.region)
        all_buckets = []

        try:
            bucket_list = list(oss2.BucketIterator(service))
            log_and_print(f"找到 {len(bucket_list)} 个存储桶", self.profile, self.region)

            for bucket in bucket_list:
                bucket_region = bucket.location.replace('oss-', '')
                if bucket_region == self.region:
                    creation_date = datetime.fromtimestamp(bucket.creation_date).isoformat()
                    bucket_info = {
                        'name': bucket.name,
                        'location': bucket_region,
                        'creation_date': creation_date
                    }
                    all_buckets.append(bucket_info)
                    log_and_print(f"存储桶: {bucket.name} (位置: {bucket_region}, 创建时间: {creation_date})",
                                self.profile, self.region)

            if all_buckets:
                save_ids(self.profile, self.region, oss_bucket=all_buckets)
            else:
                log_and_print(f"在 {self.region} 区域未找到任何 OSS 存储桶", self.profile, self.region)

        except Exception as e:
            log_and_print(f"查询 OSS 存储桶列表时发生错误: {str(e)}", self.profile, self.region)

        return all_buckets

    def remove_bucket_from_ids(self, bucket_name):
        ids_file = get_ids_file_path(self.profile, self.region)
        ids = read_ids(self.profile, self.region)
        original_length = len(ids.get('oss_bucket', []))
        ids['oss_bucket'] = [b for b in ids.get('oss_bucket', []) if b['name'] != bucket_name]
        new_length = len(ids['oss_bucket'])

        if original_length != new_length:
            with open(ids_file, 'w', encoding='utf-8') as f:
                json.dump(ids, f, indent=2, ensure_ascii=False)
            log_and_print(f"已从 {ids_file} 中移除 OSS 存储桶 '{bucket_name}' 的信息", self.profile, self.region)
        else:
            log_and_print(f"OSS 存储桶 '{bucket_name}' 的信息不存在于本地记录中", self.profile, self.region)

    # 其他方法也需要类似的更新...

    def update_bucket_acl(self, bucket_name, acl):
        try:
            bucket = oss2.Bucket(self.auth, self.endpoint, bucket_name)
            bucket.put_bucket_acl(acl)
            log_and_print(f"已更新存储桶 '{bucket_name}' 的 ACL 为 {acl}", self.profile, self.region)
            return True
        except Exception as e:
            log_and_print(f"更新存储桶 ACL 失败: {str(e)}", self.profile, self.region)
            return False

    def set_bucket_lifecycle(self, bucket_name, rules):
        try:
            bucket = oss2.Bucket(self.auth, self.endpoint, bucket_name)
            lifecycle = oss2.models.BucketLifecycle(rules)
            bucket.put_bucket_lifecycle(lifecycle)
            log_and_print(f"已设置存储桶 '{bucket_name}' 的生命周期规则", self.profile, self.region)
            return True
        except Exception as e:
            log_and_print(f"设置存储桶生命周期规则失败: {str(e)}", self.profile, self.region)
            return False

    def get_bucket_info(self, bucket_name):
        try:
            bucket = oss2.Bucket(self.auth, self.endpoint, bucket_name)

            # 获取存储桶信息
            bucket_info = bucket.get_bucket_info()

            # 获取存储桶访问权限
            acl = bucket.get_bucket_acl().acl

            # 获取存储桶存储类型
            storage_class = bucket.get_bucket_storage_capacity().storage_class

            # 获取存储桶标签
            try:
                tags = bucket.get_bucket_tagging()
            except oss2.exceptions.NoSuchTagSet:
                tags = []

            # 打印存储桶信息
            log_and_print(f"存储桶名称: {bucket_name}")
            log_and_print(f"创建时间: {bucket_info.creation_date}")
            log_and_print(f"存储区域: {bucket_info.location}")
            log_and_print(f"存储类型: {storage_class}")
            log_and_print(f"访问权限: {acl}")
            log_and_print("标签:")
            for tag in tags:
                log_and_print(f"  {tag.key}: {tag.value}")

            # 获取存储桶策略
            try:
                policy = bucket.get_bucket_policy()
                log_and_print("存储桶策略:")
                log_and_print(json.dumps(json.loads(policy.policy), indent=2, ensure_ascii=False))
            except oss2.exceptions.NoSuchBucketPolicy:
                log_and_print("存储桶策略: 未设置")

            return True
        except oss2.exceptions.NoSuchBucket:
            log_and_print(f"错误: 存储桶 '{bucket_name}' 不存在")
            return False
        except Exception as e:
            log_and_print(f"获取存储桶信息失败: {str(e)}")
            return False

    def migrate_multimedia_files(self, source_bucket_name, dest_bucket_name,
                               file_types=('.mp4', '.mp3', '.avi', '.jpg', '.png', '.gif', '.webp', '.flv',
                                           '.wmv', '.mov', '.mkv', '.mpg', '.mpeg', '.m4v', '.3gp', '.3g2',
                                           '.asf', '.asx', '.wma', '.wmv', '.m3u8', '.ts', '.m4a', '.m4b',
                                           '.m4p', '.m4r', '.m4v'),
                               batch_size=100, max_workers=5, delete_source=False, prefix=None):
        """
        优化的流式同步处理方式迁移低频存储类型的多媒体文件，并可选择删除源文件

        Args:
            source_bucket_name: 源存储桶名称
            dest_bucket_name: 目标存储桶名称
            file_types: 要迁移的文件类型
            batch_size: 每批处理的文件数量
            max_workers: 最大并发工作线程数
            delete_source: 是否在成功迁移后删除源文件
        """
        try:
            source_bucket = oss2.Bucket(self.auth, self.endpoint, source_bucket_name)
            dest_bucket = oss2.Bucket(self.auth, self.endpoint, dest_bucket_name)

            # 使用集合来跟踪已处理的文件，避免重复处理
            processed_files = set()

            # 构建日志消息，包含前缀信息
            start_msg = f"开始从 {source_bucket_name} 迁移多媒体文件到 {dest_bucket_name}"
            if prefix:
                start_msg += f" (子目录: {prefix})"
            log_and_print(start_msg + "...", self.profile, self.region)

            file_queue = queue.Queue(maxsize=batch_size * 2)
            producer_done = threading.Event()
            error_count = 0
            success_count = 0

            def producer():
                nonlocal error_count
                marker = ''

                try:
                    while True:
                        # 如果指定了前缀，则在列举对象时使用该前缀
                        objects = source_bucket.list_objects(
                            prefix=prefix,
                            marker=marker,
                            max_keys=1000
                        )

                        for obj in objects.object_list:
                            if obj.key.lower().endswith(file_types) and obj.key not in processed_files:
                                try:
                                    # 检查源文件是否存在
                                    source_bucket.head_object(obj.key)
                                    file_queue.put(obj)
                                    processed_files.add(obj.key)
                                except oss2.exceptions.NoSuchKey:
                                    error_count += 1
                                    log_and_print(f"源文件不存在: {obj.key}", self.profile, self.region)
                                except Exception as e:
                                    error_count += 1
                                    log_and_print(f"检查文件 {obj.key} 时发生错误: {str(e)}", self.profile, self.region)

                        if not objects.is_truncated:
                            break
                        marker = objects.next_marker

                except Exception as e:
                    log_and_print(f"扫描文件时发生错误: {str(e)}", self.profile, self.region)
                finally:
                    producer_done.set()

            def consumer():
                nonlocal success_count
                while not (producer_done.is_set() and file_queue.empty()):
                    try:
                        obj = file_queue.get(timeout=1)

                        # 执行复制操作
                        dest_bucket.copy_object(
                            source_bucket_name,
                            obj.key,
                            obj.key,
                            headers={'x-oss-storage-class': 'Standard'}
                        )

                        success_count += 1
                        if success_count % 10 == 0:  # 每10个文件输出一次进度
                            log_and_print(f"已成功迁移 {success_count} 个文件", self.profile, self.region)

                        # 如果需要删除源文件
                        if delete_source:
                            source_bucket.delete_object(obj.key)

                    except queue.Empty:
                        continue
                    except Exception as e:
                        error_count += 1
                        log_and_print(f"处理文件 {obj.key if 'obj' in locals() else 'unknown'} 时发生错误: {str(e)}",
                                    self.profile, self.region)

            # 启动生产者线程
            producer_thread = threading.Thread(target=producer)
            producer_thread.start()

            # 启动消费者线程池
            with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
                consumers = [executor.submit(consumer) for _ in range(max_workers)]
                concurrent.futures.wait(consumers)

            producer_thread.join()

            # 构建完成消息
            complete_msg = f"\n迁移完成: 成功迁移 {success_count} 个文件, 失败 {error_count} 个"
            if prefix:
                complete_msg += f" (子目录: {prefix})"
            if delete_source:
                complete_msg += ", 并删除了源文件"

            log_and_print(complete_msg, self.profile, self.region)

            return success_count > 0

        except Exception as e:
            log_and_print(f"迁移过程中发生错误: {str(e)}", self.profile, self.region)
            return False
