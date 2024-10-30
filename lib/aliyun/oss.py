import oss2
import re
from datetime import datetime
from .utils import (
    log_and_print,
    save_ids,
    read_ids,
    get_ids_file_path,
    get_data_dir  # 添加这个导入
)
from .config import Config
import json
import os
import concurrent.futures
from tqdm import tqdm
import queue
import threading
import logging
import time

class OSSManager:
    def __init__(self, access_key_id, access_key_secret, region, profile='default'):
        self.auth = oss2.Auth(access_key_id, access_key_secret)
        self._access_key_id = access_key_id
        self._access_key_secret = access_key_secret
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

    # 常见的压缩包和多媒体文件类型
    COMMON_FILE_TYPES = (
        # 压缩文件
        '.zip', '.tar', '.gz', '.bz2', '.xz', '.tar.gz', '.tar.bz2', '.tar.xz',
        # 音频文件
        '.amr', '.mp3', '.wma', '.m4a', '.m4b', '.m4p', '.m4r',
        # 视频文件
        '.mp4', '.avi', '.flv', '.wmv', '.mov', '.mkv', '.mpg', '.mpeg',
        '.m4v', '.3gp', '.3g2', '.asf', '.asx', '.m3u8', '.ts',
        # 图片文件
        '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.tif', '.svg',
        # 其他多媒体
        '.swf', '.ttf'
    )

    def _check_file_type(self, filename, file_types):
        """检查文件类型，忽略大小写"""
        return any(filename.lower().endswith(ext.lower()) for ext in file_types)

    def migrate_multimedia_files(self, source_bucket_name, dest_bucket_name,
                               file_types=COMMON_FILE_TYPES,
                               batch_size=100, max_workers=5, delete_source=False, prefix=''):
        """
        优化的流式同步处理方式迁移低频存储类型的多媒体文件，并可选择删除源文件

        特别注意：
        1. 使用临时文件存储待删除文件列表，避免内存溢出
        2. 分批处理删除操作
        3. 严格验证删除操作的结果
        """
        deleted_files_file = os.path.join(get_data_dir(), f'deleted_files_{source_bucket_name}.json')
        temp_delete_file = os.path.join(get_data_dir(), f'temp_delete_{source_bucket_name}.txt')

        try:
            # 记录开始时间
            start_message = f"开始同步多媒体文件, oss://{source_bucket_name} ==> oss://{dest_bucket_name}"
            if prefix:
                start_message += f", 子目录: {prefix}"

            logging.info(start_message)
            print(start_message)

            # 获取断点续传状态文件路径
            checkpoint_file = os.path.join(
                get_data_dir(),
                f'migrate_{source_bucket_name}_to_{dest_bucket_name}_{self.profile}_{self.region}.json'
            )

            # 读取断点续传状态
            checkpoint = {}
            if os.path.exists(checkpoint_file):
                try:
                    with open(checkpoint_file, 'r', encoding='utf-8') as f:
                        checkpoint = json.load(f)
                        if checkpoint.get('prefix') != prefix:  # 如果前缀变化，重置断点
                            checkpoint = {}
                except Exception as e:
                    logging.error(f"读取断点文件失败: {str(e)}")
                    checkpoint = {}

            # 获取上次的marker和统计数据
            marker = checkpoint.get('marker', '')
            processed_count = checkpoint.get('processed_count', 0)
            success_count = checkpoint.get('success_count', 0)
            skipped_count = checkpoint.get('skipped_count', 0)
            total_files = checkpoint.get('total_files', 0)
            last_update_time = checkpoint.get('last_update_time', '')

            if marker:
                resume_message = (
                    f"从断点继续迁移\n"
                    f"上次更新时间: {last_update_time}\n"
                    f"已处理: {processed_count} 个文件\n"
                    f"已成功: {success_count} 个文件\n"
                    f"已跳过: {skipped_count} 个文件"
                )
                logging.info(resume_message)
                print(resume_message)

            # 记录开始时间
            start_time = datetime.now()

            source_bucket = oss2.Bucket(self.auth, self.endpoint, source_bucket_name)
            dest_bucket = oss2.Bucket(self.auth, self.endpoint, dest_bucket_name)

            file_queue = queue.Queue(maxsize=batch_size * 2)
            producer_done = threading.Event()

            # 添加删除队列
            delete_queue = queue.Queue(maxsize=batch_size * 2)
            files_to_delete = set()  # 使用集合存储待删除的文件

            def save_checkpoint():
                """保存断点续传状态"""
                try:
                    checkpoint_data = {
                        'marker': marker,
                        'processed_count': processed_count,
                        'success_count': success_count,
                        'skipped_count': skipped_count,
                        'total_files': total_files,
                        'prefix': prefix,
                        'last_update_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    }
                    with open(checkpoint_file, 'w', encoding='utf-8') as f:
                        json.dump(checkpoint_data, f, indent=2, ensure_ascii=False)
                    logging.debug(f"断点状态已保存: {checkpoint_file}")
                except Exception as e:
                    logging.error(f"保存断点状态失败: {str(e)}")

            def producer():
                nonlocal marker, skipped_count, total_files
                file_batch = []

                try:
                    while True:
                        objects = source_bucket.list_objects(prefix=prefix, marker=marker, max_keys=1000)

                        for obj in objects.object_list:
                            if self._check_file_type(obj.key, file_types):
                                file_batch.append(obj)
                                total_files += 1

                                if len(file_batch) >= batch_size:
                                    process_file_batch(file_batch)
                                    file_batch = []
                                    # 更新marker并保存断点
                                    marker = obj.key
                                    save_checkpoint()

                        if not objects.is_truncated:
                            if file_batch:
                                process_file_batch(file_batch)
                            break
                        marker = objects.next_marker
                        save_checkpoint()  # 每次更新marker时保存断点

                except Exception as e:
                    logging.error(f"扫描文件时发生错误: {str(e)}")
                    save_checkpoint()  # 发生错误时也保存断点
                finally:
                    producer_done.set()

            # 将计数器声明为线程共享变量
            success_count = 0
            processed_count = 0
            skipped_count = 0
            total_files = 0

            # 添加线程锁来保护计数器
            counter_lock = threading.Lock()

            def save_files_to_delete(files):
                """将待删除文件写入临时文件"""
                try:
                    with open(temp_delete_file, 'a', encoding='utf-8') as f:
                        for file_key in files:
                            f.write(f"{file_key}\n")
                except Exception as e:
                    logging.error(f"保存待删除文件列表失败: {str(e)}")

            def process_file_batch(file_batch):
                """批量处理文件检查"""
                nonlocal success_count, skipped_count, total_files, processed_count
                batch_files_to_delete = set()  # 本批次待删除的文件

                try:
                    source_headers = {}
                    filtered_files = []

                    # 第一步：筛选IA文件
                    for obj in file_batch:
                        try:
                            if self._check_file_type(obj.key, file_types):
                                headers = source_bucket.head_object(obj.key)
                                storage_class = headers.headers.get('x-oss-storage-class', 'Standard')

                                if storage_class == 'IA':
                                    source_headers[obj.key] = headers
                                    filtered_files.append(obj)
                                    with counter_lock:
                                        processed_count += 1  # 记录IA文件总数
                                    logging.info(f"找到IA文件: oss://{source_bucket_name}/{obj.key}")

                                    # 直接放入队列进行复制，不再检查目标
                                    file_queue.put((obj, storage_class, headers.headers.get('etag', '').strip('"')))
                                    # logging.info(f"文件已加入队列: oss://{source_bucket_name}/{obj.key}")
                        except Exception as e:
                            logging.error(f"文件: {obj.key} -> 获取元数据失败: {str(e)}")

                    if delete_source and batch_files_to_delete:
                        save_files_to_delete(batch_files_to_delete)

                except Exception as e:
                    logging.error(f"批量处理失败: {str(e)}")

            def consumer():
                nonlocal success_count, skipped_count
                local_files_to_delete = set()

                while not (producer_done.is_set() and file_queue.empty()):
                    try:
                        obj_info = file_queue.get(timeout=1)
                        obj, storage_class, source_etag = obj_info

                        try:
                            copy_success = False
                            # 在复制前检查目标文件
                            try:
                                dest_obj = dest_bucket.head_object(obj.key)
                                dest_etag = dest_obj.headers.get('etag', '').strip('"')

                                if dest_etag == source_etag:
                                    with counter_lock:
                                        skipped_count += 1
                                        success_count += 1
                                    if delete_source:
                                        local_files_to_delete.add(obj.key)
                                    continue
                            except oss2.exceptions.NoSuchKey:
                                pass  # 忽略目标文件不存在的404错误日志

                            # 执行复制
                            dest_bucket.copy_object(
                                source_bucket_name,
                                obj.key,
                                obj.key,
                                headers={
                                    'x-oss-storage-class': storage_class,
                                    'x-oss-metadata-directive': 'COPY',
                                }
                            )

                            # 验证复制是否成功
                            try:
                                dest_obj = dest_bucket.head_object(obj.key)
                                dest_etag = dest_obj.headers.get('etag', '').strip('"')
                                if dest_etag == source_etag:
                                    copy_success = True
                                    with counter_lock:
                                        success_count += 1
                                    if delete_source:
                                        local_files_to_delete.add(obj.key)
                                    logging.info(f"文件: oss://{source_bucket_name}/{obj.key} -> oss://{dest_bucket_name}/{obj.key} 迁移成功")
                            except Exception as e:
                                logging.error(f"验证复制结果失败: oss://{source_bucket_name}/{obj.key} -> oss://{dest_bucket_name}/{obj.key} -> {str(e)}")
                        except Exception as e:
                            logging.error(f"复制文件失败: oss://{source_bucket_name}/{obj.key} -> oss://{dest_bucket_name}/{obj.key} -> {str(e)}")

                        # 定期保存待删除文件列表
                        if delete_source and len(local_files_to_delete) >= batch_size:
                            save_files_to_delete(local_files_to_delete)
                            local_files_to_delete.clear()

                    except queue.Empty:
                        continue

                # 保存剩余的待删除文件
                if delete_source and local_files_to_delete:
                    save_files_to_delete(local_files_to_delete)

            # 启动生产者线程
            producer_thread = threading.Thread(target=producer)
            producer_thread.start()

            # 启动消费者线程池
            with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
                consumers = [executor.submit(consumer) for _ in range(max_workers)]
                concurrent.futures.wait(consumers)

            producer_thread.join()

            # 计算耗时
            end_time = datetime.now()
            duration = end_time - start_time
            hours, remainder = divmod(duration.total_seconds(), 3600)
            minutes, seconds = divmod(remainder, 60)

            # 格式化耗时字符串
            duration_str = []
            if hours > 0:
                duration_str.append(f"{int(hours)}小时")
            if minutes > 0:
                duration_str.append(f"{int(minutes)}分钟")
            duration_str.append(f"{int(seconds)}秒")

            end_message = (
                f"同步完成: oss://{source_bucket_name} ==> oss://{dest_bucket_name}\n"
                f"成功迁移: {success_count}/{processed_count} 个文件\n"
                f"跳过已存在: {skipped_count} 个文件\n"
                f"总耗时: {' '.join(duration_str)}"
                + (f"\n已删除源文件" if delete_source else "")
            )

            logging.info(end_message)
            print(end_message)

            # 迁移完成后删除断点文件
            if os.path.exists(checkpoint_file):
                try:
                    os.remove(checkpoint_file)
                    logging.info("迁移完成，已删除断点文件")
                except Exception as e:
                    logging.error(f"删除断点文件失败: {str(e)}")

            # 迁移完成后，不需要再次写入文件，因为已经在删除时写入了
            if delete_source:
                logging.info(f"已删除文件信息已保存到 {deleted_files_file}")

            # 在所有复制完成后，处理文件删除
            if delete_source and os.path.exists(temp_delete_file):
                deleted_count = 0
                failed_deletes = []

                try:
                    with open(temp_delete_file, 'r', encoding='utf-8') as f:
                        files_to_delete = set(line.strip() for line in f)

                    # 分批删除文件
                    batch = []
                    for file_key in files_to_delete:
                        batch.append(file_key)
                        if len(batch) >= batch_size:
                            try:
                                # 批量删除
                                source_bucket.batch_delete_objects(batch)
                                # 验证删除
                                for key in batch:
                                    try:
                                        source_bucket.head_object(key)
                                        failed_deletes.append(key)
                                    except oss2.exceptions.NoSuchKey:
                                        deleted_count += 1
                                    except Exception as e:
                                        logging.error(f"验证删除失败: oss://{source_bucket_name}/{key} -> {str(e)}")
                            except Exception as e:
                                logging.error(f"批量删除失败: {str(e)}")
                                failed_deletes.extend(batch)
                            batch = []

                    # 处理剩余的文件
                    if batch:
                        try:
                            source_bucket.batch_delete_objects(batch)
                            for key in batch:
                                try:
                                    source_bucket.head_object(key)
                                    failed_deletes.append(key)
                                except oss2.exceptions.NoSuchKey:
                                    deleted_count += 1
                                except Exception as e:
                                    logging.error(f"验证删除失败: oss://{source_bucket_name}/{key} -> {str(e)}")
                        except Exception as e:
                            logging.error(f"批量删除失败: {str(e)}")
                            failed_deletes.extend(batch)

                    # 记录删除结果
                    if failed_deletes:
                        logging.error(f"以下文件删除失败: {failed_deletes}")
                    logging.info(f"成功删除 {deleted_count} 个文件")

                except Exception as e:
                    logging.error(f"处理文件删除时发生错误: {str(e)}")
                finally:
                    # 清理临时文件
                    try:
                        os.remove(temp_delete_file)
                    except Exception as e:
                        logging.error(f"删除临时文件失败: {str(e)}")

            return success_count > 0

        except Exception as e:
            save_checkpoint()  # 发生异常时保存断点
            current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            error_message = f"[{current_time}] 同步过程中发生错误: {str(e)}"
            logging.error(error_message)
            print(error_message)
            return False

    def restore_files(self, source_bucket_name, dest_bucket_name):
        """从目标存储桶恢复已删除的文件到源存储桶"""
        deleted_files_file = os.path.join(get_data_dir(), f'deleted_files_{source_bucket_name}.json')
        if not os.path.exists(deleted_files_file):
            logging.error(f"未找到已删除文件信息文件: {deleted_files_file}")
            return False

        try:
            with open(deleted_files_file, 'r', encoding='utf-8') as f:
                deleted_files = json.load(f)

            source_bucket = oss2.Bucket(self.auth, self.endpoint, source_bucket_name)
            dest_bucket = oss2.Bucket(self.auth, self.endpoint, dest_bucket_name)

            for file_key in deleted_files:
                try:
                    # 从目标存储桶复制回源存储桶
                    source_bucket.copy_object(dest_bucket_name, file_key, file_key)
                    logging.info(f"文件: {file_key} 已从目标存储桶恢复到源存储桶")
                except Exception as e:
                    logging.error(f"文件: {file_key} 恢复失败: {str(e)}")

            return True
        except Exception as e:
            logging.error(f"恢复文件时发生错误: {str(e)}")
            return False

