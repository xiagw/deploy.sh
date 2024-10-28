# -*- coding: utf-8 -*-
# tests/test_oss.py
import unittest
from unittest.mock import Mock, patch, MagicMock
import os
import sys
import logging
import time
import threading
import queue
import oss2

# 设置日志级别
logging.basicConfig(level=logging.DEBUG)

# 添加项目根目录到 Python 路径
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from aliyun.oss import OSSManager

class TestOSSManager(unittest.TestCase):
    def setUp(self):
        """测试前的准备工作"""
        self.timeout = 5  # 设置测试超时时间为5秒

    @patch('oss2.Auth')
    @patch('oss2.Bucket')
    def test_migrate_multimedia_files_simple(self, mock_bucket, mock_auth):
        """简化版的文件迁移测试"""
        # 配置日志
        logging.debug("开始测试文件迁移功能")

        # 初始化 OSSManager
        oss_manager = OSSManager('fake_id', 'fake_secret', 'region', 'default')

        # 模拟文件列表
        mock_obj = Mock()
        mock_obj.key = 'test.mp4'
        mock_list = Mock()
        mock_list.object_list = [mock_obj]
        mock_list.is_truncated = False

        # 模拟源文件信息
        source_headers = Mock()
        source_headers.headers = {
            'x-oss-storage-class': 'IA',
            'etag': '"123"'
        }

        # 模拟目标文件信息
        dest_headers = Mock()
        dest_headers.headers = {
            'x-oss-storage-class': 'IA',
            'etag': '"456"'  # 不同的ETag触发复制
        }

        # 模拟复制后的目标文件信息
        copied_headers = Mock()
        copied_headers.headers = {
            'x-oss-storage-class': 'IA',
            'etag': '"123"'  # 复制后与源文件相同
        }

        # 配置mock_bucket的行为
        def mock_list_objects(*args, **kwargs):
            logging.debug("调用 list_objects")
            return mock_list

        def mock_head_object(key):
            logging.debug(f"调用 head_object，key={key}")
            if not hasattr(mock_head_object, 'call_count'):
                mock_head_object.call_count = 0
            mock_head_object.call_count += 1

            if mock_head_object.call_count == 1:
                logging.debug("返回源文件信息")
                return source_headers
            elif mock_head_object.call_count == 2:
                logging.debug("返回目标文件初始信息")
                return dest_headers
            else:
                logging.debug("返回复制后的文件信息")
                return copied_headers

        def mock_copy_object(source_bucket, source_key, target_key, **kwargs):
            logging.debug(f"调用 copy_object: {source_bucket}/{source_key} -> {target_key}")
            response = Mock()
            response.status = 200
            return response

        # 设置mock对象的行为
        mock_bucket.return_value.list_objects = Mock(side_effect=mock_list_objects)
        mock_bucket.return_value.head_object = Mock(side_effect=mock_head_object)
        mock_bucket.return_value.copy_object = Mock(side_effect=mock_copy_object)

        # 执行测试
        logging.debug("开始执行migrate_multimedia_files")
        result = oss_manager.migrate_multimedia_files(
            'source-bucket',
            'dest-bucket',
            batch_size=1,
            max_workers=1
        )

        # 验证结果
        logging.debug(f"测试结果: {result}")
        self.assertTrue(result)

        # 验证调用
        mock_bucket.return_value.list_objects.assert_called_once()
        self.assertGreater(mock_bucket.return_value.head_object.call_count, 0)
        mock_bucket.return_value.copy_object.assert_called_once()

    @patch('oss2.Auth')
    @patch('oss2.Bucket')
    def test_migrate_multimedia_files_with_delete_simple(self, mock_bucket, mock_auth):
        """简化版的文件迁移并删除测试"""
        logging.debug("开始测试文件迁移并删除功能")

        oss_manager = OSSManager('fake_id', 'fake_secret', 'region', 'default')

        # 模拟文件列表
        mock_obj = Mock()
        mock_obj.key = 'test.mp4'
        mock_list = Mock()
        mock_list.object_list = [mock_obj]
        mock_list.is_truncated = False

        # 配置mock_bucket的行为
        def mock_list_objects(*args, **kwargs):
            logging.debug("调用 list_objects")
            return mock_list

        def mock_head_object(key):
            logging.debug(f"调用 head_object，key={key}")
            headers = Mock()
            headers.headers = {
                'x-oss-storage-class': 'IA',
                'etag': '"123"'
            }
            return headers

        def mock_copy_object(*args, **kwargs):
            logging.debug("调用 copy_object")
            response = Mock()
            response.status = 200
            return response

        def mock_delete_object(key):
            logging.debug(f"调用 delete_object，key={key}")
            response = Mock()
            response.status = 204
            return response

        # 设置mock对象的行为
        mock_bucket.return_value.list_objects = Mock(side_effect=mock_list_objects)
        mock_bucket.return_value.head_object = Mock(side_effect=mock_head_object)
        mock_bucket.return_value.copy_object = Mock(side_effect=mock_copy_object)
        mock_bucket.return_value.delete_object = Mock(side_effect=mock_delete_object)

        # 执行测试
        result = oss_manager.migrate_multimedia_files(
            'source-bucket',
            'dest-bucket',
            batch_size=1,
            max_workers=1,
            delete_source=True
        )

        # 验证结果
        logging.debug(f"测试结果: {result}")
        self.assertTrue(result)

        # 验证调用
        mock_bucket.return_value.list_objects.assert_called_once()
        self.assertGreater(mock_bucket.return_value.head_object.call_count, 0)
        mock_bucket.return_value.copy_object.assert_called_once()
        mock_bucket.return_value.delete_object.assert_called_once_with(mock_obj.key)

    def test_migrate_multimedia_files_error_handling(self):
        """测试文件迁移错误处理"""
        oss_manager = OSSManager('fake_id', 'fake_secret', 'region', 'default')

        # 测试无效的存储桶名称
        result = oss_manager.migrate_multimedia_files(
            '',  # 无效的源存储桶名称
            'dest-bucket',
            batch_size=1,
            max_workers=1
        )
        self.assertFalse(result)

        # 测试源存储桶和目标存储桶相同
        result = oss_manager.migrate_multimedia_files(
            'same-bucket',
            'same-bucket',
            batch_size=1,
            max_workers=1
        )
        self.assertFalse(result)

    def tearDown(self):
        """测试后的清理工作"""
        # 等待所有线程结束
        main_thread = threading.current_thread()
        for thread in threading.enumerate():
            if thread is not main_thread:
                thread.join(timeout=1)

if __name__ == '__main__':
    unittest.main()
