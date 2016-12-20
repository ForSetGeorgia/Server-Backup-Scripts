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
    string << "---- Errors ----\n"
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
      convert = { 'k' => 1, 'm' => 1024, 'g' => 1024*1024, 't' => 1024*1024*1024}
      all_file_sizes = []

      summary_messages.each do |msg|
        file_sizes = []
        total = 0

        string << "#{msg[0]}: \n"
        if msg[1].class == Array && !msg[1].empty?
          msg[1].sort.each do |item|
            if item.class == Array && !item.empty?
              string << "  - #{item[0]} (#{item[1]})\n"
              file_sizes << item[1]
            else
              string << "  - #{item}\n"
            end
          end
        end
        string << "Total Time: #{format_time(msg[2])}\n"
        if !file_sizes.empty?
          # compute the total size for this summary item
          file_sizes.each do |size|
            total += size.to_f*convert[size[-1].downcase]
          end
          if total > 0
            all_file_sizes << total
            string << "Total Size: #{human_readable_file_size(total)} **\n"
          end
        end
        string << "\n"
      end

      if !all_file_sizes.empty?
        string << "\n"
        string << "======================\n"
        string << "---- Combined Total Size ----\n"
        string << "======================\n"
        string << "Combined Total Size: #{human_readable_file_size(all_file_sizes.inject(:+))} **\n"
        string << "\n"
        string << "** - database file sizes are the size of the raw dump files; database files are compressed before sending to S3\n"
      end
    end

    return "#{string}"
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
