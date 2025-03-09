# macOS Homebrew 镜像源配置指南

## 查看当前源
```bash
# 查看 brew.git 源
cd "$(brew --repo)" && git remote -v

# 查看 homebrew-core.git 源
cd "$(brew --repo homebrew/core)" && git remote -v
```

## 切换镜像源
以下提供几个常用的镜像源配置方案，选择其中一个执行即可。

### 中科大源（推荐）
```bash
# 设置 brew.git 镜像
git -C "$(brew --repo)" remote set-url origin https://mirrors.ustc.edu.cn/brew.git

# 设置 homebrew-core.git 镜像
git -C "$(brew --repo homebrew/core)" remote set-url origin https://mirrors.ustc.edu.cn/homebrew-core.git

# 设置 homebrew-cask.git 镜像
git -C "$(brew --repo homebrew/cask)" remote set-url origin https://mirrors.ustc.edu.cn/homebrew-cask.git

# 设置环境变量
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
```

### 阿里源
```bash
# 设置 brew.git 镜像
git -C "$(brew --repo)" remote set-url origin https://mirrors.aliyun.com/homebrew/brew.git

# 设置 homebrew-core.git 镜像
git -C "$(brew --repo homebrew/core)" remote set-url origin https://mirrors.aliyun.com/homebrew/homebrew-core.git

# 设置 bottles 镜像
export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.aliyun.com/homebrew/homebrew-bottles
```

### 清华源
```bash
# 设置 brew.git 镜像
git -C "$(brew --repo)" remote set-url origin https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git

# 设置 homebrew-core.git 镜像
git -C "$(brew --repo homebrew/core)" remote set-url origin https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git

# 设置 homebrew-cask.git 镜像
git -C "$(brew --repo homebrew/cask)" remote set-url origin https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-cask.git

# 设置 bottles 镜像
export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles
```

## 应用配置
根据您使用的 shell 选择对应的配置方式：

```bash
# zsh 用户
echo 'export HOMEBREW_BOTTLE_DOMAIN=${YOUR_MIRROR}/homebrew-bottles' >> ~/.zshrc
source ~/.zshrc

# bash 用户
echo 'export HOMEBREW_BOTTLE_DOMAIN=${YOUR_MIRROR}/homebrew-bottles' >> ~/.bash_profile
source ~/.bash_profile
```
注：将 ${YOUR_MIRROR} 替换为你选择的镜像源地址

## 恢复官方源
```bash
# 重置为官方源
git -C "$(brew --repo)" remote set-url origin https://github.com/Homebrew/brew.git
git -C "$(brew --repo homebrew/core)" remote set-url origin https://github.com/Homebrew/homebrew-core.git
git -C "$(brew --repo homebrew/cask)" remote set-url origin https://github.com/Homebrew/homebrew-cask

# 删除环境变量配置（根据您的 shell 编辑对应文件）
# 在 ~/.zshrc 或 ~/.bash_profile 中注释或删除 HOMEBREW_BOTTLE_DOMAIN 配置行

# 更新 Homebrew
brew update
```

## 其他优化（可选）
```bash
# 关闭 macOS 系统的 IPv6
networksetup -setv6off Wi-Fi
```
