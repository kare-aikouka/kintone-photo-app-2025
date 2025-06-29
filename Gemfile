# Gemfile

source "https://rubygems.org"
ruby "3.1.7"

# === 基本的なRailsのgem ===
gem "rails", "~> 7.2.2", ">= 7.2.2.1"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
# gem "jsbundling-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "cssbundling-rails"
gem "jbuilder"
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem 'sassc-rails'
gem "importmap-rails"

# === ここから、古いアプリで使われていた重要なgemを追加 ===
gem "dotenv-rails" # .env ファイルを読み込むために追加
gem 'kintone', github: 'ruffnote/kintone', branch: 'basic-auth', ref: '0f1cb77' # メインの場所へ移動
gem 'config'
gem 'newrelic_rpm'
gem "haml-rails"
gem 'rack-cors'
# =======================================================

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  
  # === 古いアプリで使われていた開発用のgem ===
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'pry-byebug'
  gem 'pry-rails'
  # ======================================
end

group :development do
  gem "web-console"
  gem "error_highlight", ">= 0.4.0", platforms: [ :ruby ]
  
  # === 古いアプリで使われていた開発用のgem ===
  gem 'listen', '~> 3.7'
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.1.0'
  # ======================================
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  
  # === 古いアプリで使われていたテスト用のgem ===
  gem 'rspec-rails', '~> 3.7'
  gem 'factory_bot_rails'
  # =======================================
end

# コメントアウトされた不要なgemは省略しました
# gem "bcrypt" など、もし必要であれば後で追加できます