#!/usr/bin/env ruby

######################################
## LOAD REQUIRED GEMS AND LOCAL RUBY FILES
require_relative 'environment'

# backup server - this is called from the rake task: backup:run
def run_server_backup

  start_time = Time.now


  ## create basic logger in case the variables are not set properly
  ## - if variables are set, this logger will be re-created properly below
  logger = CustomLogger.new("./error_log.log")


  ######################################
  ## VALIDATION
  # make sure the required keys have values
  is_valid, error_messages = keys_valid?
  if !is_valid
    error_messages.each do |msg|
      logger.error('Validation Error', msg)
    end

    return
  end

  ######################################
  ## THE BACKUP SCRIPT
  begin
    # main variables

    bucket = "#{ENV['S3_BUCKET_PREFIX']}-#{ENV['SERVER_NAME']}" # old s3 names could have underscore, new names should have dash
    date = Time.now.strftime('%y-%m-%d')
    log = "#{ENV['SERVER_NAME']}_#{ENV['BACKUP_TYPE']}_backup.log"
    logger = CustomLogger.new("#{ENV['LOG_DIR']}/#{log}")

    logger.info("general", "Starting #{ENV['SERVER_NAME']} backup ...")


    # clean tmp_dir
    logger.info("cleanup", "Removing files from #{ENV['TMP_DIR']}")
    `rm -rf #{ENV['TMP_DIR']}/*`
    logger.info("cleanup", "Finished removing files from #{ENV['TMP_DIR']}")

    # backup mysql
    if variable_is_true?('HAS_MYSQL')
      start_local = Time.now

      logger.info("mysql", "Backing up MYSQL databases ...")

      db_type ='mysql'
      db_folder = 'databases'
      db_fname = "#{ENV['SERVER_NAME']}_#{db_type}_#{ENV['BACKUP_TYPE']}_#{date}.tar.bz"

      logger.info("mysql", "Getting list databases ...")
      dbs = `mysql --user=#{ENV['MYSQL_USER']} --password='#{ENV['MYSQL_PASSWORD']}' -e "SHOW DATABASES;" | tr -d "| " | grep -v Database`.split("\n")
      logger.info("mysql", "Finished getting list of mysql databases.")

      dbs.each do |db|
        logger.info("mysql", "Dumping #{db} ...")
        `mysqldump --force --opt --single-transaction --user=#{ENV['MYSQL_USER']} --password='#{ENV['MYSQL_PASSWORD']}' --databases #{db} > #{ENV['TMP_DIR']}/#{db}.sql`
        logger.info("mysql", "Finished dumping #{db}.")
      end

      # archive and copy to s3

      logger.info("mysql", "Tarring and zipping databases ...")
      `tar cvfj #{ENV['TMP_DIR']}/#{db_fname} #{ENV['TMP_DIR']}/*.sql`
      logger.info("mysql", "Finished tarring and zipping databases.")

      logger.info("mysql", "Backing up tarball to s3 ...")
      if environment_is_production?
        `s3cmd put #{ENV['TMP_DIR']}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
      else
        logger.info("mysql", ">>> this is not production so not saving to s3")
      end
      logger.info("mysql", "Finished backing up tarball to s3.")

      # clean tmp_dir

      logger.info("cleanup", "Removing files from #{ENV['TMP_DIR']}")
      `rm -rf #{ENV['TMP_DIR']}/*`
      logger.info("cleanup", "Finished removing files from #{ENV['TMP_DIR']}")

      logger.summary("MySQL Databases", dbs, Time.now-start_local)
    end

    # backup mongo
    if variable_is_true?('HAS_MONGO')
      start_local = Time.now
      logger.info("mongo", "Backing up MONGO databases ...")
      db_type = "mongo"
      db_fname = "#{ENV['SERVER_NAME']}_#{db_type}_#{ENV['BACKUP_TYPE']}_#{date}.tar.bz"

      logger.info("mongo", "Dumping databases ...")
      `mongodump --out #{ENV['TMP_DIR']}`
      logger.info("mongo", "Finished dumping database.")

      # get list of dbs that were dumped
      dbs = Dir.glob('./tmp/*').select {|f| File.directory? f}

      # archive and copy to s3

      logger.info("mongo", "Tarring and zipping databases ...")
      `tar cvfj #{ENV['TMP_DIR']}/#{db_fname} #{ENV['TMP_DIR']}/*`
      logger.info("mongo", "Finished tarring and zipping databases.")

      logger.info("mongo", "Backing up tarball to s3 ...")
      if environment_is_production?
        `s3cmd put  #{ENV['TMP_DIR']}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
      else
        logger.info("mongo", ">>> this is not production so not saving to s3")
      end
      logger.info("mongo", "Finished backing up tarball to s3.")

      # clean tmp_dir

      logger.info("cleanup", "Removing files from #{ENV['TMP_DIR']}")
      `rm -rf #{ENV['TMP_DIR']}/*`
      logger.info("cleanup", "Finished removing files from #{ENV['TMP_DIR']}")

      logger.summary("Mongo Databases", dbs.map{|db| db.split('/').last}, Time.now-start_local)
    end

    # backup all important directories

    dir_folder = "directories"

    # get a list of directories

    dirs = []

    # specific directories
    start_local = Time.now
    logger.info("directories", "Getting list of specific directories ...")

    dirs << "/etc"

    if variable_is_true?('HAS_VAR_WWW')
      dirs << "/var/www"
    end
    if variable_is_true?('HAS_NGINX_HTML')
      dirs << "/usr/share/nginx/html"
    end
    if !ENV['SPECIFIC_DIRECTORES'].nil?
      others = ENV['SPECIFIC_DIRECTORES'].split(',').map{|x| x.strip}
      if !others.empty?
        dirs << others
        dirs.flatten!
      end
    end

    logger.info("directories", "Finished getting list of specific directories.")

    # archive and copy to s3

    dirs.each do |dir|
      logger.info("directories", "Backing up #{dir} to s3 ...")
      if environment_is_production?
        `s3cmd sync --skip-existing #{dir}  s3://#{bucket}/#{dir_folder}/`
      else
        logger.info("directories", ">>> this is not production so not saving to s3")
      end
      logger.info("directories", "Finished backing up #{dir} to s3.")
    end
    logger.summary("Specific Directories", dirs, Time.now-start_local)
    

    # rails directories
    if variable_is_true?('HAS_RAILS')
      start_local = Time.now
      logger.info("directories", "Getting list of rails directories ...")
      apps = []
      if environment_is_production?
        apps << Dir.glob('/home/**/shared/system') # capistrano v2 folder structure
        apps << Dir.glob('/home/**/shared/public') # mina folder structure
      else
        apps << Dir.glob('/home/**/public/system') # normal rails sturcture on dev machine
      end
      apps.flatten!
      logger.info("directories", "Finished getting list of rails directories.")

      # get app names
      # - use the folder name that is 2 before the system folder
      app_names = []
      apps.each do |app|
        folders = app.split('/')
        if folders.length > 3
          app_names << folders[-3]
        end
      end

      # archive and copy to s3

      apps.each do |app|
        logger.info("directories", "Backing up #{app} to s3 ...")
        app_name = app.split('/')[2].chomp
        if environment_is_production?
          `s3cmd sync -r #{app}  s3://#{bucket}/#{dir_folder}/#{app_name}/`
        else
          logger.info("directories", ">>> this is not production so not saving to s3")
        end
        logger.info("directories", "Finished backing up #{app} to s3.")
      end

      logger.summary("Rails Apps with System Folders", app_names, Time.now-start_local) if !app_names.empty?
    end

  rescue => e
    logger.error(e.class.to_s, "#{e.message}\n--BACKTRACE--\n - #{e.backtrace.join("\n - ")}")
  end

  # calculate duration of backup
  total_time = Time.now - start_time

  # send the email report
  send_email(logger, total_time) if is_valid

  logger.info("general", "Finished #{ENV['SERVER_NAME']} backup after #{format_time(total_time)}.")
  logger.info("general", "============================================================================")

end
