require "./readline.cr"
module TMBSH
class Shell

  HISTORY_FILE_NAME = ".tmbsh_history"

  def initialize
    begin
      ::File.open(Path.home / HISTORY_FILE_NAME) do |fd|
        loop do
          if line = fd.gets
            ReadLine.add_history(line)
          else
            break
          end
        end
      end
    rescue
    end
  end

  def mainloop

  end
end
end
