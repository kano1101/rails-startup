#!/bin/zsh
set -e

if [ $# -ne 2 ]; then
    echo '第一引数にアプリ名、第二引数にアプリを置くディレクトリパスの指定が必須です。(例: rails_env_setup.sh example-app ~/development/)'
    exit 1
fi

SCRIPT_DIR="$(cd $(dirname $0); pwd)"
APP_NAME="$1"
BASE_DIR="$2"

cd $BASE_DIR

if [ -d $APP_NAME ];then
    echo "ディレクトリ $APP_NAME がすでに存在するため作成できません。"
    exit 1
fi

# アプリ名が有効かどうか検証
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;アプリ名が有効であるか確認します。'
cd "$SCRIPT_DIR"
! sh is_kebab.sh          $APP_NAME && echo 'アプリ名はケバブケースにしてください。' && exit 1
! sh can_heroku_create.sh $APP_NAME && echo "heroku上に $APP_NAME を作成できません。" && exit 1
! sh can_github_create.sh $APP_NAME && echo "GitHub上に $APP_NAME を作成できません。" && exit 1
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;アプリの作成が可能であることが確認できました。'
cd -

# herokuにアプリケーションを作成
echo ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;アプリ $APP_NAME をheroku上に作成します。"
cd "$SCRIPT_DIR"
ruby -e "require './heroku_util.rb'; h = HerokuUtil.new(ARGV[0]); h.create_and_setup_as_cleardb_ignite" $APP_NAME
cd -
echo ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;アプリ $APP_NAME をheroku上に作成しました。"

# GitHubにリポジトリを作成
echo ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;リポジトリ $APP_NAME をGitHub上に作成します。"
gh repo create $APP_NAME --private -y
echo ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;リポジトリ $APP_NAME をGitHub上に作成しました。"

# origin/mainの設定 TODO
cd $APP_NAME
cat <<EOF > README.md
# $APP_NAME
EOF
rm -f .git/hooks/pre-push
git switch -c main
git add .
git commit -m 'Initial commit!'
git push
cat <<EOF > .git/hooks/pre-push
#!/bin/zsh

# pushを禁止するブランチ
readonly MAIN='main'

while read local_ref local_sha1 remote_ref remote_sha1
do
  if [[ "\${remote_ref##refs/heads/}" = \$MAIN ]]; then
    echo -e "\033[0;32mDo not push to\033[m\033[1;34m main\033[m \033[0;32mbranch\033[m"
    exit 1
  fi
done
EOF
chmod 744 .git/hooks/pre-push
cd ../

# Bundlerの更新
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;BundlerなどのGemの更新を行います。'
gem update --system

echo ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;$APP_NAME ディレクトリ内作業を行います。"
cd $APP_NAME

# Docker周りの設定
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;Docker周りの設定を行います。'
cat <<EOF > entrypoint.sh
#!/bin/bash
set -e
rm -f tmp/pids/server.pid
exec "\$@"
EOF
chmod 744 entrypoint.sh
cat <<EOF > start.sh
#!/bin/sh
if [ "${RAILS_ENV}" = "production" ]
then
    bundle exec rails assets:precompile
fi
echo "PORT $PORT"
bundle exec rails s -p ${PORT:-3000} -b 0.0.0.0
EOF
chmod 744 start.sh
cat <<EOF > Dockerfile
FROM ruby:3.0
ENV RAILS_ENV=production
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
  && apt-get update -qq \
  && apt-get install -y nodejs yarn
WORKDIR /app
COPY ./src /app
RUN bundle config --local set path 'vendor/bundle' \
  && bundle install
COPY entrypoint.sh /entrypoint.sh
RUN chmod 744 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 3000
COPY start.sh /start.sh
RUN chmod 744 /start.sh
CMD ["sh", "/start.sh"]
EOF

# docker-compose.ymlの生成
cat <<EOF > docker-compose.yml
version: '3'
services:
  db:
    image: mysql:8.0
    command: --default-authentication-plugin=mysql_native_password
    volumes:
      - ./src/db/mysql_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: password
    platform: linux/x86_64
  web:
    build: .
    command: bash -c "rm -f tmp/pids/server.pid && bundle exec rails s -p 3000 -b '0.0.0.0'"
    volumes:
      - ./src:/app
    ports:
      - "3000:3000"
    environment:
      RAILS_ENV: development
    depends_on:
      - db
EOF

# Railsアプリケーションローカルディレクトリの作成
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;Railsアプリケーションの置くディレクトリをsrc以下とするためディレクトリを作成します。'
mkdir src

# Railsアプリケーションの雛形作成
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;Railsアプリケーションの雛形を作成します。'
cd src/
bundle init
echo "gem 'rails'" >> Gemfile
cd ../

# Dockerクリーンアップ
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose down --rmi all --volumes --remove-orphansを実行します。'
docker-compose down --rmi all --volumes --remove-orphans
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker system prune --all -fを実行します。'
docker system prune --all -f

# new build up
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose run web bundle exec rails new . --force --database=mysqlを行います。'
docker-compose run web bundle exec rails new . --force --database=mysql
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose build --no-cacheを行います。'
docker-compose build --no-cache # rails new より先に行う必要がある様子だったがここに置いてみた。ここではbundle installも内部で行われているのだろうか？
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose up -dを実行します。'
docker-compose up -d

# Railsのデータベースの設定
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;Railsのデータベースの設定を行います。'
cd src
CONFIG_DATABASE_YML="$(pwd)/config/database.yml"
cat <<EOF > $CONFIG_DATABASE_YML
# MySQL. Versions 5.5.8 and up are supported.
#
# Install the MySQL driver
#   gem install mysql2
#
# Ensure the MySQL gem is defined in your Gemfile
#   gem 'mysql2'
#
# And be sure to use new-style password hashing:
#   https://dev.mysql.com/doc/refman/5.7/en/password-hashing.html
#
default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  username: root
  password: password
  host: db

development:
  <<: *default
  database: app_development

# Warning: The database defined as "test" will be erased and
# re-generated from your development database when you run "rake".
# Do not set this db to the same as development or production.
test:
  <<: *default
  database: app_test
  host: <%= ENV.fetch("APP_DATABASE_HOST") { 'db' } %>

# As with config/credentials.yml, you never want to store sensitive information,
# like your database password, in your source code. If your source code is
# ever seen by anyone, they now have access to your database.
#
# Instead, provide the password or a full connection URL as an environment
# variable when you boot the app. For example:
#
#   DATABASE_URL="mysql2://myuser:mypass@localhost/somedatabase"
#
# If the connection URL is provided in the special DATABASE_URL environment
# variable, Rails will automatically merge its configuration values on top of
# the values provided in this file. Alternatively, you can specify a connection
# URL environment variable explicitly:
#
#   production:
#     url: <%= ENV['MY_APP_DATABASE_URL'] %>
#
# Read https://guides.rubyonrails.org/configuring.html#configuring-a-database
# for a full overview on how database connection configuration can be specified.
#
production:
  <<: *default
  database: <%= ENV['APP_DATABASE'] %>
  username: <%= ENV['APP_DATABASE_USERNAME'] %>
  password: <%= ENV['APP_DATABASE_PASSWORD'] %>
  host: <%= ENV['APP_DATABASE_HOST'] %>
EOF
cd ../

# Railsのデータベースを作成
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;Railsのデータベースを作成します。'
docker-compose exec web bundle exec rails db:create

# 作業ディレクトリの分離
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;Rails関連ファイルとGit関連ファイルの構造を最適化します。'
rm -rf src/.git
mv src/.gitignore .gitignore
mv src/.gitattributes .gitattributes
CURRENT_DOT_GITIGNORE="$(pwd)/.gitignore"
cd "$SCRIPT_DIR"
ruby -e "require './to_src.rb'; to_src(ARGV[0])" $CURRENT_DOT_GITIGNORE
sh insert-line-to-file-last.sh "$CURRENT_DOT_GITIGNORE" "
**/.DS_Store
**/.env
src/db/mysql_data
"
cd -

# RSpecとrexmlとconfig/application.rbの設定 TODO : config.hosts << '$APP_NAME.herokuapp.com' は必要ないか？
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;RSpecとrexmlとconfig/application.rbの設定を行います。'
cd src
CURRENT_GEMFILE="$(pwd)/Gemfile"
CONFIG_APPLICATION_RB="$(pwd)/config/application.rb"
cd "$SCRIPT_DIR"
sh insert-line-to-file-after.sh "$CURRENT_GEMFILE" "group :development, :test do" "  gem 'rspec-rails'"
sh insert-line-to-file-after.sh "$CURRENT_GEMFILE" "group :test do" "  gem 'rexml'"
sh insert-line-to-file-after.sh "$CONFIG_APPLICATION_RB" "# config.eager_load_paths << Rails.root.join" "
    config.generators do |g|
      g.test_framework :rspec,
        fixtures: false,
        view_specs: false,
        helper_specs: false,
        routing_specs: false
    end
    config.hosts << '.example.com'
    config.hosts << '$APP_NAME.herokuapp.com'
"
cd -
rm -rf test/
cd ../

# Railsのライブラリを追加
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;devise, pry-rails, dotenv-railsのライブラリをGemfileに追加します。'
cd src
CURRENT_GEMFILE="$(pwd)/Gemfile"
cd "$SCRIPT_DIR"
sh insert-line-to-file-last.sh "$CURRENT_GEMFILE" "
gem 'pry-rails'
gem 'dotenv-rails'
gem 'devise'
"
cd -
cd ../

echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose downを実行します。'
docker-compose down
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose build --no-cacheを行います。'
docker-compose build --no-cache
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose up -dを実行します。'
docker-compose up -d

echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose exec web bundle exec rails webpacker:installを行います。'
docker-compose exec web bundle exec rails webpacker:install # TODO : これはどこで必要かわからない
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose exec web bundle exec rails generate rspec:installを実行します。'
docker-compose exec web bundle exec rails generate rspec:install
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose exec web bundle exec rails generate devise:installを実行します。'
docker-compose exec web bundle exec rails generate devise:install

echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;devise:installに従いコードの追加を実行します。'
cd src
DEVELOPMENT_RB="$(pwd)/config/environments/development.rb"
ROUTES_RB="$(pwd)/config/routes.rb"
APPLICATION_HTML_ERB="$(pwd)/app/views/layouts/application.html.erb"
cd "$SCRIPT_DIR"
sh insert-line-to-file-after.sh "$DEVELOPMENT_RB" "# config.action_cable.disable_request_forgery_protection = true" "
  config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }
