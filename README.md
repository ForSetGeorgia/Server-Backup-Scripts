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

# Get the script configured
* `bundle install`
* `cp .env.example .env`
* edit .env and set all of the configuration options

## Evironment
If the environment setting is not production, nothing will be pushed to Amazon. So you can set the environment to development and run the backup script to make sure everything is working. Then when you are ready you can set the enviornment to production so the data is saved to Amazon.

# Manually run the backup script
* `bundle exec rake backup:run`

# Schedule the cron job by running the task
* `bundle exec rake backup:schedule:run_daily`

