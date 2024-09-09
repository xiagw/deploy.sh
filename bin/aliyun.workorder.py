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
from alibabacloud_tea_console.client import Client as ConsoleClient
from alibabacloud_tea_util.client import Client as UtilClient

class Sample:
    def __init__(self):
        pass

    @staticmethod
    def create_client() -> Workorder20210610Client:
        """
        使用AK&SK初始化账号Client
        @return: Client
        @throws Exception
        """
        # 工程代码泄露可能会导致 AccessKey 泄露，并威胁账号下所有资源的安全性。以下代码示例仅供参考。
        # 建议使用更安全的 STS 方式，更多鉴权访问方式请参见：https://help.aliyun.com/document_detail/378659.html。
        ## get key from aliyun profile
        aliyun_config = os.getenv('HOME') + "/.aliyun/config.json"
        with open(aliyun_config, 'r', encoding='utf8')as fp:
            data = json.load(fp)
            for i in data['profiles']:
                if i['name'] == 'flyh6':
                    profile_key_id = i['access_key_id']
                    profile_key_secret = i['access_key_secret']
                    break
        config = open_api_models.Config(
            # 必填，请确保代码运行环境设置了环境变量 ALIBABA_CLOUD_ACCESS_KEY_ID。,
            # access_key_id=os.environ['ALIBABA_CLOUD_ACCESS_KEY_ID'],
            access_key_id=profile_key_id,
            # 必填，请确保代码运行环境设置了环境变量 ALIBABA_CLOUD_ACCESS_KEY_SECRET。,
            # access_key_secret=os.environ['ALIBABA_CLOUD_ACCESS_KEY_SECRET']
            access_key_secret=profile_key_secret
        )
        # Endpoint 请参考 https://api.aliyun.com/product/Workorder
        config.endpoint = f'workorder.aliyuncs.com'
        return Workorder20210610Client(config)

    @staticmethod
    def get_product_list(
        args: List[str],
    ) -> None:
        client = Sample.create_client()
        list_products_request = workorder_20210610_models.ListProductsRequest()
        runtime = util_models.RuntimeOptions()
        try:
            resp = client.list_products_with_options(list_products_request, runtime)
            ConsoleClient.log(UtilClient.to_jsonstring(resp))
        except Exception as error:
            # 此处仅做打印展示，请谨慎对待异常处理，在工程项目中切勿直接忽略异常。
            # 错误 message
            print(error.message)
            # 诊断地址
            print(error.data.get("Recommend"))
            UtilClient.assert_as_string(error.message)

    @staticmethod
    async def get_product_list_async(
        args: List[str],
    ) -> None:
        client = Sample.create_client()
        list_products_request = workorder_20210610_models.ListProductsRequest()
        runtime = util_models.RuntimeOptions()
        try:
            resp = await client.list_products_with_options_async(list_products_request, runtime)
            ConsoleClient.log(UtilClient.to_jsonstring(resp))
        except Exception as error:
            # 此处仅做打印展示，请谨慎对待异常处理，在工程项目中切勿直接忽略异常。
            # 错误 message
            print(error.message)
            # 诊断地址
            print(error.data.get("Recommend"))
            UtilClient.assert_as_string(error.message)

    @staticmethod
    def create_workorder(
        args: List[str],
    ) -> None:
        client = Sample.create_client()
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
            # 此处仅做打印展示，请谨慎对待异常处理，在工程项目中切勿直接忽略异常。
            # 错误 message
            print(error.message)
            # 诊断地址
            print(error.data.get("Recommend"))
            UtilClient.assert_as_string(error.message)

    @staticmethod
    async def create_workorder_async(
        args: List[str],
    ) -> None:
        client = Sample.create_client()
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
            # 此处仅做打印展示，请谨慎对待异常处理，在工程项目中切勿直接忽略异常。
            # 错误 message
            print(error.message)
            # 诊断地址
            print(error.data.get("Recommend"))
            UtilClient.assert_as_string(error.message)

if __name__ == '__main__':
    if len(sys.argv[1:]) == 2:
        Sample.create_workorder(sys.argv[1:])
    else:
        Sample.get_product_list(sys.argv[1:])
