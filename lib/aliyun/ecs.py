from alibabacloud_ecs20140526.client import Client as Ecs20140526Client
from alibabacloud_tea_openapi import models as open_api_models
from alibabacloud_ecs20140526 import models as ecs_20140526_models
from alibabacloud_tea_util import models as util_models
from alibabacloud_tea_util.client import Client as UtilClient
from .utils import log_and_print, save_ids
from .config import Config
import json
import time

class ECSManager:
    def __init__(self, access_key_id, access_key_secret, region, profile):
        config = open_api_models.Config(
            access_key_id=access_key_id,
            access_key_secret=access_key_secret
        )
        config.endpoint = f'ecs.{region}.aliyuncs.com'
        self.client = Ecs20140526Client(config)
        self.region = region
        self.profile = profile

    def create_instance(self, vswitch_id, security_group_id, key_pair_name):
        try:
            system_disk = ecs_20140526_models.CreateInstanceRequestSystemDisk(
                category='cloud_efficiency'
            )
            create_instance_request = ecs_20140526_models.CreateInstanceRequest(
                region_id=self.region,
                image_family='acs:ubuntu_22_04_x64',
                instance_type='ecs.g6.large',
                security_group_id=security_group_id,
                internet_charge_type='PayByTraffic',
                system_disk=system_disk,
                v_switch_id=vswitch_id,
                instance_charge_type='PostPaid',
                key_pair_name=key_pair_name,
                dry_run=False
            )
            runtime = util_models.RuntimeOptions()
            response = self.client.create_instance_with_options(create_instance_request, runtime)
            instance_id = response.body.instance_id
            log_and_print(f"ECS 实例创建成功，实例 ID: {instance_id}")
            return instance_id
        except Exception as e:
            log_and_print(f"创建 ECS 实例失败: {str(e)}")
            return None

    def list_instances(self):
        try:
            request = ecs_20140526_models.DescribeInstancesRequest(
                region_id=self.region,
                page_size=100
            )
            response = self.client.describe_instances(request)
            instances = response.body.instances.instance
            all_instances = []

            for instance in instances:
                instance_info = {
                    'InstanceId': instance.instance_id,
                    'InstanceName': instance.instance_name,
                    'Status': instance.status,
                    'PublicIp': instance.public_ip_address.ip_address[0] if instance.public_ip_address.ip_address else 'N/A',
                    'PrivateIp': instance.vpc_attributes.private_ip_address.ip_address[0] if instance.vpc_attributes.private_ip_address.ip_address else 'N/A'
                }
                all_instances.append(instance_info)
                log_and_print(f"找到实例：ID={instance_info['InstanceId']}, 名称={instance_info['InstanceName']}, 状态={instance_info['Status']}, 公网IP={instance_info['PublicIp']}, 内网IP={instance_info['PrivateIp']}")
                save_ids(self.profile, self.region, ecs=instance_info)

            log_and_print(f"已将 {len(all_instances)} 个 ECS 实例信息保存到 ids.json")
            return all_instances
        except Exception as e:
            log_and_print(f"查询 ECS 实例列表时发生错误: {str(e)}")
            return []

    def delete_instance(self, instance_id):
        try:
            request = ecs_20140526_models.DeleteInstanceRequest(
                instance_id=instance_id,
                force=True
            )
            self.client.delete_instance(request)
            log_and_print(f"实例 {instance_id} 已成功删除")
            return True
        except Exception as e:
            log_and_print(f"删除实例 {instance_id} 失败: {str(e)}")
            return False

    def get_instance_public_ip(self, instance_id):
        try:
            request = ecs_20140526_models.DescribeInstanceAttributeRequest(
                instance_id=instance_id
            )
            response = self.client.describe_instance_attribute(request)
            public_ip = response.body.public_ip_address.ip_address[0] if response.body.public_ip_address.ip_address else None
            return public_ip
        except Exception as e:
            log_and_print(f"获取实例 {instance_id} 的公网 IP 失败: {str(e)}")
            return None

    def get_instance_info(self, instance_id):
        try:
            request = ecs_20140526_models.DescribeInstanceAttributeRequest(
                instance_id=instance_id
            )
            response = self.client.describe_instance_attribute(request)
            return {
                'InstanceId': response.body.instance_id,
                'InstanceName': response.body.instance_name,
                'PublicIpAddress': response.body.public_ip_address.ip_address[0] if response.body.public_ip_address.ip_address else 'N/A',
                'PrivateIpAddress': response.body.vpc_attributes.private_ip_address.ip_address[0] if response.body.vpc_attributes.private_ip_address.ip_address else 'N/A',
                'CreationTime': response.body.creation_time
            }
        except Exception as e:
            log_and_print(f"获取实例 {instance_id} 信息失败: {str(e)}")
            return None

    def update_instance(self, instance_id, instance_name=None, instance_type=None, security_group_id=None):
        try:
            # 更新实例名称
            if instance_name:
                modify_name_request = ecs_20140526_models.ModifyInstanceAttributeRequest(
                    instance_id=instance_id,
                    instance_name=instance_name
                )
                self.client.modify_instance_attribute(modify_name_request)
                log_and_print(f"ECS 实例 {instance_id} 名称更新为 {instance_name}")

            # 更新实例类型
            if instance_type:
                modify_type_request = ecs_20140526_models.ModifyInstanceSpecRequest(
                    instance_id=instance_id,
                    instance_type=instance_type
                )
                self.client.modify_instance_spec(modify_type_request)
                log_and_print(f"ECS 实例 {instance_id} 类型更新为 {instance_type}")

            # 更新安全组
            if security_group_id:
                modify_sg_request = ecs_20140526_models.ModifyInstanceAttributeRequest(
                    instance_id=instance_id,
                    security_group_ids=[security_group_id]
                )
                self.client.modify_instance_attribute(modify_sg_request)
                log_and_print(f"ECS 实例 {instance_id} 安全组更新为 {security_group_id}")

            # 获取更新后的实例信息
            updated_info = self.get_instance_info(instance_id)
            if updated_info:
                save_ids(self.profile, self.region, ecs=updated_info, overwrite=True)
                log_and_print(f"已更新 ECS 实例信息: {updated_info}")

            return True
        except Exception as e:
            log_and_print(f"更新 ECS 实例 {instance_id} 失败: {str(e)}")
            return False

    # 其他方法可以根据需要添加...
