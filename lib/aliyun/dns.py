from alibabacloud_alidns20150109.client import Client as Alidns20150109Client
from alibabacloud_tea_openapi import models as open_api_models
from alibabacloud_alidns20150109 import models as alidns_20150109_models
from .utils import log_and_print, save_ids
from .config import Config
import json

class DNSManager:
    def __init__(self, access_key_id, access_key_secret, region, profile):
        config = open_api_models.Config(
            access_key_id=access_key_id,
            access_key_secret=access_key_secret
        )
        config.endpoint = f'alidns.{region}.aliyuncs.com'
        self.client = Alidns20150109Client(config)
        self.profile = profile
        self.region = region

    def get_domain_record(self, domain, rr):
        request = alidns_20150109_models.DescribeDomainRecordsRequest(
            domain_name=domain,
            rrkey_word=rr
        )

        try:
            response = self.client.describe_domain_records(request)
            records = response.body.domain_records.record
            if records:
                return records[0].record_id
            return None
        except Exception as e:
            log_and_print(f"查询 DNS 记录失败: {str(e)}")
            return None

    def add_or_update_record(self, domain, rr, ip):
        record_id = self.get_domain_record(domain, rr)

        if record_id:
            request = alidns_20150109_models.UpdateDomainRecordRequest(
                record_id=record_id,
                rr=rr,
                type="A",
                value=ip
            )
        else:
            request = alidns_20150109_models.AddDomainRecordRequest(
                domain_name=domain,
                rr=rr,
                type="A",
                value=ip
            )

        try:
            if record_id:
                response = self.client.update_domain_record(request)
            else:
                response = self.client.add_domain_record(request)
            record_id = response.body.record_id
            log_and_print(f"DNS 记录{'更新' if record_id else '添加'}成功，记录 ID: {record_id}")
            save_ids(self.profile, self.region, dns_record={"id": record_id, "domain": domain, "rr": rr})
            return record_id
        except Exception as e:
            if 'DomainRecordDuplicate' in str(e):
                log_and_print(f"DNS 记录 {rr}.{domain} 已存在且值相同，无需更新")
                return record_id
            else:
                log_and_print(f"{'更新' if record_id else '添加'} DNS 记录失败: {str(e)}")
                return None

    def delete_record(self, domain, rr=None, record_id=None):
        if not record_id:
            record_id = self.get_domain_record(domain, rr)

        if record_id:
            request = alidns_20150109_models.DeleteDomainRecordRequest(
                record_id=record_id
            )

            try:
                self.client.delete_domain_record(request)
                log_and_print(f"DNS 记录 ID {record_id} 已成功删除")
                return True
            except Exception as e:
                log_and_print(f"删除 DNS 记录失败: {str(e)}")
                return False
        else:
            log_and_print(f"未找到要删除的 DNS 记录")
            return False

    def create_dns(self, domain, domain_rr, domain_value=None):
        if domain_value:
            public_ip = domain_value
        else:
            from .ecs import ECSManager
            ecs_manager = ECSManager(Config.ACCESS_KEY_ID, Config.ACCESS_KEY_SECRET, self.region, self.profile)
            instance_ids = ecs_manager.list_instances()
            if not instance_ids:
                log_and_print("未找到已创建的 ECS 实例 ID")
                log_and_print("请提供 --domain-value 参数指定 IP 地址，或先创建 ECS 实例")
                return
            instance_id = instance_ids[-1]['InstanceId']
            public_ip = ecs_manager.get_instance_public_ip(instance_id)
            if not public_ip:
                log_and_print(f"无法获取实例 {instance_id} 的公网 IP")
                log_and_print("请提供 --domain-value 参数指定 IP 地址")
                return

        record_id = self.add_or_update_record(domain, domain_rr, public_ip)
        if record_id:
            log_and_print(f"DNS 记录创建或更新成功：{domain_rr}.{domain} -> {public_ip}")
        else:
            log_and_print(f"添加或更新 DNS 记录失败：{domain_rr}.{domain} -> {public_ip}")

    def delete_dns(self, domain, domain_rr, record_id=None):
        if self.delete_record(domain, domain_rr, record_id):
            log_and_print(f"DNS 记录 {domain_rr}.{domain} 已成功删除")
            return True
        else:
            log_and_print(f"删除 DNS 记录失败")
            return False

    def list_dns_records(self):
        request = alidns_20150109_models.DescribeDomainsRequest()

        try:
            response = self.client.describe_domains(request)
            domains = response.body.domains.domain

            all_records = []

            for domain in domains:
                domain_name = domain.domain_name
                records_request = alidns_20150109_models.DescribeDomainRecordsRequest(
                    domain_name=domain_name
                )

                try:
                    records_response = self.client.describe_domain_records(records_request)
                    records = records_response.body.domain_records.record

                    log_and_print(f"域名 {domain_name} 的 DNS 记录：")
                    for record in records:
                        record_info = {
                            'RecordId': record.record_id,
                            'RR': record.rr,
                            'Type': record.type,
                            'Value': record.value,
                            'TTL': record.ttl
                        }
                        all_records.append(record_info)
                        log_and_print(f"记录 ID: {record.record_id}")
                        log_and_print(f"主机记录: {record.rr}")
                        log_and_print(f"记录类型: {record.type}")
                        log_and_print(f"记录值: {record.value}")
                        log_and_print(f"TTL: {record.ttl}")
                        log_and_print("---")

                except Exception as e:
                    log_and_print(f"获取域名 {domain_name} 的 DNS 记录失败: {str(e)}")

            if all_records:
                # 保存 DNS 记录信息
                save_ids(self.profile, self.region, dns=all_records)
                log_and_print(f"共找到 {len(all_records)} 条 DNS 记录")
            else:
                log_and_print("未找到任何 DNS 记录")

        except Exception as e:
            log_and_print(f"获取域名列表失败: {str(e)}")

    def update_dns(self, domain, rr, value, type="A"):
        try:
            record_id = self.get_domain_record(domain, rr)
            if not record_id:
                log_and_print(f"未找到要更新的 DNS 记录：{rr}.{domain}")
                return False

            request = alidns_20150109_models.UpdateDomainRecordRequest(
                record_id=record_id,
                rr=rr,
                type=type,
                value=value
            )
            response = self.client.update_domain_record(request)
            log_and_print(f"DNS 记录更新成功：{rr}.{domain} -> {value}")
            save_ids(self.profile, self.region, dns_record={"id": record_id, "domain": domain, "rr": rr})
            return True
        except Exception as e:
            log_and_print(f"更新 DNS 记录失败: {str(e)}")
            return False

    # 其他 DNS 相关方法...
