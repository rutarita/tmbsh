require "./datatypes"
require "./nodes"
require "./top_level_values"
require "./lexer/*"
require "./parser"
require "./shell_commands"
require "./variable_stack"
module TMBSH
  class Interpreter


    alias ShellCommand = Context, IO?, IO?, IO?, ::Deque(::String) -> Result
    @shell_commands : Hash(::String, ShellCommand)  = SHELL_COMMANDS
    def get_shell_command(name : ::String) : ShellCommand?
      @shell_commands[name]?
    end
    @strict : ::Bool = false

    @cwd : ::String
    property cwd
      #
      # def set_pseudoconstants_from_env
      #   ENV.each do |k, v|
      #     @variable_stack.set_constant(k, String.new(v))
      #   end
      # end

    def strict
      @strict
    end

    def strict=(val : ::Bool)
      @strict = val
      @variable_stack.strict = val
    end

    # def initialize(constants_from_env : ::Bool = true)
    #   @variable_stack = VariableStack.new
    #   @cwd = Dir.current
    #   set_pseudoconstants_from_env if constants_from_env
    # end
    def initialize
      @cwd = Dir.current
    end

    @aliases : Hash(::String, ::Array(::String)) = {} of ::String => ::Array(::String)

    def resolve_alias(command : ::String) : ::Array(::String)?
      @aliases[command]?
    end

    def add_alias(name : ::String, command : ::Array(::String))
      @aliases[name] = command
    end

    def execute_statement(statement : StatementNode) : Nil
      res = statement.execute(self)
      if res.is_a?(CommandFinish)
          set_constant("?", ExitStatus.new(res.exit_code, res.status))
      end
    end

    private def execute_parsable(parsable, context = nil)
      context = Context.new(self) unless context
      parser = Parser.new(parsable)
      until parser.token.kind.eof?
          begin
          statement = parser.parse_statement
          rescue e
            puts "tmsbh: Parsing error: #{e.to_s}"
            return
          end
          begin
            statement.execute(context)
          rescue e
            puts "tmbsh: Exception: #{e.to_s}"
          end
      end
    end

    private def execute_parsable_with_errors(parsable, context = nil)
      context = Context.new(self) unless context
      parser = Parser.new(parsable)
      until parser.token.kind.eof?
        statement = parser.parse_statement
        statement.execute(context)
      end
    end
    def execute_string(string : ::String, *, raise_on_error : ::Bool = false, context : Context? = nil)
      unless raise_on_error
          execute_parsable(string, context)
        else
          execute_parsable_with_errors(string, context)
        end
    end

    def execute_file(path : ::String | Path, *, raise_on_error : ::Bool = false, context : Context? = nil)
      # string = ::File.read(path)
      ::File.open(path) do |io|
        unless raise_on_error
          execute_parsable(io, context)
        else
          execute_parsable_with_errors(io, context)
        end
      end
      # execute_string(string)
    end
  end
end

