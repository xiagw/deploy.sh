from alibabacloud_nlb20220430.client import Client as Nlb20220430Client
from alibabacloud_alb20200616.client import Client as Alb20200616Client
from alibabacloud_slb20140515.client import Client as Slb20140515Client
from alibabacloud_tea_openapi import models as open_api_models
from alibabacloud_nlb20220430 import models as nlb_models
from alibabacloud_alb20200616 import models as alb_models
from alibabacloud_slb20140515 import models as slb_models
from .utils import log_and_print, save_ids
from .config import Config

class LBSManager:
    def __init__(self, access_key_id, access_key_secret, region):
        self.region = region
        config = open_api_models.Config(
            access_key_id=access_key_id,
            access_key_secret=access_key_secret,
            region_id=region  # 添加 region_id
        )
        self.nlb_client = Nlb20220430Client(config)
        self.alb_client = Alb20200616Client(config)
        self.clb_client = Slb20140515Client(config)

    def list_instances(self, slb_id=None):
        all_slbs = []
        all_slbs.extend(self.list_nlb_instances(slb_id))
        all_slbs.extend(self.list_alb_instances(slb_id))
        all_slbs.extend(self.list_clb_instances(slb_id))

        if not all_slbs:
            log_and_print("未找到任何负载均衡实例")
        else:
            log_and_print(f"共找到 {len(all_slbs)} 个负载均衡实例")

        return all_slbs

    def list_nlb_instances(self, slb_id=None):
        nlbs = []
        next_token = None

        while True:
            try:
                request = nlb_models.ListLoadBalancersRequest(
                    max_results=100,
                    next_token=next_token
                )
                if slb_id:
                    request.load_balancer_ids = [slb_id]

                response = self.nlb_client.list_load_balancers(request)
                slbs = response.body.load_balancers

                for slb in slbs:
                    slb_info = {
                        'type': 'NLB',
                        'load_balancer_id': slb.load_balancer_id,
                        'load_balancer_name': slb.load_balancer_name,
                        'address_type': slb.address_type,
                        'network_type': slb.network_type,
                        'create_time': slb.create_time,
                        'address': slb.address,
                        'ip_address': slb.ip_address,
                        'vpc_id': slb.vpc_id
                    }
                    nlbs.append(slb_info)
                    log_and_print(f"找到 NLB 实例：ID={slb_info['load_balancer_id']}, 名称={slb_info['load_balancer_name']}")
                    save_ids(self.region, slb=slb_info)

                next_token = response.body.next_token
                if not next_token:
                    break
            except Exception as e:
                log_and_print(f"查询 NLB 实例列表时发生错误: {str(e)}")
                break

        return nlbs

    def list_alb_instances(self, slb_id=None):
        albs = []
        next_token = None

        while True:
            try:
                request = alb_models.ListLoadBalancersRequest(
                    max_results=100,
                    next_token=next_token
                )
                if slb_id:
                    request.load_balancer_ids = [slb_id]

                response = self.alb_client.list_load_balancers(request)
                slbs = response.body.load_balancers

                for slb in slbs:
                    slb_info = {
                        'type': 'ALB',
                        'load_balancer_id': slb.load_balancer_id,
                        'load_balancer_name': slb.load_balancer_name,
                        'address_type': slb.address_type,
                        'create_time': slb.create_time,
                        'vpc_id': slb.vpc_id
                    }
                    albs.append(slb_info)
                    log_and_print(f"找到 ALB 实例：ID={slb_info['load_balancer_id']}, 名称={slb_info['load_balancer_name']}")
                    save_ids(self.region, slb=slb_info)

                next_token = response.body.next_token
                if not next_token:
                    break
            except Exception as e:
                log_and_print(f"查询 ALB 实例列表时发生错误: {str(e)}")
                break

        return albs

    def list_clb_instances(self, slb_id=None):
        clbs = []
        page_number = 1
        page_size = 100

        while True:
            try:
                request = slb_models.DescribeLoadBalancersRequest(
                    region_id=self.region,
                    page_number=page_number,
                    page_size=page_size
                )
                if slb_id:
                    request.load_balancer_id = slb_id

                response = self.clb_client.describe_load_balancers(request)
                slbs = response.body.load_balancers.load_balancer

                for slb in slbs:
                    slb_info = {
                        'type': 'CLB',
                        'load_balancer_id': slb.load_balancer_id,
                        'load_balancer_name': slb.load_balancer_name,
                        'address_type': slb.address_type,
                        'network_type': slb.network_type,
                        'create_time': slb.create_time,
                        'address': slb.address,
                        'vpc_id': slb.vpc_id
                    }
                    clbs.append(slb_info)
                    log_and_print(f"找到 CLB 实例：ID={slb_info['load_balancer_id']}, 名称={slb_info['load_balancer_name']}")
                    save_ids(self.region, slb=slb_info)

                if len(slbs) < page_size:
                    break
                page_number += 1
            except Exception as e:
                log_and_print(f"查询 CLB 实例列表时发生错误: {str(e)}")
                break

        return clbs

    def create_nlb(self, vpc_id, vswitch_id, name, address_type='Internet'):
        try:
            request = nlb_models.CreateLoadBalancerRequest(
                vpc_id=vpc_id,
                zone_mappings=[nlb_models.CreateLoadBalancerRequestZoneMappings(
                    vswitch_id=vswitch_id
                )],
                load_balancer_name=name,
                address_type=address_type
            )
            response = self.nlb_client.create_load_balancer(request)
            nlb_id = response.body.load_balancer_id
            log_and_print(f"NLB 实例创建成功，ID: {nlb_id}")
            return nlb_id
        except Exception as e:
            log_and_print(f"创建 NLB 实例失败: {str(e)}")
            return None

    def delete_nlb(self, nlb_id):
        try:
            request = nlb_models.DeleteLoadBalancerRequest(
                load_balancer_id=nlb_id
            )
            self.nlb_client.delete_load_balancer(request)
            log_and_print(f"NLB 实例 {nlb_id} 删除成功")
            return True
        except Exception as e:
            log_and_print(f"删除 NLB 实例 {nlb_id} 失败: {str(e)}")
            return False

    # 其他 SLB 和 NLB 相关方法可以根据需要添加...

    def create_instance(self, lb_type, vpc_id, vswitch_id, name, address_type='Internet'):
        if lb_type == 'NLB':
            return self.create_nlb(vpc_id, vswitch_id, name, address_type)
        elif lb_type == 'ALB':
            return self.create_alb(vpc_id, vswitch_id, name, address_type)
        elif lb_type == 'CLB':
            return self.create_clb(vpc_id, vswitch_id, name, address_type)
        else:
            log_and_print(f"不支持的负载均衡类型: {lb_type}")
            return None

    def create_alb(self, vpc_id, vswitch_id, name, address_type='Internet'):
        try:
            request = alb_models.CreateLoadBalancerRequest(
                vpc_id=vpc_id,
                zone_mappings=[alb_models.ZoneMapping(
                    vswitch_id=vswitch_id
                )],
                load_balancer_name=name,
                address_type=address_type
            )
            response = self.alb_client.create_load_balancer(request)
            alb_id = response.body.load_balancer_id
            log_and_print(f"ALB 实例创建成功，ID: {alb_id}")
            return alb_id
        except Exception as e:
            log_and_print(f"创建 ALB 实例失败: {str(e)}")
            return None

    def create_clb(self, vpc_id, vswitch_id, name, address_type='internet'):
        try:
            request = slb_models.CreateLoadBalancerRequest(
                vpc_id=vpc_id,
                vswitch_id=vswitch_id,
                load_balancer_name=name,
                address_type=address_type
            )
            response = self.clb_client.create_load_balancer(request)
            clb_id = response.body.load_balancer_id
            log_and_print(f"CLB 实例创建成功，ID: {clb_id}")
            return clb_id
        except Exception as e:
            log_and_print(f"创建 CLB 实例失败: {str(e)}")
            return None

    def update_instance(self, lb_type, lb_id, **kwargs):
        if lb_type == 'NLB':
            return self.update_nlb(lb_id, **kwargs)
        elif lb_type == 'ALB':
            return self.update_alb(lb_id, **kwargs)
        elif lb_type == 'CLB':
            return self.update_clb(lb_id, **kwargs)
        else:
            log_and_print(f"不支持的负载均衡类型: {lb_type}")
            return False

    def update_nlb(self, lb_id, **kwargs):
        try:
            request = nlb_models.UpdateLoadBalancerAttributeRequest(
                load_balancer_id=lb_id,
                **kwargs
            )
            self.nlb_client.update_load_balancer_attribute(request)
            log_and_print(f"NLB 实例 {lb_id} 更新成功")
            return True
        except Exception as e:
            log_and_print(f"更新 NLB 实例 {lb_id} 失败: {str(e)}")
            return False

    def update_alb(self, lb_id, **kwargs):
        try:
            request = alb_models.UpdateLoadBalancerAttributeRequest(
                load_balancer_id=lb_id,
                **kwargs
            )
            self.alb_client.update_load_balancer_attribute(request)
            log_and_print(f"ALB 实例 {lb_id} 更新成功")
            return True
        except Exception as e:
            log_and_print(f"更新 ALB 实例 {lb_id} 失败: {str(e)}")
            return False

    def update_clb(self, lb_id, **kwargs):
        try:
            request = slb_models.SetLoadBalancerNameRequest(
                load_balancer_id=lb_id,
                load_balancer_name=kwargs.get('load_balancer_name', '')
            )
            self.clb_client.set_load_balancer_name(request)
            log_and_print(f"CLB 实例 {lb_id} 更新成功")
            return True
        except Exception as e:
            log_and_print(f"更新 CLB 实例 {lb_id} 失败: {str(e)}")
            return False

    def delete_instance(self, lb_type, lb_id):
        if lb_type == 'NLB':
            return self.delete_nlb(lb_id)
        elif lb_type == 'ALB':
            return self.delete_alb(lb_id)
        elif lb_type == 'CLB':
            return self.delete_clb(lb_id)
        else:
            log_and_print(f"不支持的负载均衡类型: {lb_type}")
            return False

    def delete_alb(self, lb_id):
        try:
            request = alb_models.DeleteLoadBalancerRequest(
                load_balancer_id=lb_id
            )
            self.alb_client.delete_load_balancer(request)
            log_and_print(f"ALB 实例 {lb_id} 删除成功")
            return True
        except Exception as e:
            log_and_print(f"删除 ALB 实例 {lb_id} 失败: {str(e)}")
            return False

    def delete_clb(self, lb_id):
        try:
            request = slb_models.DeleteLoadBalancerRequest(
                load_balancer_id=lb_id
            )
            self.clb_client.delete_load_balancer(request)
            log_and_print(f"CLB 实例 {lb_id} 删除成功")
            return True
        except Exception as e:
            log_and_print(f"删除 CLB 实例 {lb_id} 失败: {str(e)}")
            return False
