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
        self.endpoint = f'http://oss-{region}.aliyuncs.com'

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
            # 首先删除存储桶中的所有对象
            for obj in oss2.ObjectIterator(bucket):
                bucket.delete_object(obj.key)
                log_and_print(f"删除对象: {obj.key}", self.profile, self.region)

            # 删除存储桶
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
            log_and_print("开始列举 OSS 存储桶...", self.profile, self.region)
            bucket_list = list(oss2.BucketIterator(service))
            log_and_print(f"找到 {len(bucket_list)} 个存储桶", self.profile, self.region)

            for bucket in bucket_list:
                # 移除 'oss-' 前缀以获取实际的区域名称
                bucket_region = bucket.location.replace('oss-', '')
                log_and_print(f"处理存储桶：名称={bucket.name}, 位置={bucket_region}", self.profile, self.region)

                # 检查存储桶是否在指定区域
                if bucket_region == self.region:
                    creation_date = datetime.fromtimestamp(bucket.creation_date).isoformat()
                    bucket_info = {
                        'name': bucket.name,
                        'location': bucket_region,
                        'creation_date': creation_date
                    }
                    all_buckets.append(bucket_info)
                    log_and_print(f"添加 OSS 存储桶：名称={bucket.name}, 位置={bucket_region}, 创建日期={creation_date}", self.profile, self.region)

                    # 使用 save_ids 函数追加每个存储桶的信息
                    save_ids(self.profile, self.region, oss_bucket=bucket_info)
                else:
                    log_and_print(f"跳过不在指定区域的存储桶：名称={bucket.name}, 位置={bucket_region}", self.profile, self.region)

            if not all_buckets:
                log_and_print(f"在 {self.region} 区域未找到任何 OSS 存储桶", self.profile, self.region)
            else:
                log_and_print(f"已将 {len(all_buckets)} 个 OSS 存储桶信息保存到 ids.json", self.profile, self.region)

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
                                           '.m4p', '.m4r', '.m4v', '.m3u', '.m3u', '.m3u'),
                               batch_size=100, max_workers=5):
        """
        流式同步处理方式迁移低频存储类型的多媒体文件，避免重复迁移
        """
        try:
            source_bucket = oss2.Bucket(self.auth, self.endpoint, source_bucket_name)
            dest_bucket = oss2.Bucket(self.auth, self.endpoint, dest_bucket_name)

            log_and_print(f"开始同步 {source_bucket_name} 中的低频存储多媒体文件...", self.profile, self.region)

            # 使用队列来存储待处理的文件
            file_queue = queue.Queue(maxsize=batch_size * 2)
            # 使用事件来控制生产者和消费者
            producer_done = threading.Event()

            # 计数器
            processed_count = 0
            success_count = 0
            skipped_count = 0  # 添加跳过计数器的初始化

            # 生产者线程：扫描文件并放入队列
            def producer():
                nonlocal skipped_count  # 添加 nonlocal 声明
                marker = ''
                try:
                    while True:
                        objects = source_bucket.list_objects(marker=marker, max_keys=1000)
                        for obj in objects.object_list:
                            if obj.key.lower().endswith(file_types):
                                try:
                                    # 获取源文件的元数据
                                    source_headers = source_bucket.head_object(obj.key)
                                    storage_class = source_headers.headers.get('x-oss-storage-class', 'Standard')
                                    source_etag = source_headers.headers.get('etag', '').strip('"')

                                    # 只处理低频存储类型的文件
                                    if storage_class == 'IA':
                                        try:
                                            # 检查目标文件是否存在
                                            dest_headers = dest_bucket.head_object(obj.key)
                                            dest_etag = dest_headers.headers.get('etag', '').strip('"')
                                            dest_storage_class = dest_headers.headers.get('x-oss-storage-class', 'Standard')

                                            # 如果文件已存在且 ETag 相同且存储类型相同，则跳过
                                            if source_etag == dest_etag and storage_class == dest_storage_class:
                                                skipped_count += 1
                                                log_and_print(f"跳过已存在的文件: {obj.key}", self.profile, self.region)
                                                continue

                                        except oss2.exceptions.NoSuchKey:
                                            # 目标文件不存在，需要迁移
                                            pass

                                        file_queue.put((obj, storage_class, source_etag))
                                        log_and_print(f"添加待迁移文件: {obj.key}", self.profile, self.region)

                                except Exception as e:
                                    log_and_print(f"检查文件 {obj.key} 时发生错误: {str(e)}", self.profile, self.region)

                        if not objects.is_truncated:
                            break
                        marker = objects.next_marker
                except Exception as e:
                    log_and_print(f"扫描文件时发生错误: {str(e)}", self.profile, self.region)
                finally:
                    producer_done.set()

            # 消费者函数：处理队列中的文件
            def consumer():
                nonlocal processed_count, success_count
                while not (producer_done.is_set() and file_queue.empty()):
                    try:
                        # 使用超时来避免永久阻塞
                        obj_info = file_queue.get(timeout=1)
                        obj, storage_class, source_etag = obj_info

                        try:
                            # 准备目标文件的headers
                            object_headers = {
                                'x-oss-storage-class': storage_class,
                                'x-oss-metadata-directive': 'COPY',
                            }

                            # 执行复制
                            dest_bucket.copy_object(
                                source_bucket_name,
                                obj.key,
                                obj.key,
                                headers=object_headers
                            )

                            # 验证迁移是否成功
                            dest_headers = dest_bucket.head_object(obj.key)
                            dest_etag = dest_headers.headers.get('etag', '').strip('"')

                            if source_etag == dest_etag:
                                success_count += 1
                                log_and_print(f"成功迁移: {obj.key}", self.profile, self.region)
                            else:
                                log_and_print(f"迁移文件 {obj.key} 校验失败", self.profile, self.region)

                        except Exception as e:
                            log_and_print(f"迁移文件 {obj.key} 失败: {str(e)}", self.profile, self.region)

                        processed_count += 1

                    except queue.Empty:
                        continue
                    except Exception as e:
                        log_and_print(f"处理文件时发生错误: {str(e)}", self.profile, self.region)

            # 启动生产者线程
            producer_thread = threading.Thread(target=producer)
            producer_thread.start()

            # 启动消费者线程池
            with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
                consumers = [executor.submit(consumer) for _ in range(max_workers)]

                # 等待所有消费者完成
                concurrent.futures.wait(consumers)

            # 等待生产者完成
            producer_thread.join()

            log_and_print(f"同步完成: 成功迁移 {success_count}/{processed_count} 个文件，跳过 {skipped_count} 个已存在的文件",
                         self.profile, self.region)

            return success_count > 0

        except Exception as e:
            log_and_print(f"同步过程中发生错误: {str(e)}", self.profile, self.region)
            return False

