# decorators.py
import time
import functools

def timing_decorator(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        end = time.time()
        print(f"{func.__name__} took {end - start:.2f} seconds")
        return result
    return wrapper

# 使用示例
@timing_decorator
def migrate_multimedia_files(self, *args, **kwargs):
    # 原函数代码...