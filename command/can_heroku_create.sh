#!/bin/zsh

if [ $# -ne 1 ]; then
    echo 'アプリ名(ケバブケースのみ可)が必須です。(例: can_heroku_create.sh example-app)'
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

CAN_CREATE=$(ruby -e "require './heroku_util.rb'; h = HerokuUtil.new(ARGV[0]); p h.can_create?" $1)

if [ $CAN_CREATE = true ]; then
    echo 'heroku上にアプリが作成可能です。'
    exit 0
else
    echo 'heroku上にアプリが作成不可です。'
    exit 1
fi
