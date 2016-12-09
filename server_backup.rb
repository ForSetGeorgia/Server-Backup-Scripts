#!/usr/bin/env ruby

# backup jumpstart server
# requires s3cmd & ruby

######################################
## LOAD REQUIRED GEMS
require 'dotenv'
Dotenv.load
require 'logger'
require 'mail'

######################################
## COMMON METHODS
def environment_is_production?
  return ENV['ENVIRONMENT'].downcase == 'production'
end

def variable_exists?(key)
  return !ENV[key].nil? && ENV[key].strip.length > 0
end

def variable_is_true?(key)
  variable_exists?(key) && ENV[key].downcase == 'true'
end


######################################
## CONFIG SETTINGS
if environment_is_production?
  Mail.defaults do
    delivery_method :smtp,
                    address: 'smtp.gmail.com',
                    port: '587',
                    user_name: ENV['FEEDBACK_FROM_EMAIL'],
                    password: ENV['FEEDBACK_FROM_EMAIL_PASSWORD'],
                    authentication: :plain,
                    enable_starttls_auto: true
  end
else
  Mail.defaults do
    delivery_method :smtp,
                    address: 'localhost',
                    port: 1025
  end
end

######################################
## VALIDATION
# make sure the required keys have values
required_keys = %w(BACKUP_TYPE SERVER_NAME S3_BUCKET_PREFIX TMP_DIR LOG_DIR WHEN_BACKUP_SERVER)
required_keys_prod = %w(FEEDBACK_FROM_EMAIL FEEDBACK_FROM_EMAIL_PASSWORD FEEDBACK_TO_EMAIL)
mysql_keys = %w(MYSQL_USER MYSQL_PASSWORD)
missing_keys = []
keys = required_keys
if environment_is_production?
  keys << required_keys_prod
end
if variable_is_true?('HAS_MYSQL')
  keys << mysql_keys
end
keys.flatten!
keys.each do |key|
  if !variable_exists? key
    missing_keys << key
  end
end

if missing_keys.length > 0
  puts "ERROR: the following keys are missing values: #{missing_keys.join(', ')}"
  return
end


# make sure the required directories exist
if !File.exists? ENV['TMP_DIR']
  puts "ERROR: the tmp directory '#{ENV['TMP_DIR']}' does not exist and must be created before running this script"
  return
end
if !File.exists? ENV['LOG_DIR']
  puts "ERROR: the log directory '#{ENV['LOG_DIR']}' does not exist and must be created before running this script"
  return
end

######################################
## THE BACKUP SCRIPT

# main variables

bucket = "#{ENV['S3_BUCKET_PREFIX']}-#{ENV['SERVER_NAME']}" # old s3 names could have underscore, new names should have dash
date = Time.now.strftime('%y-%m-%d')
log = "#{ENV['SERVER_NAME']}_#{ENV['BACKUP_TYPE']}_backup.log"
logger = Logger.new("#{ENV['LOG_DIR']}/#{log}")
start_time = Time.now

logger.info('general') { "Starting #{ENV['SERVER_NAME']} backup ..." }

# backup mysql
if variable_is_true?('HAS_MYSQL')
  logger.info('mysql') { "Backing up MYSQL databases ..." }

  db_type ='mysql'
  db_folder = 'databases'
  db_fname = "#{ENV['SERVER_NAME']}_#{db_type}_#{ENV['BACKUP_TYPE']}_#{date}.tar.bz"

  logger.info('mysql') { "Getting list databases ..." }
  dbs = `mysql --user=#{ENV['MYSQL_USER']} --password=#{ENV['MYSQL_PASSWORD']} -e "SHOW DATABASES;" | tr -d "| " | grep -v Database`.split("\n")
  logger.info('mysql') { "Finished getting list of mysql databases." }

  dbs.each do |db|
    logger.info('mysql') { "Dumping #{db} ..." }
    `mysqldump --force --opt --single-transaction --user=#{ENV['MYSQL_USER']} --password=#{ENV['MYSQL_PASSWORD']} --databases #{db} > #{ENV['TMP_DIR']}/#{db}.sql`
    logger.info('mysql') { "Finished dumping #{db}." }
  end

  # archive and copy to s3

  logger.info('mysql') { "Tarring and zipping databases ..." }
  `tar cvfj #{ENV['TMP_DIR']}/#{db_fname} #{ENV['TMP_DIR']}/*.sql`
  logger.info('mysql') { "Finished tarring and zipping databases." }

  logger.info('mysql') { "Backing up tarball to s3 ..." }
  if environment_is_production?
    `s3cmd put #{ENV['TMP_DIR']}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
  else
    logger.info('mysql') { ">>> this is not production so not saving to s3" }
  end
  logger.info('mysql') { "Finished backing up tarball to s3." }

  # clean tmp_dir

  logger.info('cleanup') { "Removing files from #{ENV['TMP_DIR']}" }
  `rm -rf #{ENV['TMP_DIR']}/*`
  logger.info('cleanup') { "Finished removing files from #{ENV['TMP_DIR']}" }
