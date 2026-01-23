# -*- coding: utf-8 -*-
import logging
import os

def setup_debug_logging(log_file='debug.log'):
    """设置调试日志"""
    log_dir = os.path.dirname(log_file)
    if log_dir and not os.path.exists(log_dir):
        os.makedirs(log_dir)

    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler()
        ]
    )

def debug_print(message):
    """打印调试信息"""
    logging.debug(message)
