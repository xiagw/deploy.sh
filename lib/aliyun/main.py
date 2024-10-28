import argparse
import json
import time
from alibabacloud_ecs20140526.client import Client as Ecs20140526Client
from .config import Config
from .utils import setup_logging, log_and_print, read_latest_log, save_ids, confirm_action, read_ids
from .ecs import ECSManager
from .dns import DNSManager
from .oss import OSSManager
from .cdn import CDNManager
from .lbs import LBSManager  # 更新这一行

def show_service_actions(service):
    actions = {
        'ecs': [
            ("create", "创建 ECS 实例"),
            ("list", "列出 ECS 实例"),
            ("delete", "删除 ECS 实例"),
            ("update", "更新 ECS 实例")
        ],
        'dns': [
            ("create", "创建 DNS 记录"),
            ("delete", "删除 DNS 记录"),
            ("list", "列出 DNS 记录"),
            ("update", "更新 DNS 记录")
        ],
        'oss': [
            ("create", "创建 OSS 存储桶"),
            ("list", "列出 OSS 存储桶"),
            ("delete", "删除 OSS 存储桶"),
            ("update-acl", "更新 OSS 存储桶 ACL"),
            ("set-lifecycle", "设置 OSS 存储桶生命周期规则"),
            ("info", "获取 OSS 存储桶信息")
        ],
        'cdn': [
            ("create", "创建 CDN 域名"),
            ("delete", "删除 CDN 域名"),
            ("list", "列出 CDN 域名"),
            ("update", "更新 CDN 域名")
        ],
        'lbs': [
            ("list", "列出负载均衡实例"),
            ("create", "创建负载均衡实例"),
            ("update", "更新负载均衡实例"),
            ("delete", "删除负载均衡实例")
        ]
    }

    if service in actions:
        print(f"{service.upper()} 可用操作：")
        for action, description in actions[service]:
            print(f"  {action:<12} {description}")
    else:
        print(f"未知的服务: {service}")

