#!/bin/bash

# 设置错误处理
set -e
set -o pipefail

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# 环境检查
check_environment() {
    log_info "开始环境检查"

    # 检查必需的命令
    local required_commands=("git" "yq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "找不到必需的命令: $cmd"
            log_info "尝试使用 Homebrew 安装..."
            if ! brew install "$cmd"; then
                log_error "安装 $cmd 失败"
                return 1
            fi
        fi
    done

    # 检查配置文件
    local yml_file="$SCRIPT_DIR/../pod_tools/pods_config.yml"
    log_info "正在检查配置文件: $yml_file"
    
    if [ ! -f "$yml_file" ]; then
        log_error "找不到配置文件: $yml_file"
        log_info "当前脚本目录: $SCRIPT_DIR"
        log_info "请确保配置文件存在于正确的位置"
        return 1
    fi

    if [ ! -r "$yml_file" ]; then
        log_error "无法读取配置文件: $yml_file"
        return 1
    fi

    # 显示配置文件内容（用于调试）
    log_info "配置文件内容:"
    cat "$yml_file"
    echo ""

    # 检查配置文件内容
    local repo_paths
    repo_paths=$(yq e '.pods[].path' "$yml_file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_error "解析配置文件失败，请检查 YAML 格式是否正确"
        return 1
    fi

    if [ -z "$repo_paths" ]; then
        log_error "配置文件中没有找到任何仓库配置 (.pods[].path)"
        return 1
    fi

    # 显示找到的仓库路径（用于调试）
    log_info "找到以下仓库配置:"
    echo "$repo_paths" | while read -r path; do
        echo "  - $path"
    done

    log_info "环境检查通过"
}

# 初始化仓库数组
init_repos() {
    local yml_file="$SCRIPT_DIR/../pod_tools/pods_config.yml"
    
    # 读取配置文件中的仓库路径
    while IFS= read -r path; do
        if [ -n "$path" ]; then
            local full_path="$SCRIPT_DIR/../$path"
            repos+=("$full_path")
        fi
    done < <(yq e '.pods[].path' "$yml_file" 2>/dev/null)

    # 显示找到的仓库（用于调试）
    if [ ${#repos[@]} -eq 0 ]; then
        log_error "没有找到任何仓库配置"
        log_info "请检查配置文件格式是否正确"
        return 1
    else
        log_info "找到 ${#repos[@]} 个仓库:"
        for repo in "${repos[@]}"; do
            echo "  - $repo"
        done
    fi
}

# 检查 Git 仓库状态
check_git_status() {
    local repo_path=$1
    cd "$repo_path" || return 1

    # 检查是否是 git 仓库
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "'$repo_path' 不是有效的 Git 仓库"
        return 1
    fi

    # 检查远程仓库连接
    if ! git ls-remote origin HEAD &> /dev/null; then
        log_error "无法连接到远程仓库"
        return 1
    fi

    # 检查工作目录状态
    if ! git diff --quiet HEAD; then
        log_warn "仓库 '$repo_path' 有未提交的更改"
    fi
}

# 检查分支是否存在
check_branch_exists() {
    local branch_name=$1
    local repo_path=$2
    local local_repo_name=$(get_repo_name "$repo_path")

    # 检查本地分支
    if ! git branch --list "$branch_name" | grep -q "$branch_name"; then
        # 检查远程分支
        if ! git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
            log_error "在 $local_repo_name 中找不到分支 '$branch_name'（本地和远程都不存在）"
            return 1
        fi
    fi
    return 0
}

# 获取仓库名称
get_repo_name() {
    local repo_path=$1
    basename "$repo_path"
}

# 执行推送操作
do_git_push() {
    local repo_path=$1
    local branch_name=$2
    local repo_name=$(basename "$repo_path")
    
    # 检查是否存在 gitpush.sh 脚本
    if [ -f "$repo_path/gitpush.sh" ]; then
        log_info "使用 gitpush.sh 脚本进行推送"
        if ! bash "$repo_path/gitpush.sh"; then
            log_error "使用 gitpush.sh 推送失败"
            return 1
        fi
    else
        log_info "使用 git push 命令进行推送"
        if ! git push origin "$branch_name"; then
            log_error "推送失败"
            return 1
        fi
    fi
    return 0
}

# 更新 YAML 文件中的分支名称
update_branch_in_yaml() {
    local new_branch=$1
    local repo_path=$2
    local yml_file="$SCRIPT_DIR/../pod_tools/pods_config.yml"
    
    # 获取仓库名称
    local repo_name=$(basename "$repo_path")
    
    # 使用仓库名称来匹配和更新配置
    if ! yq e -i "(.pods[] | select(.name == \"$repo_name\").branch) = \"$new_branch\"" "$yml_file"; then
        log_error "更新 YAML 文件失败: $repo_name"
        return 1
    fi
    log_info "已更新 $repo_name 的分支为 '$new_branch'"
}

# 处理提交操作
do_commit() {
    local commit_message=$1
    if [ -z "$commit_message" ]; then
        log_error "commit 操作需要提交信息"
        echo "用法: $0 commit \"提交信息\""
        return 1
    fi

    for repo in "${repos[@]}"; do
        echo ""
        cd "$current_dir" || exit 1
        if ! cd "$repo"; then
            log_error "无法访问仓库目录 '$repo'"
            continue
        fi

        local_repo_name=$(get_repo_name "$repo")
        if ! check_git_status "$repo"; then
            continue
        fi

        current_branch=$(git symbolic-ref --short HEAD)
        log_info "正在处理: $local_repo_name (分支: $current_branch)"

        if ! git add .; then
            log_error "git add 失败"
            continue
        fi

        if ! git commit -m "$commit_message"; then
            log_error "git commit 失败"
            continue
        fi

        log_info "成功提交更改到 $local_repo_name"
    done
}

# 处理推送操作
do_push() {
    # 检查 repos 数组是否为空
    if [ ${#repos[@]} -eq 0 ]; then
        log_error "没有找到要处理的仓库"
        return 1
    fi

    for repo in "${repos[@]}"; do
        echo ""
        cd "$current_dir" || exit 1
        if ! cd "$repo"; then
            log_error "无法访问仓库目录 '$repo'"
            continue
        fi

        local_repo_name=$(get_repo_name "$repo")
        if ! check_git_status "$repo"; then
            continue
        fi

        # 获取当前分支
        current_branch=$(git symbolic-ref --short HEAD)
        log_info "正在处理: $local_repo_name (当前分支: $current_branch)"

        # 执行推送
        if ! do_git_push "$repo" "$current_branch"; then
            continue
        fi

        log_info "成功推送更改到 $local_repo_name"
    done
}

# 处理拉取操作
do_pull() {
    for repo in "${repos[@]}"; do
        echo ""
        cd "$current_dir" || exit 1
        if ! cd "$repo"; then
            log_error "无法访问仓库目录 '$repo'"
            continue
        fi

        local_repo_name=$(get_repo_name "$repo")
        if ! check_git_status "$repo"; then
            continue
        fi

        current_branch=$(git symbolic-ref --short HEAD)
        log_info "正在处理: $local_repo_name (分支: $current_branch)"

        if ! git pull origin "$current_branch"; then
            log_error "拉取更新失败"
            continue
        fi

        log_info "成功拉取 $local_repo_name 的更新"
    done
}

# 处理合并操作
do_merge() {
    local target_branch=$1
    local auto_push=$2

    if [ -z "$target_branch" ]; then
        log_error "merge 操作需要目标分支名"
        echo "用法: $0 merge <目标分支> [push]"
        return 1
    fi

    # 检查 repos 数组是否为空
    if [ ${#repos[@]} -eq 0 ]; then
        log_error "没有找到要处理的仓库"
        return 1
    fi

    # 显示要处理的仓库
    log_info "将在以下仓库中执行合并操作:"
    for repo in "${repos[@]}"; do
        echo "  - $(get_repo_name "$repo")"
    done
    echo ""

    for repo in "${repos[@]}"; do
        echo ""
        cd "$current_dir" || exit 1
        if ! cd "$repo"; then
            log_error "无法访问仓库目录 '$repo'"
            continue
        fi

        local_repo_name=$(get_repo_name "$repo")
        if ! check_git_status "$repo"; then
            continue
        fi

        log_info "正在处理: $local_repo_name"

        # 获取当前分支
        current_branch=$(git symbolic-ref --short HEAD)
        log_info "当前分支: $current_branch"

        # 先获取远程更新
        if ! git fetch origin; then
            log_error "获取远程更新失败，将使用本地分支的改变进行合并"
        fi

        # 检查目标分支是否存在
        if ! check_branch_exists "$target_branch" "$repo"; then
            continue
        fi

        # 确保当前分支是最新的
        if ! git pull origin "$current_branch"; then
            log_error "更新当前分支失败，可能是当前分支只存在本地"
        fi

        # 尝试合并目标分支到当前分支
        log_info "正在将 '$target_branch' 合并到 '$current_branch'"
        if ! git merge "origin/$target_branch" --no-ff --log --no-edit; then
            log_error "合并分支失败，请手动解决冲突"
            continue
        fi

        # 如果指定了自动推送
        if [ "$auto_push" = "push" ]; then
            log_info "正在推送更改到远程..."
            if ! do_git_push "$repo" "$current_branch"; then
                continue
            fi
            log_info "成功推送更改到远程"
        else
            log_info "合并完成，使用 'push' 命令推送更改"
        fi

        log_info "成功将 $target_branch 合并到 $current_branch 在 $local_repo_name"
    done
}

# 处理创建分支操作
do_create() {
    local new_branch=$1
    local base_branch=$2
    local should_push=${3:-"push"}  # 默认推送

    if [ -z "$new_branch" ] || [ -z "$base_branch" ]; then
        log_error "create 操作需要新分支名和基于分支名"
        echo "用法: $0 create <新分支名> <基于分支名> [no-push]"
        echo "  添加 no-push 参数禁用自动推送"
        return 1
    fi

    # 检查 repos 数组是否为空
    if [ ${#repos[@]} -eq 0 ]; then
        log_error "没有找到要处理的仓库"
        return 1
    fi

    # 显示要处理的仓库
    log_info "将在以下仓库中创建新分支 '$new_branch' (基于 '$base_branch'):"
    for repo in "${repos[@]}"; do
        echo "  - $(get_repo_name "$repo")"
    done
    echo ""

    for repo in "${repos[@]}"; do
        echo ""
        cd "$current_dir" || exit 1
        if ! cd "$repo"; then
            log_error "无法访问仓库目录 '$repo'"
            continue
        fi

        local_repo_name=$(get_repo_name "$repo")
        if ! check_git_status "$repo"; then
            continue
        fi

        log_info "正在处理: $local_repo_name"

        # 先获取远程更新
        if ! git fetch origin; then
            log_error "获取远程更新失败，可能远程分支并不存在"
        fi

        # 检查基础分支是否存在
        if ! check_branch_exists "$base_branch" "$repo"; then
            continue
        fi

        # 切换到基础分支
        if ! git checkout "$base_branch"; then
            log_error "切换到基础分支失败"
            continue
        fi

        # 更新基础分支
        if ! git pull origin "$base_branch"; then
            log_error "更新基础分支失败"
            continue
        fi

        # 创建并切换到新分支
        if ! git checkout -b "$new_branch"; then
            log_error "创建新分支失败"
            continue
        fi

        # 根据参数决定是否推送
        if [ "$should_push" != "no-push" ]; then
            log_info "正在推送新分支到远程..."
            if ! git push --set-upstream origin "$new_branch"; then
                if ! do_git_push "$repo" "$new_branch"; then
                    log_error "推送新分支失败"
                    continue
                fi
                # 设置上游分支
                if ! git branch --set-upstream-to="origin/$new_branch" "$new_branch"; then
                    log_error "设置上游分支失败"
                    continue
                fi
            fi
            log_info "成功推送新分支到远程"
        else
            log_info "跳过推送新分支到远程"
        fi

        # 更新 YAML 文件
        update_branch_in_yaml "$new_branch" "$repo"

        log_info "成功创建新分支 $new_branch 在 $local_repo_name"
    done
}

# 处理切换分支操作
do_switch() {
    local target_branch=$1
    if [ -z "$target_branch" ]; then
        log_error "switch 操作需要分支名"
        echo "用法: $0 switch <分支名>"
        return 1
    fi

    # 检查 repos 数组是否为空
    if [ ${#repos[@]} -eq 0 ]; then
        log_error "没有找到要处理的仓库，请检查配置文件: $SCRIPT_DIR/../pod_tools/pods_config.yml"
        return 1
    fi

    # 显示要处理的仓库
    log_info "将在以下仓库中切换到分支 '$target_branch':"
    for repo in "${repos[@]}"; do
        echo "  - $(get_repo_name "$repo")"
    done
    echo ""

    for repo in "${repos[@]}"; do
        echo ""
        cd "$current_dir" || exit 1
        if ! cd "$repo"; then
            log_error "无法访问仓库目录 '$repo'"
            continue
        fi

        local_repo_name=$(get_repo_name "$repo")
        if ! check_git_status "$repo"; then
            continue
        fi

        log_info "正在处理: $local_repo_name"

        # 获取当前分支
        current_branch=$(git symbolic-ref --short HEAD)
        if [ "$current_branch" = "$target_branch" ]; then
            log_info "已经在 '$target_branch' 分支上"
            # 即使已经在目标分支上，也要更新配置文件
            if ! update_branch_in_yaml "$target_branch" "$repo"; then
                log_error "更新配置文件失败"
                continue
            fi
            # 确保分支是最新的
            if ! git pull origin "$target_branch"; then
                log_error "拉取分支更新失败"
                continue
            fi
            continue
        fi

        # 先获取远程更新
        if ! git fetch origin; then
            log_error "获取远程更新失败"
            continue
        fi

        # 检查分支是否存在
        if ! check_branch_exists "$target_branch" "$repo"; then
            continue
        fi

        # 尝试切换分支
        if ! git checkout "$target_branch"; then
            log_error "切换到分支 '$target_branch' 失败"
            continue
        fi

        # 尝试拉取更新
        if ! git pull origin "$target_branch"; then
            log_error "拉取分支 '$target_branch' 更新失败， 可能远程分支不存在"
        fi

        # 成功后更新 YAML 文件
        if ! update_branch_in_yaml "$target_branch" "$repo"; then
            log_error "更新配置文件失败"
            continue
        fi

        log_info "成功切换到分支 $target_branch 在 $local_repo_name"
    done
}

# 处理删除分支操作
do_delete() {
    local delete_branch=$1
    if [ -z "$delete_branch" ]; then
        log_error "delete 操作需要分支名"
        echo "用法: $0 delete <分支名>"
        return 1
    fi

    echo -n "确定要删除分支 '$delete_branch' 吗? (Y/N) "
    read -r confirm_delete

    if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
        for repo in "${repos[@]}"; do
            echo ""
            cd "$current_dir" || exit 1
            if ! cd "$repo"; then
                log_error "无法访问仓库目录 '$repo'"
                continue
            fi

            local_repo_name=$(get_repo_name "$repo")
            if ! check_git_status "$repo"; then
                continue
            fi

            log_info "正在处理: $local_repo_name"

            # 尝试删除本地分支
            if git branch -d "$delete_branch" ; then
                log_info "成功删除本地分支 '$delete_branch'"
            else
                log_error "删除本地分支失败"
                log_warn "尝试强制删除本地分支 '$delete_branch'"
                # 从命令行读取是否要强制删除
                echo -n "是否要强制删除本地分支 '$delete_branch'? (Y/N) "
                read -r confirm_force_delete
                if [[ "$confirm_force_delete" =~ ^[Yy]$ ]]; then
                    log_info "强制删除本地分支 '$delete_branch'"
                    if ! git branch -D "$delete_branch" ; then
                        log_error "删除本地分支失败"
                    fi
                else
                    log_info "取消强制删除本地分支 '$delete_branch'"
                fi
            fi

            # 尝试删除远程分支
            # if git push origin --delete "$delete_branch" 2>/dev/null; then
            #     log_info "成功删除远程分支 '$delete_branch'"
            # else
            #     log_error "删除远程分支失败"
            # fi
            echo ""
        done
    else
        log_info "取消删除分支操作"
    fi
}

# 显示帮助信息
display_help() {
    echo "用法: $0 <操作类型> [参数]"
    echo ""
    echo "操作类型:"
    echo "  commit <提交信息>        提交更改，要求提供提交信息"
    echo "  push                    推送当前分支的更改到远程仓库"
    echo "  pull                    拉取当前分支的最新更改"
    echo "  merge <目标分支> [push]  将目标分支合并到当前分支"
    echo "                          添加 push 参数会自动推送到远程"
    echo "  create <新分支名> <基于分支名> [no-push]"
    echo "                         创建并推送新分支"
    echo "                         添加 no-push 参数禁用自动推送"
    echo "  switch <目标分支>        切换到指定分支"
    echo "  delete <分支名>          删除指定分支"
    echo "  help                    显示此帮助信息"
    echo "=========================="
    echo "示例:"
    echo "  $0 commit \"修复了一个重要的 bug\""
    echo "  $0 push"
    echo "  $0 pull"
    echo "  $0 merge main push"
    echo "  $0 create feature_branch base_branch no-push"
    echo "  $0 switch main"
    echo "  $0 delete old_branch"
}

# 主程序开始
# 检查是否提供了操作类型
if [ -z "$1" ]; then
    log_error "操作类型是必需的"
    display_help
    exit 1
fi

log_info "开始环境检查"
# 环境检查
check_environment
log_info "环境检查通过"

# 定义操作类型和参数
operation="$1"
param="$2"
base_branch="$3"

# 读取当前目录
current_dir=$(pwd)

# 初始化仓库数组
init_repos

# 主要操作逻辑
case $operation in
    help)
        display_help
        ;;
    commit)
        do_commit "$param"
        ;;
    push)
        do_push
        ;;
    pull)
        do_pull
        ;;
    merge)
        do_merge "$param" "$base_branch"
        ;;
    create)
        do_create "$param" "$base_branch" "$4"
        ;;
    switch)
        do_switch "$param"
        ;;
    delete)
        do_delete "$param"
        ;;
    *)
        log_error "无效的操作类型: $operation"
        display_help
        exit 1
        ;;
esac
