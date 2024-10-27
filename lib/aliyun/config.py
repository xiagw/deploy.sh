import os
import json
from alibabacloud_tea_openapi import models as open_api_models

class Config:
    ACCESS_KEY_ID = os.environ.get('ALIYUN_ACCESS_KEY_ID')
    ACCESS_KEY_SECRET = os.environ.get('ALIYUN_ACCESS_KEY_SECRET')
    PUBLIC_KEY_NAME = 'xkk'
    PUBLIC_KEY = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9/b3mFlob8espX/7BH31Ie4SQURLNQ0cen8UtnI13y'
    DEFAULT_REGION = 'cn-hangzhou'

    @classmethod
    def load_profile(cls, profile_name):
        config_file = os.path.expanduser('~/.aliyun/config.json')
        if os.path.exists(config_file):
            with open(config_file, 'r', encoding='utf-8') as f:
                config = json.load(f)
            for profile in config.get('profiles', []):
                if profile['name'] == profile_name:
                    cls.ACCESS_KEY_ID = profile['access_key_id']
                    cls.ACCESS_KEY_SECRET = profile['access_key_secret']
                    cls.DEFAULT_REGION = profile.get('region_id', cls.DEFAULT_REGION)
                    return True
        return False

    @classmethod
    def get_client_config(cls):
        return open_api_models.Config(
            access_key_id=cls.ACCESS_KEY_ID,
            access_key_secret=cls.ACCESS_KEY_SECRET,
            region_id=cls.DEFAULT_REGION
        )

    @classmethod
    def validate_config(cls):
        if not cls.ACCESS_KEY_ID or not cls.ACCESS_KEY_SECRET:
            raise ValueError("ACCESS_KEY_ID 和 ACCESS_KEY_SECRET 必须设置")
        if not cls.PUBLIC_KEY_NAME or not cls.PUBLIC_KEY:
            raise ValueError("PUBLIC_KEY_NAME 和 PUBLIC_KEY 必须设置")
