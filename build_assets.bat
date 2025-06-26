@echo off
echo === Building CSS ===
yarn build:css

echo === Precompiling Assets ===
bundle exec rake assetsenvironment
bundle exec rake javascriptbuild

echo === Done! ===
pause