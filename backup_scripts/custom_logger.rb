# Logs all messages to files and stores in array for later usage (i.e. by error sheet)
class CustomLogger
  def initialize(file_path)
    @logger = Logger.new("#{file_path}")

    @start = Time.now

    @info_messages = [] # format: [label, message]
    @warning_messages = [] # format: [label, message]
    @error_messages = [] # format: [label, message]
    @summary_messages = [] # format: [label, array of items, total time]
  end

  attr_reader :info_messages,
              :warning_messages,
              :error_messages, 
              :summary_messages,
              :start

  def info(label, message)
    logger.info(label) {message}
    @info_messages << [label, message]
  end

  def warn(label, message)
    logger.warn(label) {message}
    @warning_messages << [label, message]
  end

  def error(label, message)
    logger.error(label) {message}
    @error_messages << [label, message]
  end

  def summary(label, message, total_time)
    @summary_messages << [label, message, total_time]
  end

  #####################################3
  ## WRITE MESSAGES INTO NICE STRING FORMAT

  def info_to_s
    string =  "======================\n"
    string << "----- Basic Info -----\n"
    string << "======================\n"

    if info_messages.empty?
      string << "NONE\n"
    else
      string << build_messages(info_messages)
    end

    return "#{string}\n\n"
  end

  def warn_to_s
    string =  "======================\n"
    string << "-----  Warnings  -----\n"
    string << "======================\n"

    if warning_messages.empty?
      string << "NONE\n"
    else
      string << build_messages(warning_messages)
    end

    return "#{string}\n\n"
  end

  def errors_to_s
    string =  "======================\n"
    string << "-----   Errors   -----\n"
    string << "======================\n"

    if error_messages.empty?
      string << "NONE\n"
    else
      string << build_messages(error_messages)
    end

    return "#{string}\n\n"
  end


  def summary_to_s
    string =  "======================\n"
    string << "---- Summary Info ----\n"
    string << "======================\n"

    if summary_messages.empty?
      string << "NONE\n"
    else
      summary_messages.each do |msg|
        string << "#{msg[0]}: \n"
        if msg[1].class == Array && !msg[1].empty?
          msg[1].sort.each do |item|
            string << "  - #{item}\n"
          end
        end
        string << "Total Time: #{format_time(msg[2])}\n"
        string << "\n"
      end
    end

    return "#{string}\n\n"
  end



  private

  attr_reader :logger


  def build_messages(messages)
    msgs = ''
    messages.each_with_index do |msg, index|
      msgs << "#{index + 1}. #{msg[0]}: #{msg[1]}\n"
    end

    return msgs
  end
end
