#!/usr/bin/env bash
# exit on error
set -o errexit

bundle install
yarn install
# JavaScript is served via importmap from app/javascript. Running the esbuild
# bundle here creates app/assets/builds/machines.js, which collides with the
# importmap-linked app/javascript/machines.js during assets:precompile.
yarn build:css
bundle exec rake assets:precompile
bundle exec rake assets:clean
bundle exec rake db:migrate
