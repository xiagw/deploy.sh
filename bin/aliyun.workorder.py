# -*- coding: utf-8 -*-
# This file is auto-generated, don't edit it. Thanks.
import os
import sys
import json

from typing import List

from alibabacloud_workorder20210610.client import Client as Workorder20210610Client
from alibabacloud_tea_openapi import models as open_api_models
from alibabacloud_workorder20210610 import models as workorder_20210610_models
from alibabacloud_tea_util import models as util_models
from alibabacloud_tea_util.client import Client as UtilClient

## get aliyun profile
aliyun_config = os.getenv('HOME') + "/.aliyun/config.json"
with open(aliyun_config, 'r', encoding='utf8')as fp:
    data = json.load(fp)
    for i in data['profiles']:
        if i['name'] == 'flyh6':
            aliyun_key = i['access_key_id']
            aliyun_secret = i['access_key_secret']
            break

class Sample:
    def __init__(self):
        pass

    def display_info():
        print("""
        11864 云解析DNS
        18700 负载均衡
        18422 内容分发网络CDN
        9457  对象存储OSS
        7160  云服务器ECS
        18474 容器服务Kubernetes版
        10293 财务
        25352 备案
        78102 云控制API
        18528 函数计算
        18771 弹性容器实例
        """)

    @staticmethod
    def create_client(
        access_key_id: str,
        access_key_secret: str,
    ) -> Workorder20210610Client:
        """
        使用AK&SK初始化账号Client
        @param access_key_id:
        @param access_key_secret:
        @return: Client
        @throws Exception
        """
        config = open_api_models.Config(
            # 必填，您的 AccessKey ID,
            access_key_id=aliyun_key,
            # 必填，您的 AccessKey Secret,
            access_key_secret=aliyun_secret
        )
        # Endpoint 请参考 https://api.aliyun.com/product/Workorder
        config.endpoint = f'workorder.aliyuncs.com'
        return Workorder20210610Client(config)

    @staticmethod
    def get_product_list(
        args: List[str],
    ) -> None:
        client = Sample.create_client(aliyun_key, aliyun_secret)
        list_products_request = workorder_20210610_models.ListProductsRequest()
        runtime = util_models.RuntimeOptions()
        try:
            # 复制代码运行请自行打印 API 的返回值
            client.list_products_with_options(list_products_request, runtime)
        except Exception as error:
            # 如有需要，请打印 error
            UtilClient.assert_as_string(error.message)

    @staticmethod
    def main(
        args: List[str],
    ) -> None:
        if len(args) != 2:
            Sample.display_info()
            # Sample.get_product_list(sys.argv[1:])
            return
        # 请确保代码运行环境设置了环境变量 ALIBABA_CLOUD_ACCESS_KEY_ID 和 ALIBABA_CLOUD_ACCESS_KEY_SECRET。
        # 工程代码泄露可能会导致 AccessKey 泄露，并威胁账号下所有资源的安全性。以下代码示例使用环境变量获取 AccessKey 的方式进行调用，仅供参考，建议使用更安全的 STS 方式，更多鉴权访问方式请参见：https://help.aliyun.com/document_detail/378659.html
        # client = Sample.create_client(os.environ['ALIBABA_CLOUD_ACCESS_KEY_ID'], os.environ['ALIBABA_CLOUD_ACCESS_KEY_SECRET'])
        client = Sample.create_client(aliyun_key, aliyun_secret)
        create_ticket_request = workorder_20210610_models.CreateTicketRequest(
            category_id=args[0],
            description=args[1],
            severity=2,
            title='',
            email=''
        )
        runtime = util_models.RuntimeOptions()
        try:
            # 复制代码运行请自行打印 API 的返回值
            client.create_ticket_with_options(create_ticket_request, runtime)
        except Exception as error:
            # 如有需要，请打印 error
            UtilClient.assert_as_string(error.message)

    @staticmethod
    async def main_async(
        args: List[str],
    ) -> None:
        # 请确保代码运行环境设置了环境变量 ALIBABA_CLOUD_ACCESS_KEY_ID 和 ALIBABA_CLOUD_ACCESS_KEY_SECRET。
        # 工程代码泄露可能会导致 AccessKey 泄露，并威胁账号下所有资源的安全性。以下代码示例使用环境变量获取 AccessKey 的方式进行调用，仅供参考，建议使用更安全的 STS 方式，更多鉴权访问方式请参见：https://help.aliyun.com/document_detail/378659.html
        client = Sample.create_client(aliyun_key, aliyun_secret)
        create_ticket_request = workorder_20210610_models.CreateTicketRequest(
            category_id=args[0],
            description=args[1],
            severity=2,
            title='',
            email=''
        )
        runtime = util_models.RuntimeOptions()
        try:
            # 复制代码运行请自行打印 API 的返回值
            await client.create_ticket_with_options_async(create_ticket_request, runtime)
        except Exception as error:
            # 如有需要，请打印 error
            UtilClient.assert_as_string(error.message)

if __name__ == '__main__':
    Sample.main(sys.argv[1:])
    # Sample.get_product_list(sys.argv[1:])
