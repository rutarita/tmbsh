require "./readline.cr"

class TMBSH

  HISTORY_FILE_NAME = ".tmbsh_history"

  def initialize
    (Path.home / HISTORY_FILE_NAME).open do |fd|
      line = fd.gets
      ReadLine.add_history(line)
    end
  end

  def mainloop

  end
end
