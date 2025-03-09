# 日期格式说明

## 日期格式参数
- `%u`: 星期几 (1..7)；1 代表星期一
- `%j`: 一年中的第几天 (001..366)
- `%W`: 一年中的第几周，以星期一为一周的第一天 (00..53)

## Git LFS 相关说明
如果遇到 "Encountered 1 file(s) that should have been pointers, but weren't" 错误，可以使用以下命令解决：

```bash
git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)
```

fatal: git fetch-pack: expected shallow list
fatal: The remote end hung up unexpectedly

https://computingforgeeks.com/how-to-install-latest-version-of-git-git-2-x-on-centos-7/
