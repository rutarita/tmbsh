require "./interpreter"

module TMBSH
class Interpreter
  BUILTIN_COMMANDS = {
    "test" => builtin do
      if output_io
        output_io.puts "tests really loud"
      end
      NOTHING_RESULT
    end,
    "cd" => CD_COMMAND,
    "pwd" => PWD_COMMAND,
  } of ::String => BuiltinCommand

  private macro builtin(&body)
    ->(interpreter : Interpreter, input_io : IO?, output_io : IO?, error_io : IO?, args : ::Indexable(::String)) : Result {
      {{body.body}}
    }
  end

  CD_COMMAND = builtin do
    if args.size != 1
      error_io.try &.puts "cd requires one argument"
      return CommandFinish.new(1)
    end
    target = args[0]
    unless ::Dir.exists?(target)
      error_io.try &.puts "#{target}: no such directory"
      return CommandFinish.new(1)
    end
    ::Dir.cd(target)
    interpreter.cwd = Dir.current
    CommandFinish.new(0)
  end
  PWD_COMMAND = builtin do
    output_io.try &.puts interpreter.cwd
    CommandFinish.new(0)
  end
end
end
