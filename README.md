# Server-Backup-Scripts
The backup scripts are written in ruby and use Amazon s3 (s3cmd) to store the backups.

Each step of the backup script is written to a log (as defined in .env) and a summary of the backup is sent to an email address (also defined in .env). The email will also contain a list of errors if any occurred during the backup process.

# Items that can be backed up
You indicate which of these are to be backed up in the .env file.
* mysql
* postegres
* mongo db
* specific folders (/etc, /home/user/folder, etc.)
* Rails' shared/system folders


# The requirements are
* Ruby is installed under root (rbenv, at least ruby 2.3.1)
* [s3cmd is installed](http://tecadmin.net/install-s3cmd-manage-amazon-s3-buckets/) 
* the target bucket exists in Amazon S3 (this is set in the .env file)

# Setting up the backup script
* `bundle install`
* `cp .env.example .env`
* edit .env and set all of the configuration options

## Evironment
If the environment setting is not production, nothing will be pushed to Amazon. So you can set the environment to development and run the backup script to make sure everything is working. Then when you are ready you can set the enviornment to production so the data is saved to Amazon.

# Rake tasks
`Rakefile` contains the following rake tasks to run the backup and create the cron job.

## Manually run the backup script
* `bundle exec rake backup:run`

## Schedule the cron job by running the task
* `bundle exec rake backup:schedule:run_daily`

# The components
All of the ruby files can be found in the `backup_scripts` folder.

## server_backup.rb
This is the main file. You can start the script by running the rake task: `bundle exec rake backup:run`.

## environment.rb
This files loads gems and the other ruby files.

## utiltiies.rb
The file contains a list of common methods and config settings such as:
* testing if a variable key was provided
* testing if a variable value is true
* validating that the required variable keys have values
* sending the report email
* setting the default settings for email settings

## custom_logger.rb
This is a custom logger taken from our scrapers - it writes to log but also records the messages so they can be included in the email report. The logger also contains a section to record summary info for the email report.


