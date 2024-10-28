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
        logging.debug("开始测试文件迁移功能")

        # 初始化 OSSManager
        oss_manager = OSSManager('fake_id', 'fake_secret', 'region', 'default')

        # 模拟文件列表
        mock_obj = Mock()
        mock_obj.key = 'test.mp4'
        mock_list = Mock()
        mock_list.object_list = [mock_obj]
        mock_list.is_truncated = False

        # 模拟源文件和目标文件的状态
        head_object_responses = {}
        head_object_responses['source'] = Mock(headers={
            'x-oss-storage-class': 'IA',
            'etag': '"123"'
        })
        head_object_responses['dest_before'] = Mock(headers={
            'x-oss-storage-class': 'IA',
            'etag': '"456"'  # 不同的ETag触发复制
        })
        head_object_responses['dest_after'] = Mock(headers={
            'x-oss-storage-class': 'IA',
            'etag': '"123"'  # 复制后与源文件相同
        })

        # 模拟head_object的行为
        head_object_calls = []
        def mock_head_object(key):
            head_object_calls.append(key)
            if len(head_object_calls) == 1:
                return head_object_responses['source']
            elif len(head_object_calls) == 2:
                return head_object_responses['dest_before']
            return head_object_responses['dest_after']

        # 模拟copy_object的行为
        def mock_copy_object(*args, **kwargs):
            response = Mock()
            response.status = 200
            return response

        # 设置mock对象
        mock_bucket.return_value.list_objects.return_value = mock_list
        mock_bucket.return_value.head_object = Mock(side_effect=mock_head_object)
        mock_bucket.return_value.copy_object = Mock(side_effect=mock_copy_object)

        # 执行测试
        result = oss_manager.migrate_multimedia_files(
            'source-bucket',
            'dest-bucket',
            batch_size=1,
            max_workers=1
        )

        # 验证结果
        self.assertTrue(result)
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
        mock_bucket.return_value.list_objects.return_value = mock_list

        # 模拟源文件和目标文件的状态
        head_object_responses = {}
        head_object_responses['source'] = Mock(headers={
            'x-oss-storage-class': 'IA',
            'etag': '"123"'
        })
        head_object_responses['dest_before'] = Mock(headers={
            'x-oss-storage-class': 'IA',
            'etag': '"456"'  # 不同的ETag触发复制
        })
        head_object_responses['dest_after'] = Mock(headers={
            'x-oss-storage-class': 'IA',
            'etag': '"123"'  # 复制后与源文件相同
        })

        # 模拟head_object的行为
        head_object_calls = []
        def mock_head_object(key):
            head_object_calls.append(key)
            if len(head_object_calls) == 1:
                return head_object_responses['source']
            elif len(head_object_calls) == 2:
                return head_object_responses['dest_before']
            return head_object_responses['dest_after']

        # 模拟copy_object的行为
        def mock_copy_object(*args, **kwargs):
            response = Mock()
            response.status = 200
            return response

        # 模拟delete_object的行为
        def mock_delete_object(key):
            response = Mock()
            response.status = 204
            return response

        # 设置mock对象
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
        self.assertTrue(result)
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
