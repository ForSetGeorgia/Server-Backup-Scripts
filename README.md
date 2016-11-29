# Server-Bakcup-Scripts
Backup scripts using ruby and amazon s3 for each server

So the server backup script is not fancy, but it works. It is a Ruby script that uses Amazon's s3cmd program to sync files to our AWS S3 account daily. It is attached to this email.


# The requirements are:
* Ruby is installed under root (rbenv)
* s3cmd is installed
* the target bucket exists
* all the variables are correct in the script for the server in question
* the script is located in /root/scripts/
* /root/tmp directory exists
* the cronjob is setup correctly
Sample cronjob:
```
0 4 * * * /bin/bash -c 'export PATH="$HOME/.rbenv/bin:$PATH" ; eval "$(rbenv init -)"; ruby /root/scripts/svr_bkup.rb'
```

The comments explain the main sections:
* mysql backup
* mongo db backup (if exists)
* specific folders
* Rails' shared/system folders # this will need to be updated as your use of Rails changes
