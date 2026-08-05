require "./interpreter"
require "./context"
module TMBSH
class Interpreter
  SHELL_COMMANDS = {
    "cd" => CD_COMMAND,
    "pwd" => PWD_COMMAND,
    "alias" => ALIAS_COMMAND,
    "export" => EXPORT_COMMAND,
    "exit"  => builtin do
      exit args[0]?.try &.to_i || 0
    end,
    "yield" => YIELD_COMMAND,
    "sleep" => SLEEP_COMMAND,
    "tmbshgc" => GC_COMMAND,
  } of ::String => ShellCommand

  private macro builtin(&body)
    ->(context : Context, input : IO?, output : IO?, error : IO?, args : ::Deque(::String)) : Result {
      {{body.body}}
    }
  end

  private macro cd(target)
    unless ::Dir.exists?({{target}})
      error.try &.puts "tmbsh: cd: #{{{target}}}: no such directory"
      return CommandFinish.new(1)
    end
    if context.original
      ::Dir.cd({{target}})
      current = Dir.current
      context.interpreter.cwd = current
      if old = ENV["PWD"]
        ENV["OLDPWD"] = old
      end
      ENV["PWD"] = current
    end
    context.cwd = current || target
  end

  CD_COMMAND = builtin do
    if args.size != 1
      error.try &.puts "tmbsh: cd: requires one argument"
      return CommandFinish.new(1)
    end
    target = args[0]
    if target == "-"
      if old = ENV["OLDPWD"]?
        cd(old)
        return CommandFinish.new(0)
      else
        error.try &.puts "tmbsh: cd: OLDPWD not set"
        return CommandFinish.new(1)
      end
    else
      cd(target)
      return CommandFinish.new(0)
    end
  end
  PWD_COMMAND = builtin do
    output.try &.puts context.cwd
    CommandFinish.new(0)
  end

  ALIAS_HELP = <<-HELP
Usage:
alias [name]
alias [name] = [command]...
HELP

  ALIAS_COMMAND = builtin do
    case args.size
    when 1
      command = context.interpreter.resolve_alias(args[0])
      if command
      output.try &.puts command.join(" ")
      CommandFinish.new(0)
      else
        output.try &.puts "tmbsh: alias: #{args[0]}: not found"
        CommandFinish.new(1)
      end
    when 3..
      name = args[0]
      command = args.to_a[2..]
      context.interpreter.add_alias(name, command)
      CommandFinish.new(0)
    else
      output.try &.puts ALIAS_HELP
      CommandFinish.new(0)
    end
  end

  EXPORT_COMMAND = builtin do
    # temporary solution
    args.each do |arg|
      context.interpreter.export_variable(arg)
    end
    CommandFinish.new(0)
  end

  YIELD_COMMAND = builtin do
    Fiber.yield
    CommandFinish.new(0)
  end

  SLEEP_USAGE = <<-HELP
Usage:
sleep [SECONDS]
HELP

  SLEEP_COMMAND = builtin do
    if args.size == 0
      output.try &.puts SLEEP_USAGE
      CommandFinish.new(0)
    else
      time = args[0].to_f64?
      if time
        sleep time.seconds
        CommandFinish.new(0)
      else
        output.try &.puts "Incorrect seconds amount: #{args[0]}"
        CommandFinish.new(1)
      end
    end
  end
GC_USAGE = <<-HELP
Usage:
tmbshgc collect|disable|enable
HELP
  GC_COMMAND = builtin do
    if args.size == 0
      output.try &.puts GC_USAGE
      CommandFinish.new(0)
    else
      case args[0]
        when "collect"
          GC.collect
          CommandFinish.new(0)
        when "disable"
          GC.disable
          CommandFinish.new(0)
        when "enable"
          GC.enable
          CommandFinish.new(0)
        else
          error.try &.puts "Unknown command: #{args[0]}"
          CommandFinish.new(1)
      end
    end
  end
end
end