"
sh insert-line-to-file-before.sh "$ROUTES_RB" "end" "
  root to: 'home#index'
"
sh insert-line-to-file-before.sh "$APPLICATION_HTML_ERB" "<%= yield %>" "
    <p class="notice"><%= notice %></p>
    <p class="alert"><%= alert %></p>
"
cd -
cd ../
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose exec web bundle exec rails generate devise:viewsを実行します。'
docker-compose exec web bundle exec rails generate devise:views

echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose exec web bundle exec rails generate controller home indexを実行します。'
docker-compose exec web bundle exec rails generate controller home index
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose exec web bundle exec rails generate devise Userを実行します。'
docker-compose exec web bundle exec rails generate devise User
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;docker-compose exec web bundle exec rails db:migrateを実行します。'
docker-compose exec web bundle exec rails db:migrate


# CircleCIのconfig.yml設定
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;CircleCIのconfig.ymlの設定を行います。'
RAILS_MASTER_KEY="$(cat src/config/master.key)"
cd "$SCRIPT_DIR"
ruby -e "require './heroku_util.rb'; h = HerokuUtil.new(ARGV[0]); h.config_add('RAILS_MASTER_KEY', ARGV[1])" $APP_NAME $RAILS_MASTER_KEY
cd -
mkdir .circleci
cat <<EOF > .circleci/config.yml
version: 2.1
orbs:
  ruby: circleci/ruby@1.1.3
  heroku: circleci/heroku@1.2.3
  node: circleci/node@4.4.0

