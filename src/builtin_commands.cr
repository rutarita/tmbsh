require "./interpreter"

module TMBSH
class Interpreter
  BUILTIN_COMMANDS = {
    "test" => builtin do
      if output_io
        output_io.puts "tests really loud"
      end
      NOTHING_RESULT
    end
  } of ::String => BuiltinCommand

  private macro builtin(&body)
    ->(interpreter : Interpreter, input_io : IO?, output_io : IO?, error_io : IO?, args : ::Indexable(::String)) : Result {
      {{body.body}}
    }
  end

  CD_COMMAND = builtin do

  end
end
end