end

# backup mongo
if variable_is_true?('HAS_MONGO')
  logger.info('mongo') { "Backing up MONGO databases ..." }
  db_type = "mongo"
  db_fname = "#{ENV['SERVER_NAME']}_#{db_type}_#{ENV['BACKUP_TYPE']}_#{date}.tar.bz"

  logger.info('mongo') { "Dumping databases ..." }
  `mongodump --out #{ENV['TMP_DIR']}`
  logger.info('mongo') { "Finished dumping database." }

  # archive and copy to s3

  logger.info('mongo') { "Tarring and zipping databases ..." }
  `tar cvfj #{ENV['TMP_DIR']}/#{db_fname} #{ENV['TMP_DIR']}/*`
  logger.info('mongo') { "Finished tarring and zipping databases." }

  logger.info('mongo') { "Backing up tarball to s3 ..." }
  if environment_is_production?
    `s3cmd put  #{ENV['TMP_DIR']}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
  else
    logger.info('mongo') { ">>> this is not production so not saving to s3" }
  end
  logger.info('mongo') { "Finished backing up tarball to s3." }

  # clean tmp_dir

  logger.info('cleanup') { "Removing files from #{ENV['TMP_DIR']}" }
  `rm -rf #{ENV['TMP_DIR']}/*`
  logger.info('cleanup') { "Finished removing files from #{ENV['TMP_DIR']}" }
end

# backup all important directories

dir_folder = "directories"

# get a list of directories

dirs = []

# other directories

logger.info('directories') { "Getting list of other directories ..." }

dirs << "/etc"

if variable_is_true?('HAS_VAR_WWW')
  dirs << "/var/www"
end
if variable_is_true?('HAS_NGINX_HTML')
  dirs << "/usr/share/nginx/html"
end
if !ENV['OTHER_DIRECTORES'].nil?
  others = ENV['OTHER_DIRECTORES'].split(',').map{|x| x.strip}
  if others.length > 0
    dirs << others
    dirs.flatten!
  end
end

logger.info('directories') { "Finished getting list of other directories." }
# logger.info('directories') { "- other directores: #{dirs.join('; ')}" }

# archive and copy to s3

dirs.each do |dir|
  logger.info('directories') { "Backing up #{dir} to s3 ..." }
  if environment_is_production?
    `s3cmd sync --skip-existing #{dir}  s3://#{bucket}/#{dir_folder}/`
  else
    logger.info('directories') { ">>> this is not production so not saving to s3" }
  end
  logger.info('directories') { "Finished backing up #{dir} to s3." }
end

# rails directories
if variable_is_true?('HAS_RAILS')

  logger.info('directories') { "Getting list of rails directories ..." }
  apps = []
  if environment_is_production?
    apps << Dir.glob('/home/**/shared/system') # capistrano v2 folder structure
    apps << Dir.glob('/home/**/shared/public') # mina folder structure
  else
    apps << Dir.glob('/home/**/public/system') # normal rails sturcture on dev machine
  end
  apps.flatten!
  logger.info('directories') { "Finished getting list of rails directories." }

  # get app names
  app_names = []
  apps.each do |app|
    folders = app.split('/')
    if folders.length > 3
      app_names << folders[-3]
    end
  end
  logger.info('directories') { "Rails Apps being backed up: #{app_names.join('; ')}" } if app_names.length > 0

  # archive and copy to s3

  apps.each do |app|
    logger.info('directories') { "Backing up #{app} to s3 ..." }
    app_name = app.split('/')[2].chomp
    if environment_is_production?
      `s3cmd sync -r #{app}  s3://#{bucket}/#{dir_folder}/#{app_name}/`
    else
      logger.info('directories') { ">>> this is not production so not saving to s3" }
    end
    logger.info('directories') { "Finished backing up #{app} to s3." }
  end
end

# calculate duration of backup

end_time = Time.now
time_min = ((end_time - start_time) / 60).round(2) # minutes
time_sec = ((end_time - start_time) % 60).round(2) # seconds

logger.info('general') { "Finished #{ENV['SERVER_NAME']} backup after #{time_min} MIN #{time_sec} SEC." }
logger.info('general') { "============================================================================" }

