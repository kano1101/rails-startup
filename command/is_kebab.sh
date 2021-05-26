#!/bin/zsh
set -e

if [ $# -ne 1 ]; then
    echo 'ケバブケースかどうかをチェックする文字列の指定が必須です。(例: is_kebab.sh example-app)'
    exit 1
fi

RESULT=$(ruby -e "require './is_kebab.rb'; p is_kebab?(ARGV[0])" $1)

if [ $RESULT = true ]; then
    echo '有効(ケバブケース)です。'
    exit 0
else
    echo 'ケバブケースではありません。'
    exit 1
fi
