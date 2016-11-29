#!/usr/bin/env ruby

# backup jumpstart server
# requires s3cmd & ruby

require 'logger'

# main variables

type = 'daily'
server = 'alpha'
bucket = "jsgeorgia-#{server}" # old s3 names could have underscore, new names should have dash
tmp_dir = '/root/tmp'
date = Time.now.strftime('%y-%m-%d')
log = "#{server}_#{type}_backup.log"
log_dir = '/root/scripts'

logger = Logger.new("#{log_dir}/#{log}")
start_time = Time.now
logger.info('general') { "Starting #{server} backup ..." }

# backup mysql

db_type ='mysql'
db_user = ''
db_pwd = ''
db_folder = 'databases'
db_fname = "#{server}_#{db_type}_#{type}_#{date}.tar.bz"

logger.info('mysql') { "Getting list databases ..." }
dbs = `mysql --user=#{db_user} --password=#{db_pwd} -e "SHOW DATABASES;" | tr -d "| " | grep -v Database`.split("\n")
logger.info('mysql') { "Finished getting list of mysql databases." }

dbs.each do |db|
  logger.info('mysql') { "Dumping #{db} ..." }
  `mysqldump --force --opt --single-transaction --user=#{db_user} --password=#{db_pwd} --databases #{db} > #{tmp_dir}/#{db}.sql`
  logger.info('mysql') { "Finished dumping #{db}." }
end

# archive and copy to s3

logger.info('mysql') { "Tarring and zipping databases ..." }
`tar cvfj #{tmp_dir}/#{db_fname} #{tmp_dir}/*.sql`
logger.info('mysql') { "Finished tarring and zipping databases." }

logger.info('mysql') { "Backing up tarball to s3 ..." }
`s3cmd put #{tmp_dir}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
logger.info('mysql') { "Finished backing up tarball to s3." }

# clean tmp_dir

logger.info('cleanup') { "Removing files from #{tmp_dir}" }
`rm -rf #{tmp_dir}/*`
logger.info('cleanup') { "Finished removing files from #{tmp_dir}" }

# backup mongo

db_type = "mongo"
db_fname = "#{server}_#{db_type}_#{type}_#{date}.tar.bz"

logger.info('mongo') { "Dumping databases ..." }
`mongodump --out #{tmp_dir}`
logger.info('mongo') { "Finished dumping database." }

# archive and copy to s3

logger.info('mongo') { "Tarring and zipping databases ..." }
`tar cvfj #{tmp_dir}/#{db_fname} #{tmp_dir}/*`
logger.info('mongo') { "Finished tarring and zipping databases." }

logger.info('mongo') { "Backing up tarball to s3 ..." }
`s3cmd put  #{tmp_dir}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
logger.info('mongo') { "Finished backing up tarball to s3." }

# clean tmp_dir

logger.info('cleanup') { "Removing files from #{tmp_dir}" }
`rm -rf #{tmp_dir}/*`
logger.info('cleanup') { "Finished removing files from #{tmp_dir}" }

# backup all important directories

dir_folder = "directories"

# get a list of directories

dirs = []

# one-off directories

logger.info('directories') { "Getting list of one-off directories ..." }
dirs << "/etc"
dirs << "/var/www"
dirs << "/home/drupal-js-site/drupal-7.23/sites/default"
dirs << "/home/eric"
dirs << "/home/jason"
dirs << "/home/scrapers/Place-ge-Scraper/system"
dirs << "/home/scrapers/Makler.ge-Scraper/data"
logger.info('directories') { "Finished getting list of one-off directories." }

# archive and copy to s3

dirs.each do |dir|
  logger.info('directories') { "Backing up #{dir} to s3 ..." }
  `s3cmd sync --skip-existing #{dir}  s3://#{bucket}/#{dir_folder}/`
  logger.info('directories') { "Finished backing up #{dir} to s3." }
end

# rails directories

logger.info('directories') { "Getting list of rails directories ..." }
apps = []
apps << Dir.glob('/home/**/shared/system')
apps = apps.flatten
logger.info('directories') { "Finished getting list of rails directories." }

# archive and copy to s3

apps.each do |app|
  logger.info('directories') { "Backing up #{app} to s3 ..." }
  app_name = app.split('/')[2].chomp
  `s3cmd sync -r #{app}  s3://#{bucket}/#{dir_folder}/#{app_name}/`
  logger.info('directories') { "Finished backing up #{app} to s3." }
end

# calculate duration of backup

end_time = Time.now
time_min = (end_time - start_time) / 60 # minutes
time_sec = (end_time - start_time) % 60 # seconds

logger.info('general') { "Finished #{server} backup after #{time_min} MIN #{time_sec} SEC." }
