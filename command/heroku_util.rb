require 'platform-api'
require_relative './is_kebab.rb'

class HerokuUtil

  OAUTH_TOKEN_FILE = ".env"
  
  def initialize(app_name)
    raise NameError, 'アプリ名はケバブケースで指定してください。' unless is_kebab?(app_name)
    f = File.open(OAUTH_TOKEN_FILE)
    token = f.read.chomp
    f.close
    if token == '' 
      token = %x[heroku authorizations:create -d "Platform API token" | grep "Token:"].gsub!(/Token:\s*/, '').chomp
      f = File.open(OAUTH_TOKEN_FILE, 'w')
      f.puts token
      f.close
    end
    @heroku = PlatformAPI.connect_oauth(token)
    @app_name = app_name
  end

  def can_create?
    config_ref
  rescue Excon::Error::NotFound
    true
  rescue Excon::Error::Forbidden
    false
  else
    false
  end

  def config_add(env_name, env_value)
    envs = @heroku.config_var.update(@app_name, {env_name => env_value})
    [env_name, envs[env_name]]
  end
  
  def create
    raise NameError, 'アプリが作成できません。' unless can_create?
    @heroku.app.create({'name'=>@app_name})
    added = @heroku.app.info(@app_name)['owner']['email']
    email = "a.kano1101@gmail.com"
    added == email
  end
  def delete
    @heroku.app.delete(@app_name)
  end
  
  private

  def addon_create(plan_name)
    info = @heroku.addon.create(@app_name, {'plan' => plan_name})
    info['plan']['name']
  end
  def config_ref
    envs = @heroku.config_var.info_for_app(@app_name)
    envs
  end
  def config_ref_of(env_name)
    envs = @heroku.config_var.info_for_app(@app_name)
    envs[env_name]
  end
  def config_add_options
    envs = ['RAILS_SERVE_STATIC_FILES', 'RAILS_LOG_TO_STDOUT']
    added = envs.map do |env|
      config_add(env, 'true')
    end
    added
  end
  def config_add_cleardb_ignite
    envs = ['APP_DATABASE', 'APP_DATABASE_USERNAME', 'APP_DATABASE_PASSWORD', 'APP_DATABASE_HOST']
    cleardb_database_url = config_ref_of('CLEARDB_DATABASE_URL')
    m = /mysql:\/\/(?<APP_DATABASE_USERNAME>\w{14}):(?<APP_DATABASE_PASSWORD>\w{8})@(?<APP_DATABASE_HOST>.{27})\/(?<APP_DATABASE>.{22})\?reconnect=true/.match(cleardb_database_url)
    added = envs.map do |env|
      config_add(env, m[env])
    end
    added
  end

  public
  
  def create_and_setup_as_cleardb_ignite
    create
    addon_create("cleardb:ignite")
    config_add_cleardb_ignite
    config_add_options
    envs = config_ref
    puts 'herokuアプリのセットアップに成功しました。'
    envs
  end
end

