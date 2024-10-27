from alibabacloud_cdn20180510.client import Client as Cdn20180510Client
from alibabacloud_tea_openapi import models as open_api_models
from alibabacloud_cdn20180510 import models as cdn_models
from .utils import log_and_print
from .config import Config

class CDNManager:
    def __init__(self, access_key_id, access_key_secret):
        config = open_api_models.Config(
            access_key_id=access_key_id,
            access_key_secret=access_key_secret
        )
        config.endpoint = 'cdn.aliyuncs.com'
        self.client = Cdn20180510Client(config)

    def create_domain(self, domain_name, origin_domain):
        if not origin_domain:
            log_and_print("错误: 未提供源域名")
            return False

        source_type = 'oss' if '.oss-' in origin_domain else 'domain'
        sources = [
            {
                "content": origin_domain,
                "type": source_type,
                "priority": "20",
                "port": 80
            }
        ]

        add_cdn_domain_request = cdn_models.AddCdnDomainRequest(
            domain_name=domain_name,
            cdn_type="web",
            sources=str(sources)
        )

        try:
            response = self.client.add_cdn_domain(add_cdn_domain_request)
            log_and_print(f"CDN 域名 '{domain_name}' 创建成功，源站: {origin_domain}，类型: {source_type}")
            return True
        except Exception as e:
            log_and_print(f"创建 CDN 域名失败: {str(e)}")
            return False

    def delete_domain(self, domain_name):
        delete_cdn_domain_request = cdn_models.DeleteCdnDomainRequest(
            domain_name=domain_name
        )

        try:
            response = self.client.delete_cdn_domain(delete_cdn_domain_request)
            log_and_print(f"CDN 域名 '{domain_name}' 删除成功")
            return True
        except Exception as e:
            log_and_print(f"删除 CDN 域名失败: {str(e)}")
            return False

    def list_domains(self):
        try:
            request = cdn_models.DescribeUserDomainsRequest(
                page_size=50,
                page_number=1
            )
            response = self.client.describe_user_domains(request)
            domains = response.body.domains.page_data

            if not domains:
                log_and_print("未找到任何 CDN 域名")
                return

            log_and_print("CDN 域名列表：")
            for domain in domains:
                log_and_print(f"域名: {domain.domain_name}")
                log_and_print(f"状态: {domain.domain_status}")
                log_and_print(f"CNAME: {domain.cname}")
                log_and_print(f"创建时间: {domain.gmt_created}")
                log_and_print("---")

            log_and_print(f"共找到 {len(domains)} 个 CDN 域名")
        except Exception as e:
            log_and_print(f"列出 CDN 域名失败: {str(e)}")

    def update_domain(self, domain_name, origin_domain=None, cdn_type=None):
        try:
            request = cdn_models.ModifyCdnDomainRequest(
                domain_name=domain_name
            )

            if origin_domain:
                source_type = 'oss' if '.oss-' in origin_domain else 'domain'
                sources = [
                    {
                        "content": origin_domain,
                        "type": source_type,
                        "priority": "20",
                        "port": 80
                    }
                ]
                request.sources = str(sources)

            if cdn_type:
                request.cdn_type = cdn_type

            response = self.client.modify_cdn_domain(request)
            log_and_print(f"CDN 域名 '{domain_name}' 更新成功")
            return True
        except Exception as e:
            log_and_print(f"更新 CDN 域名失败: {str(e)}")
            return False

    # 其他 CDN 相关方法...
