require "./interpreter"

module TMBSH
  class Interpreter
    class Context
      property output : IO?
      property input : IO?
      property error : IO?
      property interpreter : Interpreter
      property variable_stacks : ::Array(VariableStack)
      property cwd : ::String
      property original : ::Bool

      def initialize(interpreter : Interpreter)
        @interpreter = interpreter
        @variable_stacks = [interpreter.variable_stack]
        @cwd = interpreter.cwd
        @output = STDOUT
        @input = STDIN
        @error = STDERR
        @original = true
      end

      def dup
        ctx = self.class.allocate
        ctx.output = @output
        ctx.input = @input
        ctx.error = @error
        ctx.interpreter = interpreter
        ctx.variable_stacks = @variable_stacks.dup
        ctx.cwd = cwd
        ctx.original = false
        ctx
      end

      def current_variable_stack
        # @variable_stack || @interpreter.variable_stack
        @variable_stacks.last
      end

      def enter_scope
        current_variable_stack.enter_scope
      end

      def exit_scope
        current_variable_stack.exit_scope
      end

      def shadow_variable(name : ::String, value : Variant)
        current_variable_stack.shadow_variable(name, value)
      end

      def set_variable(name : ::String, value : Variant)
        current_variable_stack[name] = value
      end

      def get_variable(name : ::String)
        variable_stacks.reverse_each do |stack|
          val = stack[name]
          return val unless val.is_a?(Null)
        end
        NULL
      end

      def add_variable_stack
        # raise
        @variable_stacks << VariableStack.new
      end
    end
  end
end
