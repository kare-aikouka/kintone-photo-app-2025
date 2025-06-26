# lib/tasks/disable_css_install.rake

# Rakeタスク 'css:build' を無効化する
if Rake::Task.task_defined?("css:build")
  Rake::Task["css:build"].clear
end
