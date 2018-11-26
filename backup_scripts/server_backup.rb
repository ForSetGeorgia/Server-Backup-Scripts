#!/usr/bin/env ruby

######################################
## LOAD REQUIRED GEMS AND LOCAL RUBY FILES
require_relative 'environment'

# backup server - this is called from the rake task: backup:run
def run_server_backup

  start_time = Time.now


  ## create basic logger in case the variables are not set properly
  ## - if variables are set, this logger will be re-created properly below
  logger = CustomLogger.new("#{ENV['ROOT_DIR']}/error_log.log")


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

    bucket = "#{ENV['S3_BUCKET_PREFIX']}#{ENV['S3_BUCKET_SEPARATOR']}#{ENV['SERVER_NAME']}"
    date = Time.now.strftime('%y-%m-%d')
    log = "#{ENV['SERVER_NAME']}_#{ENV['BACKUP_TYPE']}_backup.log"
    logger = CustomLogger.new("#{ENV['LOG_DIR']}/#{log}")

    logger.info("general", "============================================================================")
    logger.info("general", "Starting #{ENV['SERVER_NAME']} backup ...")


    # clean tmp_dir
    logger.info("cleanup", "Removing files from #{ENV['TMP_DIR']}")
    `rm -rf #{ENV['TMP_DIR']}/*`
    logger.info("cleanup", "Finished removing files from #{ENV['TMP_DIR']}")

    # backup mysql
    if variable_is_true?('HAS_MYSQL')
      start_local = Time.now
      summary_info = []

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

        dh_output = `du -hs #{ENV['TMP_DIR']}/#{db}.sql`
        summary_info << [db, dh_output.split(' ').first.chomp.strip]
        logger.info("mysql", "Finished dumping #{db}.")
      end

      # archive and copy to s3

      logger.info("mysql", "Tarring and zipping databases ...")
      `tar cvfj #{ENV['TMP_DIR']}/#{db_fname} #{ENV['TMP_DIR']}/*.sql`
      logger.info("mysql", "Finished tarring and zipping databases.")

      logger.info("mysql", "Backing up tarball to s3 at s3://#{bucket}/#{db_folder}/#{db_fname}...")
      if environment_is_production?
        `#{ENV['S3CMD_PATH']} put #{ENV['TMP_DIR']}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
      else
        logger.info("mysql", ">>> this is not production so not saving to s3")
      end
      logger.info("mysql", "Finished backing up tarball to s3.")

      # clean tmp_dir

      logger.info("cleanup", "Removing files from #{ENV['TMP_DIR']}")
      `rm -rf #{ENV['TMP_DIR']}/*`
      logger.info("cleanup", "Finished removing files from #{ENV['TMP_DIR']}")

      logger.summary("MySQL Databases", summary_info, Time.now-start_local) if !summary_info.empty?
    end

    # backup mongo
    if variable_is_true?('HAS_MONGO')
      start_local = Time.now
      summary_info = []

      logger.info("mongo", "Backing up MONGO databases ...")
      db_type = "mongo"
      db_fname = "#{ENV['SERVER_NAME']}_#{db_type}_#{ENV['BACKUP_TYPE']}_#{date}.tar.bz"

      logger.info("mongo", "Dumping databases ...")
      `mongodump --out #{ENV['TMP_DIR']}`
      logger.info("mongo", "Finished dumping database.")

      # get list of dbs that were dumped
      dbs = Dir.glob("#{ENV['TMP_DIR']}/*").select {|f| File.directory? f}

      # create summary info
      dbs.each do |db|
        dh_output = `du -hs #{db}`
        summary_info << [db.split('/').last, dh_output.split(' ').first.chomp.strip]
      end

      # archive and copy to s3

      logger.info("mongo", "Tarring and zipping databases ...")
      `tar cvfj #{ENV['TMP_DIR']}/#{db_fname} #{ENV['TMP_DIR']}/*`
      logger.info("mongo", "Finished tarring and zipping databases.")

      logger.info("mongo", "Backing up tarball to s3 at s3://#{bucket}/#{db_folder}/#{db_fname} ...")
      if environment_is_production?
        `#{ENV['S3CMD_PATH']} put  #{ENV['TMP_DIR']}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
      else
        logger.info("mongo", ">>> this is not production so not saving to s3")
      end
      logger.info("mongo", "Finished backing up tarball to s3.")

      # clean tmp_dir

      logger.info("cleanup", "Removing files from #{ENV['TMP_DIR']}")
      `rm -rf #{ENV['TMP_DIR']}/*`
      logger.info("cleanup", "Finished removing files from #{ENV['TMP_DIR']}")

      logger.summary("Mongo Databases", summary_info, Time.now-start_local) if !summary_info.empty?
    end

    # backup postgres
    if variable_is_true?('HAS_POSTGRES')
      start_local = Time.now
      summary_info = []

      db_type ='postgres'
      db_folder = 'databases'
      db_fname = "#{ENV['SERVER_NAME']}_#{db_type}_#{ENV['BACKUP_TYPE']}_#{date}.tar.bz"

      if !ENV['POSTGRES_DOCKER_CONTAINERS'].nil? && !ENV['POSTGRES_DOCKER_CONTAINERS'].index(':').nil?
        # backing up postgres dbs in docker containers

        logger.info("postgres", "Dumping docker databases ...")

        containers = ENV['POSTGRES_DOCKER_CONTAINERS'].split(',')
        containers.each do |container|
          container_name, path = container.split(':')
          if container_name && path
            # test to make sure container is running
            output = `cd #{path} && docker exec -t #{container_name} echo 'running!'`
            if output.chomp.strip == 'running!'
              `cd #{path} && docker exec -t #{container_name} pg_dumpall -c -U #{ENV['POSTGRES_USER']} | gzip > #{ENV['TMP_DIR']}/#{container_name}.sql.gz`
            else
              logger.error("postgres", "The postgres docker container '#{container_name}' is not running and so cannot be backed up")
            end
          else
            logger.error("postgres", "The POSTGRES_DOCKER_CONTAINERS enviornmental variable was not properly setup")
          end

        end

      else
        # backing up postgres dbs on server
        logger.info("postgres", "Dumping databases ...")
        `sh ./postgres_db_dump.sh '#{ENV['POSTGRES_USER']}' '#{ENV['POSTGRES_PASSWORD']}' '#{ENV['TMP_DIR']}'`
      end

      # get list of dbs that were dumped
      dbs = Dir.glob("#{ENV['TMP_DIR']}/*")

      # create summary info
      dbs.each do |db|
        dh_output = `du -hs #{db}`
        summary_info << [db.split('/').last.gsub(/\.sql.*/, ''), dh_output.split(' ').first.chomp.strip]
      end

      # archive and copy to s3
      logger.info("postgres", "Tarring and zipping databases ...")
      `tar cvfj #{ENV['TMP_DIR']}/#{db_fname} #{ENV['TMP_DIR']}/*.sql*`
      logger.info("postgres", "Finished tarring and zipping databases.")

      logger.info("postgres", "Backing up tarball to s3 at s3://#{bucket}/#{db_folder}/#{db_fname}...")
      if environment_is_production?
        `#{ENV['S3CMD_PATH']} put #{ENV['TMP_DIR']}/#{db_fname} s3://#{bucket}/#{db_folder}/#{db_fname}`
      else
        logger.info("postgres", ">>> this is not production so not saving to s3")
      end
      logger.info("postgres", "Finished backing up tarball to s3.")

      # clean tmp_dir
      logger.info("cleanup", "Removing files from #{ENV['TMP_DIR']}")
      `rm -rf #{ENV['TMP_DIR']}/*`
      logger.info("cleanup", "Finished removing files from #{ENV['TMP_DIR']}")

      logger.summary("Postgres Databases", summary_info, Time.now-start_local) if !summary_info.empty?
    end

    # backup all important directories

    dir_folder = "directories"

    # get a list of directories

    dirs = []

    # specific directories
    start_local = Time.now
    summary_info  = []

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
      logger.info("directories", "Backing up #{dir} to s3 to s3://#{bucket}/#{dir_folder}/...")

      # get the folder size
      dh_output = `du -hs #{dir}`
      summary_info << [dir, dh_output.split(' ').first.chomp.strip]

      if environment_is_production?
        `#{ENV['S3CMD_PATH']} sync --skip-existing #{dir}  s3://#{bucket}/#{dir_folder}/`
      else
        logger.info("directories", ">>> this is not production so not saving to s3")
      end
      logger.info("directories", "Finished backing up #{dir} to s3.")
    end
    logger.summary("Specific Directories", summary_info, Time.now-start_local) if !summary_info.empty?


    # rails directories
    if variable_is_true?('HAS_RAILS')
      start_local = Time.now
      summary_info  = []
      apps_to_ignore = []
      if variable_exists?('RAILS_APPS_TO_IGNORE')
        apps_to_ignore = ENV['RAILS_APPS_TO_IGNORE'].split(',').map{|x| x.strip.downcase}
      end

      logger.info("rails", "Getting list of rails directories ...")
      apps = []
      if variable_is_true?('IS_SERVER')
        apps << Dir.glob('/home/**/shared/system') # capistrano v2 folder structure
        apps << Dir.glob('/home/**/shared/public') # mina folder structure
      else
        apps << Dir.glob('/home/**/public/system') # normal rails sturcture on dev machine
      end
      apps.flatten!
      logger.info("rails", "Finished getting list of rails directories.")

      # get app names
      # - use the folder name that is 2 before the system folder
      # app_names = []
      # apps.each do |app|
      #   folders = app.split('/')
      #   if folders.length > 3
      #     app_names << folders[-3]
      #   end
      # end

      # archive and copy to s3
      apps.each do |app|
        # get the app name
        app_name = app.split('/')[-3].chomp

        # check if in list of apps to ignore
        if !apps_to_ignore.empty? && apps_to_ignore.include?(app_name.downcase)
          logger.info("rails", "Ignoring Rails app: #{app_name}")
          summary_info << [app_name, 'IGNORED']
        else
          # get the folder size
          dh_output = `du -hs #{app}`
          summary_info << [app_name, dh_output.split(' ').first.chomp.strip]
          logger.info("rails", "Backing up #{app} to s3 to s3://#{bucket}/#{dir_folder}/#{app_name}/...")

          if environment_is_production?
            `#{ENV['S3CMD_PATH']} sync --skip-existing #{app}  s3://#{bucket}/#{dir_folder}/#{app_name}/`
          else
            logger.info("rails", ">>> this is not production so not saving to s3")
          end
          logger.info("rails", "Finished backing up #{app} to s3.")
        end
      end

      logger.summary("Rails Apps with System Folders", summary_info, Time.now-start_local) if !summary_info.empty?
    end


    # backup mail-in-a-box
    if variable_is_true?('HAS_MAIL_IN_A_BOX') && variable_exists?('MAIL_IN_A_BOX_BACKUP_DIRECTORY')
      # assume the backup directory exists (it is checked for in keys_valid?)

      start_local = Time.now
      summary_info  = []

      logger.info("mail-in-a-box", "Checking for encrypted folder and secret_key file")

      encrypted_folder = "encrypted"
      encrypted_folder_path = "#{ENV['MAIL_IN_A_BOX_BACKUP_DIRECTORY']}/#{encrypted_folder}"
      secret_key = "#{ENV['MAIL_IN_A_BOX_BACKUP_DIRECTORY']}/secret_key.txt"
      encrypted_s3_folder = 'encrypted'

      if File.exists?(encrypted_folder_path) && File.exists?(secret_key)
        logger.info("mail-in-a-box", "Found files, backing up to s3 to s3://#{bucket}/#{ENV['MAIL_IN_A_BOX_S3_DIRECTORY']}/...")

        # secrety key
        # get the file size
        dh_output = `du -hs #{secret_key}`
        summary_info << [secret_key, dh_output.split(' ').first.chomp.strip]
        if environment_is_production?
        `#{ENV['S3CMD_PATH']} put #{secret_key} s3://#{bucket}/#{ENV['MAIL_IN_A_BOX_S3_DIRECTORY']}/#{secret_key}`
        else
          logger.info("mail-in-a-box", ">>> this is not production so not saving to s3")
        end


        # copy the encrypted folder to tmp so can compress and send to s3
        dh_output = `du -hs #{encrypted_folder_path}`
        summary_info << [encrypted_folder_path, dh_output.split(' ').first.chomp.strip]
        folder_fname = "encrypted_folder_#{date}.tar.bz"

        logger.info("mail-in-a-box", "Tarring and zipping encrypted folder ...")
        `cp -r #{encrypted_folder_path} #{ENV['TMP_DIR']}/#{encrypted_folder}`
        `tar cvfj #{ENV['TMP_DIR']}/#{folder_fname} #{ENV['TMP_DIR']}/#{encrypted_folder}`
        logger.info("mail-in-a-box", "Finished tarring and zipping encrypted folder.")

        logger.info("mail-in-a-box", "Backing up tarball to s3 at s3://#{bucket}/#{ENV['MAIL_IN_A_BOX_S3_DIRECTORY']}/#{encrypted_s3_folder}/#{folder_fname}...")
        if environment_is_production?
          `#{ENV['S3CMD_PATH']} put #{ENV['TMP_DIR']}/#{folder_fname} s3://#{bucket}/#{ENV['MAIL_IN_A_BOX_S3_DIRECTORY']}/#{encrypted_s3_folder}/#{folder_fname}`
        else
          logger.info("mail-in-a-box", ">>> this is not production so not saving to s3")
        end
        logger.info("mail-in-a-box", "Finished backing up tarball to s3.")

      else
        logger.error("mail-in-a-box", "At least one of the following paths could not be found: #{encrypted_folder_path} OR #{secret_key}")
      end

      # clean tmp_dir
      logger.info("cleanup", "Removing files from #{ENV['TMP_DIR']}")
      `rm -rf #{ENV['TMP_DIR']}/*`
      logger.info("cleanup", "Finished removing files from #{ENV['TMP_DIR']}")

      logger.summary("Mail-In-A-Box", summary_info, Time.now-start_local) if !summary_info.empty?
    end



  rescue => e
    logger.error(e.class.to_s, "#{e.message}\n--BACKTRACE--\n - #{e.backtrace.join("\n - ")}")
  end

  # calculate duration of backup
  total_time = Time.now - start_time

  # send the email report
  logger.info("email", "Sending the email ...")
  send_email(logger, total_time) if is_valid
  logger.info("email", "Email sent.")

  logger.info("general", "Finished #{ENV['SERVER_NAME']} backup after #{format_time(total_time)}.")
  logger.info("general", "============================================================================")

end
