# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "hotwired/turbo-rails.js" # 例
pin_all_from "app/javascript/controllers", under: "controllers" # 例
pin "@hotwired/turbo-rails", to: "https://ga.jspm.io/npm:@hotwired/turbo-rails@7.4.0/app/javascript/turbo/index.js"
pin "machines"
