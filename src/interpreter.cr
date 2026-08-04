require "./datatypes"
require "./nodes"
require "./top_level_values"
{% unless flag?(:old_parsing) %}
  require "./lexer/*"
  require "./parser"
{% else %}
  require "./regex_based_lexer_parser"
{% end %}
require "./shell_commands"
module TMBSH
  class Interpreter
    class VariableStack
      @vars : ::Array(::Hash(::String, Variant))
      getter vars
      @global : ::Hash(::String, Variant) = {} of ::String => Variant
      @constants : ::Hash(::String, Variant) = TOP_LEVEL_VALUES
      @strict : ::Bool = false
      property strict

      # @scope_cache : ::Hash(::String, Int32) = {} of ::String => Int32

      def initialize
        @vars = [@global]
      end

      def enter_scope : Nil
        @vars << {} of ::String => Variant
      end

      def exit_scope : Nil
        if @vars.size > 1
          @vars.pop
          # @vars.pop.each_key do |key|
          #   @scope_cache.delete(key)
          # end
        else
          raise "Cannot exit global scope"
        end
      end

      def current_scope
        @vars.size - 1
      end

      def local_scope
        @vars[-1]
      end

      def find_scope(of_var : ::String) : ::Hash(::String, Variant)?
        # if scope = @scope_cache[of_var]?
        #   return scope
        # end
        @vars.reverse_each do |scope|
          if scope[of_var]?
            # @scope_cache[of_var] = i
            return scope
          end
        end
      end

      def set_constant(name : ::String, value : Variant)
        @constants[name] = value
      end

      def shadow_variable(name : ::String, value : Variant) : Nil
        return if name == "_"
        # @scope_cache[name] = current_scope
        @vars.last[name] = value
      end

      def [](name : ::String) : Variant
        if val = @constants[name]?
          return val
        end
        if str = ENV[name]?
          return String.new(str)
        end
        if scope = find_scope(name)
          scope[name]
        else
          @strict ? raise "Variable #{name} not found" : return TMBSH::NULL
          # TMBSH::NULL
        end
      end

      private def set_env(name : ::String, value : Variant) : Nil
          # return if val.is_a?(Null)
          if value.is_a?(Array)
            ENV[name] = value.join(":")
          elsif value.is_a?(Null)
            ENV.delete(name)
          else
            ENV[name] = value.to_s
          end
      end

      def []=(name : ::String, value : Variant) : Nil
        return if name == "_"
        if ENV[name]?
          set_env(name, value)
          return
        end
        scope = find_scope(name) || @vars.last
        if !@strict && value == TMBSH::NULL
          scope.delete(name)
        else
          scope[name] = value
        end
      end

      def export(name : ::String)
        val = self[name]
        set_env(name, val)
      end

      def make_variable_global(name : ::String)
        if scope = find_scope
          if val = scope.delete(name)
            @global[name] = val
          end
        end
      end
    end

    alias ShellCommand = Context, ::Deque(::String) -> Result
    @builtins : Hash(::String, ShellCommand)  = SHELL_COMMANDS
    def get_builtin(name : ::String) : ShellCommand?
      @builtins[name]?
    end
    @variable_stack : VariableStack
    getter variable_stack
    @strict : ::Bool = false

    @cwd : ::String
    property cwd

      def enter_scope
        @variable_stack.enter_scope
      end

      def exit_scope
        @variable_stack.exit_scope
      end

      def set_variable(name : ::String, value : Variant, scope : Int32 = -1)
        @variable_stack[name] = value
      end

      delegate set_constant, to: @variable_stack

      def shadow_variable(name : ::String, value : Variant)
        @variable_stack.shadow_variable(name, value)
      end

      def get_variable(name : ::String) : Variant
        @variable_stack[name]
      end

      def export_variable(name : ::String) : Nil
        @variable_stack.export(name)
      end

      def make_variable_global(name : ::String)
        @variable_stack.make_variable_global(name : ::String)
      end
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
      @variable_stack = VariableStack.new
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

    private def execute_parsable(parsable)
      parser = Parser.new(parsable)
      until parser.token.kind.eof?
          begin
          statement = parser.parse_statement
          rescue e
            puts "tmsbh: Parsing error: #{e.to_s}"
            return
          end
          begin
            execute_statement(statement)
          rescue e
            puts "tmbsh: Exception #{e.to_s}"
          end
      end
    end

    def execute_string(string : ::String)
      execute_parsable(string)
    end

    def execute_file(path : ::String | Path)
      # string = ::File.read(path)
      ::File.open(path) do |io|
        execute_parsable(io)
      end
      # execute_string(string)
    end

    def reset
      @variable_stack = VariableStack.new
      @variable_stack.strict = @strict
    end


    @variable_stack_stack : ::Array(VariableStack) = [] of VariableStack
    def enter_variable_context
      @variable_stack_stack << @variable_stack
      @variable_stack = VariableStack.new
      @variable_stack.strict = @strict
    end

    def exit_variable_context
      @variable_stack = @variable_stack_stack.pop
      @variable_stack.strict = @strict
    end
  end
end