jobs:
  build:
    docker:
      - image: circleci/ruby:3.0
    working_directory: ~/$APP_NAME/src
    steps:
      - checkout:
          path: ~/$APP_NAME
      - run:
          name: bundleにプラットフォームをx86_64-linuxとするよう指定
          command: bundle lock --add-platform x86_64-linux
      - ruby/install-deps

  test:
    docker:
      - image: circleci/ruby:3.0
      - image: circleci/mysql:5.5
        environment:
          MYSQL_ROOT_PASSWORD: password
          MYSQL_DATABASE: app_test
          MYSQL_USER: root
    environment:
      BUNDLE_JOBS: "3"
      BUNDLE_RETRY: "3"
      APP_DATABASE_HOST: "127.0.0.1"
      RAILS_ENV: test
    working_directory: ~/$APP_NAME/src
    steps:
      - checkout:
          path: ~/$APP_NAME 
      - run:
          name: bundleにプラットフォームをx86_64-linuxとするよう指定
          command: bundle lock --add-platform x86_64-linux
      - ruby/install-deps
      - node/install:
          install-yarn: true
      - run: node --version
      - run:
          name: webpacker:install
          command: bundle exec rails webpacker:install
      - run:
          name: webpacker:compile
          command: bundle exec rails webpacker:compile
      - run:
          name: Database setup
          command: bundle exec rails db:migrate
      - run:
          name: test
          command: bundle exec rspec

  deploy:
    docker:
      - image: circleci/ruby:3.0
    steps:
      - checkout
      - setup_remote_docker:
          version: 19.03.13
      - heroku/install
      - run:
          name: heroku login
          command: heroku container:login
      - run:
          name: push docker image
          command: heroku container:push web -a \$HEROKU_APP_NAME
      - run:
          name: release docker image
          command: heroku container:release web -a \$HEROKU_APP_NAME
      - run:
          name: database setup
          command: heroku run bundle exec rails db:migrate RAILS_ENV=production -a \$HEROKU_APP_NAME

