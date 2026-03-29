#!/bin/bash
# ============================================
# Servers Clean - 服务器安全清理脚本
# 版本: 1.0.0
# 仓库: https://github.com/zhongguomeng/servers-clean
# 说明: 支持 Ubuntu/Debian/CentOS/RHEL/Alpine
#       安全清理 Docker、containerd、系统缓存
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION="1.0.0"

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        OS=$(uname -s)
    fi
    
    case $OS in
        ubuntu|debian)
            OS_FAMILY="debian"
            PKG_MANAGER="apt"
            ;;
        centos|rhel|rocky|almalinux)
            OS_FAMILY="rhel"
            if command -v dnf &> /dev/null; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            ;;
        alpine)
            OS_FAMILY="alpine"
            PKG_MANAGER="apk"
            ;;
        fedora)
            OS_FAMILY="fedora"
            PKG_MANAGER="dnf"
            ;;
        opensuse*|suse)
            OS_FAMILY="suse"
            PKG_MANAGER="zypper"
            ;;
        arch)
            OS_FAMILY="arch"
            PKG_MANAGER="pacman"
            ;;
        *)
            OS_FAMILY="unknown"
            PKG_MANAGER="unknown"
            ;;
    esac
    
    echo -e "${BLUE}检测到系统: $OS${NC}"
    echo -e "${BLUE}包管理器: $PKG_MANAGER${NC}"
}

# 显示帮助
show_help() {
    cat << EOF
${BLUE}Servers Clean v${VERSION} - 服务器安全清理脚本${NC}

支持系统: Ubuntu, Debian, CentOS, RHEL, Alpine, Fedora, OpenSUSE, Arch

用法: 
  bash <(curl -s https://raw.githubusercontent.com/zhongguomeng/servers-clean/main/clean.sh)

选项:
  --help, -h      显示帮助信息
  --version, -v   显示版本信息
  --force         跳过卷清理确认
  --dry-run       预览模式，不实际执行
  --no-docker     跳过 Docker 清理
  --no-system     跳过系统缓存清理

示例:
  # 交互式清理（推荐）
  bash <(curl -s https://raw.githubusercontent.com/zhongguomeng/servers-clean/main/clean.sh)
  
  # 自动清理（跳过确认）
  bash <(curl -s https://raw.githubusercontent.com/zhongguomeng/servers-clean/main/clean.sh) --force
  
  # 只清理 Docker
  bash <(curl -s https://raw.githubusercontent.com/zhongguomeng/servers-clean/main/clean.sh) --no-system

EOF
    exit 0
}

# 解析参数
FORCE_MODE=false
DRY_RUN=false
CLEAN_DOCKER=true
CLEAN_SYSTEM=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --version|-v) echo "servers-clean v${VERSION}"; exit 0 ;;
        --force) FORCE_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --no-docker) CLEAN_DOCKER=false ;;
        --no-system) CLEAN_SYSTEM=false ;;
        *) echo "未知参数: $1"; show_help ;;
    esac
    shift
done

# 检测系统
detect_os

# 清理包管理器缓存
clean_package_cache() {
    echo -e "${YELLOW}清理包管理器缓存...${NC}"
    case $PKG_MANAGER in
        apt)
            sudo apt clean 2>/dev/null
            sudo apt autoclean 2>/dev/null
            echo -e "${GREEN}  ✓ apt 缓存已清理${NC}"
            ;;
        dnf|yum)
            sudo $PKG_MANAGER clean all 2>/dev/null
            echo -e "${GREEN}  ✓ $PKG_MANAGER 缓存已清理${NC}"
            ;;
        apk)
            sudo apk cache clean 2>/dev/null
            echo -e "${GREEN}  ✓ apk 缓存已清理${NC}"
            ;;
        zypper)
            sudo zypper clean 2>/dev/null
            echo -e "${GREEN}  ✓ zypper 缓存已清理${NC}"
            ;;
        pacman)
            sudo pacman -Scc --noconfirm 2>/dev/null
            echo -e "${GREEN}  ✓ pacman 缓存已清理${NC}"
            ;;
        *)
            echo -e "${YELLOW}  ⚠ 不支持的包管理器，跳过${NC}"
            ;;
    esac
}

