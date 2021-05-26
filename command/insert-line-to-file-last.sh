#!/bin/sh

if [ $# -ne 2 ]; then
    echo 'ファイル末尾行に文字列を追加できます。第一引数に挿入対象のファイル名、第二引数に挿入したい文字列を指定してください。'
fi

ruby -e 'File.open(ARGV[0],"a").print("\n#{ARGV[1]}")' "$1" "$2"