workflows:
  version: 2
  build_test_and_deploy:
    jobs:
      - build
      - test:
          requires:
            - build
      - deploy:
          requires:
            - test
          filters:
            branches:
              only: main
EOF

echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
1. CircleCIへプロジェクト登録を完了させてください。

'
open "https://app.circleci.com/projects/project-dashboard/github/kano1101/"
echo '設定が終えたらEnterを押してください。: (enter) '
read Wait

echo ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
2. 次にAdd Environment Variableにて以下を設定してください。

  a) HEROKU_APP_NAME $APP_NAME
  b) HEROKU_API_KEY  \$HEROKU_API_KEY

"
open "https://app.circleci.com/settings/project/github/kano1101/$APP_NAME/environment-variables"
echo '設定が終えたらEnterを押してください。: (enter) '
read Wait

echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
3. 最後にherokuに作成したアプリのブートタイムアウトの時間を120秒に変更してください。

'
open "https://tools.heroku.support/limits/boot_timeout"
echo '設定が終えたらEnterを押してください。: (enter) '
read Wait

# Railsのローカルでの画面が表示されるかどうか確認
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;開発環境での表示を確認してください。'
docker-compose down
docker-compose up -d
sleep 10
open http://0.0.0.0:3000
echo '表示が確認できたらEnterを押してください。: (enter) '
read Wait
docker-compose down

# 完了をコミット
echo ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;最後にコミットをして完了とします。'
git switch -c init
git add .
git commit -m 'Initial setup finished!'
git push
gh pr create -f
gh pr view -w


echo 'done.'
exit 0
