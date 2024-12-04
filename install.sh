#!/bin/sh

URL_ADDRESS="https://raw.githubusercontent.com/Beliefei/Tset_Shell/refs/heads/main/gitpush.sh"

# 获取当前目录的所在git仓库的根目录
GIT_PATH=$(git rev-parse --show-toplevel)
if [ $? -ne 0 ]; then
    echo "当前目录及其父目录不是git仓库的根目录"
    exit 1
fi

# 检查是否存在gitpush.sh文件，如果不存在则下载，存在检查是否需要更新
if [! -f "$GIT_PATH/gitpush.sh" ]; then
    echo "gitpush.sh文件不存在"
    echo "即将下载gitpush.sh文件"
else
    echo "gitpush.sh文件存在"
    echo "即将检查gitpush.sh文件是否需要更新"
    # 获取当前gitpush.sh文件的MD5
    GITPUSH_MD5=$(md5 -q "$GIT_PATH/gitpush.sh")
    # 获取远程gitpush.sh文件的MD5
    REMOTE_GITPUSH_MD5=$(curl -s $URL_ADDRESS | md5 -q)
    # 比较MD5
    if [ $GITPUSH_MD5 = $REMOTE_GITPUSH_MD5 ]; then
        echo "gitpush.sh文件不需要更新"
    else
        echo "gitpush.sh文件需要更新"
        # 下载gitpush.sh文件到一个临时文件中
        curl -s $URL_ADDRESS -o "$GIT_PATH/gitpush.sh.tmp"
        # 下载成功后，将临时文件重命名为gitpush.sh文件，并删除临时文件;下载失败则删除临时文件
        if [ $? -ne 0 ]; then
            echo "gitpush.sh文件下载失败"
            rm -f "$GIT_PATH/gitpush.sh.tmp"
            exit 1
        fi
        
        mv "$GIT_PATH/gitpush.sh.tmp" "$GIT_PATH/gitpush.sh"
        rm -f "$GIT_PATH/gitpush.sh.tmp"
        # 给gitpush.sh文件添加执行权限
        chmod +x "$GIT_PATH/gitpush.sh"
        echo "gitpush.sh文件更新成功"
    fi
fi