def main():
    parser = argparse.ArgumentParser(description='阿里云资源管理工具')

    # 全局参数
    parser.add_argument('--region', default='cn-hangzhou', help='阿里云地域')
    parser.add_argument('--profile', help='指定阿里云配置文件名称')
    parser.add_argument('--access-key-id', help='阿里云访问密钥 ID')
    parser.add_argument('--access-key-secret', help='阿里云访问密钥密码')

    subparsers = parser.add_subparsers(dest='service', help='云服务')

    # ECS 子命令
    ecs_parser = subparsers.add_parser('ecs', help='ECS 相关操作')
    ecs_subparsers = ecs_parser.add_subparsers(dest='action', help='ECS 操作')
    ecs_subparsers.add_parser('create', help='创建 ECS 实例')
    ecs_subparsers.add_parser('list', help='列出 ECS 实例')
    ecs_delete_parser = ecs_subparsers.add_parser('delete', help='删除 ECS 实例')
    ecs_delete_parser.add_argument('--instance-id', help='要删除的 ECS 实例 ID（可选）')
    ecs_delete_parser.add_argument('--force', action='store_true', help='强制删除，不进行二次确认')
    ecs_update_parser = ecs_subparsers.add_parser('update', help='更新 ECS 实例')
    ecs_update_parser.add_argument('--instance-id', required=True, help='要更新的 ECS 实例 ID')
    ecs_update_parser.add_argument('--name', help='新的实例名称')
    ecs_update_parser.add_argument('--instance-type', help='新的实例类型')
    ecs_update_parser.add_argument('--security-group-id', help='新的安全组 ID')

    # DNS 子命令
    dns_parser = subparsers.add_parser('dns', help='DNS 相关操作')
    dns_subparsers = dns_parser.add_subparsers(dest='action', help='DNS 操作')
    dns_create_parser = dns_subparsers.add_parser('create', help='创建 DNS 记录')
    dns_create_parser.add_argument('--domain', required=True, help='域名')
    dns_create_parser.add_argument('--rr', required=True, help='主机记录')
    dns_create_parser.add_argument('--value', required=True, help='记录值')
    dns_delete_parser = dns_subparsers.add_parser('delete', help='删除 DNS 记录')
    dns_delete_parser.add_argument('--domain', required=True, help='域名')
    dns_delete_parser.add_argument('--rr', required=True, help='主机记录')
    dns_delete_parser.add_argument('--record-id', required=True, help='记录 ID')
    dns_subparsers.add_parser('list', help='列出 DNS 记录')
    dns_update_parser = dns_subparsers.add_parser('update', help='更新 DNS 记录')
    dns_update_parser.add_argument('--domain', required=True, help='域名')
    dns_update_parser.add_argument('--rr', required=True, help='主机记录')
    dns_update_parser.add_argument('--value', required=True, help='新的记录值')
    dns_update_parser.add_argument('--type', default='A', help='记录类型（默认为 A）')

    # OSS 子命令
    oss_parser = subparsers.add_parser('oss', help='OSS 相关操作')
    oss_subparsers = oss_parser.add_subparsers(dest='action', help='OSS 操作')
    oss_create_parser = oss_subparsers.add_parser('create', help='创建 OSS 存储桶')
    oss_create_parser.add_argument('--bucket-name', required=True, help='存储桶名称')
    oss_subparsers.add_parser('list', help='列出 OSS 存储桶')
    oss_delete_parser = oss_subparsers.add_parser('delete', help='删除 OSS 存储桶')
    oss_delete_parser.add_argument('--bucket-name', required=True, help='存储桶名称')
    oss_update_acl_parser = oss_subparsers.add_parser('update-acl', help='更新 OSS 存储桶 ACL')
    oss_update_acl_parser.add_argument('--bucket-name', required=True, help='存储桶名称')
    oss_update_acl_parser.add_argument('--acl', required=True, choices=['private', 'public-read', 'public-read-write'], help='ACL 类型')
    oss_set_lifecycle_parser = oss_subparsers.add_parser('set-lifecycle', help='设置 OSS 存储桶生命周期规则')
    oss_set_lifecycle_parser.add_argument('--bucket-name', required=True, help='存储桶名称')
    oss_set_lifecycle_parser.add_argument('--rules', required=True, help='生命周期规则 JSON 字符串')
    oss_get_info_parser = oss_subparsers.add_parser('info', help='获取 OSS 存储桶信息')
    oss_get_info_parser.add_argument('--bucket-name', required=True, help='存储桶名称')
    oss_migrate_parser = oss_subparsers.add_parser('migrate', help='迁移 OSS 存储桶中的多媒体文件')
    oss_migrate_parser.add_argument('--source-bucket', required=True, help='源存储桶名称')
    oss_migrate_parser.add_argument('--dest-bucket', required=True, help='目标存储桶名称')
    oss_migrate_parser.add_argument('--batch-size', type=int, default=100, help='每批处理的文件数量')
    oss_migrate_parser.add_argument('--max-workers', type=int, default=5, help='最大并发工作线程数')

    # CDN 子命令
    cdn_parser = subparsers.add_parser('cdn', help='CDN 相关操作')
    cdn_subparsers = cdn_parser.add_subparsers(dest='action', help='CDN 操作')
    cdn_create_parser = cdn_subparsers.add_parser('create', help='创建 CDN 域名')
    cdn_create_parser.add_argument('--domain', required=True, help='加速域名')
    cdn_create_parser.add_argument('--origin', required=True, help='源站域名')
    cdn_delete_parser = cdn_subparsers.add_parser('delete', help='删除 CDN 域名')
    cdn_delete_parser.add_argument('--domain', required=True, help='加速域名')
    cdn_subparsers.add_parser('list', help='列出 CDN 域名')
    cdn_update_parser = cdn_subparsers.add_parser('update', help='更新 CDN 域名')
    cdn_update_parser.add_argument('--domain', required=True, help='加速域名')
    cdn_update_parser.add_argument('--origin', help='新的源站域名')
    cdn_update_parser.add_argument('--cdn-type', choices=['web', 'download', 'video'], help='CDN 类型')

    # LBS 子命令 (原 SLB 子命令)
    lbs_parser = subparsers.add_parser('lbs', help='负载均衡相关操作')  # 将 'slb' 改为 'lbs'
    lbs_subparsers = lbs_parser.add_subparsers(dest='action', help='负载均衡操作')
    lbs_list_parser = lbs_subparsers.add_parser('list', help='列出负载均衡实例')
    lbs_list_parser.add_argument('--id', help='负载均衡实例 ID')

    lbs_create_parser = lbs_subparsers.add_parser('create', help='创建负载均衡实例')
    lbs_create_parser.add_argument('--type', required=True, choices=['NLB', 'ALB', 'CLB'], help='负载均衡类型')
    lbs_create_parser.add_argument('--vpc-id', required=True, help='VPC ID')
    lbs_create_parser.add_argument('--vswitch-id', required=True, help='交换机 ID')
    lbs_create_parser.add_argument('--name', required=True, help='负载均衡实例名称')
    lbs_create_parser.add_argument('--address-type', default='Internet', choices=['Internet', 'Intranet'], help='地址类型')

    lbs_update_parser = lbs_subparsers.add_parser('update', help='更新负载均衡实例')
    lbs_update_parser.add_argument('--type', required=True, choices=['NLB', 'ALB', 'CLB'], help='负载均衡类型')
    lbs_update_parser.add_argument('--id', required=True, help='负载均衡实例 ID')
    lbs_update_parser.add_argument('--name', help='新的负载均衡实例名称')

    lbs_delete_parser = lbs_subparsers.add_parser('delete', help='删除负载均衡实例')
    lbs_delete_parser.add_argument('--type', required=True, choices=['NLB', 'ALB', 'CLB'], help='负载均衡类型')
    lbs_delete_parser.add_argument('--id', required=True, help='负载均衡实例 ID')

    args = parser.parse_args()

    # 如果只指定了服务而没有指定操作，显示该服务的可用操作
    if args.service and not args.action:
        show_service_actions(args.service)
        return

    # 如果没有指定服务，显示主帮助信息
    if not args.service:
        parser.print_help()
        return

    profile = args.profile or 'default'
    region = args.region or Config.DEFAULT_REGION

    setup_logging(profile, region)

    if args.access_key_id:
        Config.ACCESS_KEY_ID = args.access_key_id
    if args.access_key_secret:
        Config.ACCESS_KEY_SECRET = args.access_key_secret

    if args.profile:
        if not Config.load_profile(args.profile):
            log_and_print(f"错误: 未找到为 {args.profile} 的配置文件", profile, region)
            return

    try:
        Config.validate_config()
    except ValueError as e:
        log_and_print(f"配置错误: {str(e)}", profile, region)
        return

    # 创建 ECS 客户端
    ecs_client = Ecs20140526Client(Config.get_client_config())

    # 更新管理器初始化
    ecs_manager = ECSManager(Config.ACCESS_KEY_ID, Config.ACCESS_KEY_SECRET, region, profile)
    dns_manager = DNSManager(Config.ACCESS_KEY_ID, Config.ACCESS_KEY_SECRET, region, profile)
    oss_manager = OSSManager(Config.ACCESS_KEY_ID, Config.ACCESS_KEY_SECRET, region, profile)
    cdn_manager = CDNManager(Config.ACCESS_KEY_ID, Config.ACCESS_KEY_SECRET)
    lbs_manager = LBSManager(Config.ACCESS_KEY_ID, Config.ACCESS_KEY_SECRET, region)  # 将 SLBManager 改为 LBSManager

    # 执行相应的操作
    if args.service == 'ecs':
        if args.action == 'create':
            ecs_manager.create_ecs()
        elif args.action == 'list':
            ecs_manager.list_instances()
        elif args.action == 'delete':
            # 首先尝试从已保存的信息中获取实例 ID
            ids = read_ids(profile, region)
            instance_ids = ids.get("ecs", [])

            if instance_ids:
                instance_id = instance_ids[-1].get('InstanceId') if isinstance(instance_ids[-1], dict) else instance_ids[-1]
            else:
                instance_id = None

            # 如果没有找到保存的实例 ID，则使用参数中提供的实例 ID
            if not instance_id and args.instance_id:
                instance_id = args.instance_id

            if instance_id:
                instance_info = ecs_manager.get_instance_info(instance_id)
                if instance_info:
                    print(f"将要删除的实例信息：")
                    print(f"实例 ID: {instance_info['InstanceId']}")
                    print(f"实例名称: {instance_info['InstanceName']}")
                    print(f"公网 IP: {instance_info['PublicIpAddress']}")
                    print(f"私网 IP: {instance_info['PrivateIpAddress']}")
                    print(f"创建时间: {instance_info['CreationTime']}")

                    if not args.force:
                        if confirm_action(f"确定要删除实例 {instance_id} 吗？此操作不可逆。"):
                            print("开始 30 秒冷却期，如果想取消删除，请按 Ctrl+C...")
                            try:
                                time.sleep(30)
                            except KeyboardInterrupt:
                                print("删除操作已取消。")
                                return
                            ecs_manager.delete_instance(instance_id)
                        else:
                            print("删除操作已取消。")
                    else:
                        ecs_manager.delete_instance(instance_id)
                else:
                    print(f"未找到实例 ID 为 {instance_id} 的实例。")
            else:
                print("错误: 未找到要删除的实例 ID。请确保已创建实例或提供 --instance-id 参数。")
        elif args.action == 'update':
            ecs_manager.update_instance(
                args.instance_id,
                instance_name=args.name,
                instance_type=args.instance_type,
                security_group_id=args.security_group_id
            )
    elif args.service == 'dns':
        if args.action == 'create':
            dns_manager.create_dns(args.domain, args.rr, args.value)
        elif args.action == 'delete':
            dns_manager.delete_dns(args.domain, args.rr, args.record_id)
        elif args.action == 'list':
            dns_manager.list_dns_records()
        elif args.action == 'update':
            dns_manager.update_dns(args.domain, args.rr, args.value, args.type)
        else:
            log_and_print(f"未知的 DNS 操作: {args.action}")
    elif args.service == 'oss':
        if args.action == 'create':
            oss_manager.create_bucket(args.bucket_name)
        elif args.action == 'list':
            buckets = oss_manager.list_buckets()
            if buckets:
                save_ids(profile, region, oss_bucket=buckets)
        elif args.action == 'delete':
            oss_manager.delete_bucket(args.bucket_name)
        elif args.action == 'update-acl':
            oss_manager.update_bucket_acl(args.bucket_name, args.acl)
        elif args.action == 'set-lifecycle':
            rules = json.loads(args.rules)
            oss_manager.set_bucket_lifecycle(args.bucket_name, rules)
        elif args.action == 'info':
            oss_manager.get_bucket_info(args.bucket_name)
        elif args.action == 'migrate':
            oss_manager.migrate_multimedia_files(
                args.source_bucket,
                args.dest_bucket,
                batch_size=args.batch_size,
                max_workers=args.max_workers
            )
    elif args.service == 'cdn':
        if args.action == 'create':
            cdn_manager.create_domain(args.domain, args.origin)
        elif args.action == 'delete':
            cdn_manager.delete_domain(args.domain)
        elif args.action == 'list':
            cdn_manager.list_domains()
        elif args.action == 'update':
            cdn_manager.update_domain(args.domain, args.origin, args.cdn_type)
    elif args.service == 'lbs':
        if args.action == 'list':
            lbs_manager.list_instances(args.id)
        elif args.action == 'create':
            lbs_manager.create_instance(args.type, args.vpc_id, args.vswitch_id, args.name, args.address_type)
        elif args.action == 'update':
            lbs_manager.update_instance(args.type, args.id, load_balancer_name=args.name)
        elif args.action == 'delete':
            lbs_manager.delete_instance(args.type, args.id)
        else:
            log_and_print(f"未知的 LBS 操作: {args.action}")

if __name__ == "__main__":
    main()
