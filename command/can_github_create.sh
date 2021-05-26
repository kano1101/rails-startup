#!/bin/zsh

if [ $# -ne 1 ]; then
    echo 'アプリ名(ケバブケースのみ可)が必須です。(例: can_github_create.sh example-app)'
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

gh repo view $1 > /dev/null 2>&1

if [ $? = 1 ]; then
    echo 'GitHub上にアプリが作成可能です。'
    exit 0
else
    echo 'GitHub上にアプリが作成不可です。'
    exit 1
fi