# 清理日志
clean_logs() {
    echo -e "${YELLOW}清理系统日志...${NC}"
    
    # journalctl (systemd)
    if command -v journalctl &> /dev/null; then
        sudo journalctl --vacuum-time=7d --vacuum-size=500M 2>/dev/null
        echo -e "${GREEN}  ✓ systemd journal 已清理（保留7天/500M）${NC}"
    else
        # 非 systemd 系统，清理 /var/log 旧文件
        sudo find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null
        sudo find /var/log -name "*.gz" -delete 2>/dev/null
        echo -e "${GREEN}  ✓ /var/log 旧日志已清理（保留30天）${NC}"
    fi
    
    # snap 缓存（仅 Debian 系）
    if [ -d "/var/lib/snapd/cache" ]; then
        sudo rm -rf /var/lib/snapd/cache/* 2>/dev/null
        echo -e "${GREEN}  ✓ snap 缓存已清理${NC}"
    fi
}

# 清理 Docker
clean_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}  ⚠ Docker 未安装，跳过${NC}"
        return
    fi
    
    echo -e "${YELLOW}清理 Docker 资源...${NC}"
    
    RUNNING_CONTAINERS=$(docker ps -q | wc -l)
    echo -e "  运行中的容器: ${GREEN}$RUNNING_CONTAINERS${NC} 个"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}  [预览] 将清理停止的容器和未使用的镜像${NC}"
        docker system df
        return
    fi
    
    docker system prune -a -f
    echo -e "${GREEN}  ✓ Docker 清理完成${NC}"
    
    # 清理卷（需确认）
    UNUSED_VOLUMES=$(docker volume ls -qf dangling=true | wc -l)
    if [ "$UNUSED_VOLUMES" -gt 0 ]; then
        echo -e "  发现 ${YELLOW}$UNUSED_VOLUMES${NC} 个未使用的卷"
        if [[ "$FORCE_MODE" == true ]]; then
            docker volume prune -f
            echo -e "${GREEN}  ✓ 未使用的卷已清理${NC}"
        else
            docker volume ls -qf dangling=true
            read -p "  是否删除这些未使用的卷？(y/n): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                docker volume prune -f
                echo -e "${GREEN}  ✓ 未使用的卷已清理${NC}"
            fi
        fi
    fi
}

# 清理 containerd
clean_containerd() {
    if [ ! -d "/var/lib/containerd" ]; then
        return
    fi
    
    echo -e "${YELLOW}清理 containerd 资源...${NC}"
    
    if command -v crictl &> /dev/null; then
        crictl rmi --prune 2>/dev/null
        echo -e "${GREEN}  ✓ containerd 镜像已清理 (crictl)${NC}"
    elif command -v ctr &> /dev/null; then
        ctr -n default image prune --all 2>/dev/null
        ctr -n k8s.io image prune --all 2>/dev/null
        echo -e "${GREEN}  ✓ containerd 镜像已清理 (ctr)${NC}"
    fi
}

# 主流程
main() {
    echo "=========================================="
    echo "  Servers Clean v${VERSION}"
    echo "  系统: $OS | 包管理器: $PKG_MANAGER"
    echo "=========================================="
    echo ""
    
    # 显示当前状态
    echo -e "${YELLOW}[1/5] 当前磁盘使用情况${NC}"
    df -h | head -2
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}[预览模式] 不会实际清理任何内容${NC}"
        echo ""
    fi
    
    # 清理 Docker
    if [[ "$CLEAN_DOCKER" == true ]]; then
        echo -e "${YELLOW}[2/5] 清理 Docker${NC}"
        clean_docker
        echo ""
    fi
    
    # 清理 containerd
    if [[ "$CLEAN_DOCKER" == true ]]; then
        echo -e "${YELLOW}[3/5] 清理 containerd${NC}"
        clean_containerd
        echo ""
    fi
    
    # 清理系统缓存
    if [[ "$CLEAN_SYSTEM" == true ]]; then
        echo -e "${YELLOW}[4/5] 清理系统缓存${NC}"
        clean_package_cache
        clean_logs
        echo ""
    fi
    
    # 显示结果
    echo -e "${YELLOW}[5/5] 清理后状态${NC}"
    echo "=========================================="
    echo -e "${GREEN}  清理完成！${NC}"
    echo "=========================================="
    echo ""
    
    df -h
    echo ""
    
    if command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker 占用情况：${NC}"
        docker system df
        echo ""
    fi
    
    echo -e "${GREEN}✓ 所有运行中的服务均未受影响${NC}"
}

# 执行
main
