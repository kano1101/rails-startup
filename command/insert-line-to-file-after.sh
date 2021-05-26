#!/bin/sh

if [ $# -ne 3 ]; then
    echo '第一引数に挿入対象のファイル名、第二引数に挿入行の直前に存在する文字列、第三引数に挿入したい文字列を指定してください。'
fi

ruby -e 'File.write(ARGV[0], File.read(ARGV[0]).gsub(Regexp.new("(^.*" + ARGV[1] + ".*\n)"), "\\1#{ARGV[2]}\n"))' "$1" "$2" "$3"
