#!/usr/bin/env bash

# $1 all
GROUP="all"

function showTipCorrectReviewGroup() {
    echo "\033[33m PLS 添加正确的reviewer分组，eg: \033[0m"
    echo "\033[32m \t- all: for all reviewers \033[0m"
    echo "\033[32m \t- na: for all reviewers of ios and android \033[0m"
    echo "\033[32m \t- ios: reviewers of ios \033[0m"
    echo "\033[32m \t- andr: reviewers of android \033[0m"
    echo "\033[32m \t- fe: reviewers of fe \033[0m"
    echo "\033[32m \t- -r: add custom reviewers like this : sh gitpush.sh -r xxxx,yyyy \033[0m"
}

function showSuccessTip() {
    echo ""
    echo ""
    echo "🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉"
    echo "🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉"
    echo "----------------------------------------------------------------------------------"
    echo "----------------------------------------------------------------------------------"
    echo -e "|   \033[32m你做的棒极了，快让小伙伴们来CR下吧！！！ \033[0m "
    echo -e "|   \033[32mYou've done an excellent job! Let the code review now!!!   \033[0m "
    echo "----------------------------------------------------------------------------------"
    echo "----------------------------------------------------------------------------------"
    echo "🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉"
    echo "🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉"
    echo ""
    echo ""
}

function showFailTip() {
    echo ""
    echo ""
    echo "⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️"
    echo "⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️"
    echo "----------------------------------------------------------------------------------"
    echo "----------------------------------------------------------------------------------"
    echo -e "|   \033[31m你做的棒极了，快让小伙伴们来CR下吧！！！ \033[0m "
    echo -e "|   \033[31mYou've done an excellent job! Let the code review now!!!   \033[0m "
    echo "----------------------------------------------------------------------------------"
    echo "----------------------------------------------------------------------------------"
    echo "⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️"
    echo "⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️"
    echo ""
    echo ""
}

# 解析命令行参数
while getopts "r:" opt; do
    case $opt in
        r)  # 追加 reviewer
            IFS=',' read -ra reviewers_arr <<< "$OPTARG"
            for reviewer in "${reviewers_arr[@]}"; do
                reviewers="$reviewers,r=${reviewer}@classup.com"
            done
            ;;
        *)
            echo "Invalid option: -$opt"
            exit 1
            ;;
    esac
done

BR=$(git rev-parse --abbrev-ref HEAD)

# 如果reviewers 参数为空，则使用group的默认配置
if [ -z "$reviewers" ]; then
    echo ""
    echo ""
    echo -e "✅ ✅ ✅ ✅ \033[32mwill push to gerrit for $GROUP reviewers \033[0m"
    echo ""
    echo ""
    DIR=$(dirname "$BASH_SOURCE"})

    if [[ -f ${DIR}/.reviewers/${GROUP}.gitreviewers ]]; then
        while IFS=';' read -r _branch _members; do
            if [[ $BR = "$_branch" ]] || [[ $_branch = "-" ]] || [[ $BR =~ $_branch ]]; then
                _members=${_members:1}
                members="$members,$_members"
                break;
            fi
        done < "$DIR"/.reviewers/"$GROUP".gitreviewers
    else
        echo "[ skip ] - no '.gitreviewers' config found"
    fi

    IFS=','
    for member in $members; do
        if [[ -n "$member" ]]; then
            reviewers="$reviewers,r=$member@classup.com"
        fi
    done
    unset IFS
fi

reviewers=${reviewers:1}
echo "[ checking ] - will push to gerrit for $reviewers"

echo "[ checking ] - current branch is *$BR*"
echo "[ checking ] - will push to branch *$BR*"

git fetch -q
behind=$(git rev-list --left-only --count origin/"$BR"..."$BR")
ahead=$(git rev-list --right-only --count origin/"$BR"..."$BR")
# echo $reviewers

if [[ $behind -gt 0 ]]; then
    echo "[ abort ] - remote branch origin/${BR} is ahead of local branch, rebase first"
    exit 1
fi
if [[ $ahead -le 0 ]]; then
    echo "[ exit ] - no new changes!"
    exit 1
fi

git push origin "$BR":refs/for/"$BR"%"$reviewers"
if [[ $? -ne 0 ]]; then
    showFailTip
    exit 1
fi
showSuccessTip
