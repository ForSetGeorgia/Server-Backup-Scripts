require_relative 'backup_scripts/server_backup'

namespace :backup do
  desc 'Run the server backup'
  task :run do
    run_server_backup
  end

  namespace :schedule do
    desc 'Schedule cron job to scrape daily'
    task :run_daily do
      `bundle exec whenever -i`
    end
  end

end
