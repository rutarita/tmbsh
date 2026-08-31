require "./readline.cr"
require "./interpreter.cr"

module TMBSH
  class Shell
    HISTORY_FILE_NAME = ".tmbsh_history"

    @interpreter : Interpreter

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
      @interpreter = Interpreter.new
    end

    def mainloop
      context = Interpreter::Context.new(@interpreter)
      loop do
        input = ReadLine.readline("$ ")
        if input
          if !input.empty?
            ReadLine.add_history(input)
            @interpreter.execute_string(input, context: context)
          end
        else
          break
        end
      end
    end
  end
end
