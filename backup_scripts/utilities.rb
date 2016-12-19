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

def format_time(time)
  time_min = (time / 60).floor # minutes without decimal since decimal is seconds
  time_sec = (time % 60).round(2) # seconds
  return "#{time_min} MIN #{time_sec} SEC"
end

def send_email(logger, total_time)
  mail = Mail.new do
    from    ENV['FEEDBACK_FROM_EMAIL']
    to      ENV['FEEDBACK_TO_EMAIL']
    subject "#{ENV['SERVER_NAME']} Server Backup Report (#{Time.now.strftime('%F')})"
  end

  mail[:body] = build_email_body(logger, total_time)

  mail.deliver!
end


# make sure the required keys have values
def keys_valid?
  valid = true
  msg = []
  required_keys = %w(BACKUP_TYPE SERVER_NAME S3_BUCKET_PREFIX TMP_DIR LOG_DIR BACKUP_SERVER_TIME FEEDBACK_FROM_EMAIL FEEDBACK_FROM_EMAIL_PASSWORD FEEDBACK_TO_EMAIL)
  mysql_keys = %w(MYSQL_USER MYSQL_PASSWORD)
  missing_keys = []
  keys = required_keys
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
    msg << "ERROR: the following keys are missing values: #{missing_keys.join(', ')}"
    valid = false
  end


  # make sure the required directories exist
  if !File.exists? ENV['TMP_DIR']
    msg << "ERROR: the tmp directory '#{ENV['TMP_DIR']}' does not exist and must be created before running this script"
    valid = false
  end
  if !File.exists? ENV['LOG_DIR']
    msg << "ERROR: the log directory '#{ENV['LOG_DIR']}' does not exist and must be created before running this script"
    valid = false
  end

  return valid, msg
end


######################################
## CONFIG SETTINGS
if environment_is_production? || variable_is_true?('IS_SERVER')
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
######################################

private

  def build_email_body(logger, total_time)
    body = ''

    # add time to finish backup
    body << "======================\n"
    body << "---- Running Time ----\n"
    body << "======================\n"
    body << "Start Time: #{logger.start}\n"
    body << "Total Time: #{format_time(total_time)}"

    body << "\n\n"

    # add summary section
    body << logger.summary_to_s

    # add errors
    body << logger.errors_to_s

    return body

  end