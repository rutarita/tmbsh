require "./interpreter"
require "./exceptions"
require "./context"

# require "./user_defined_function"
module TMBSH
  class Interpreter
    class VariableRef
      @name : StringName

      def initialize(name : ::String)
        @name = StringName.new(name)
      end

      def initialize(name : StringName)
        @name = name
      end

      def get(context : Context) : Variant
        context.get_variable(@name)
      end
    end

    abstract class Node
      abstract def constant? : ::Bool
    end

    abstract struct Action
      abstract def constant? : ::Bool # means always the same regardless the context
      abstract def apply(to : Variant, context : Context) : Variant
    end

    struct KeyAccess < Action
      @key : ValueNode
      getter key

      def initialize(key : ValueNode)
        @key = key
      end

      def constant? : ::Bool
        @key.constant?
      end

      def apply(to : Variant, context : Context) : Variant
        to[@key.evaluate(context)]
      end
    end

    struct OptionalKeyAccess < Action
      @key : ValueNode
      getter key

      def initialize(key : ValueNode)
        @key = key
      end

      def constant? : ::Bool
        @key.constant?
      end

      def apply(to : Variant, context : Context) : Variant
        to[@key.evaluate(context)]?
      end
    end

    struct KeyAssignment < Action
      @key : ValueNode
      @value : ValueNode
      getter key

      def initialize(key : ValueNode, value : ValueNode)
        @key = key
        @value = value
      end

      def constant? : ::Bool
        @key.constant? && @value.constant?
      end

      def apply(to : Variant, context : Context) : Variant
        to[@key.evaluate(context)] = @value.evaluate(context)
      end
    end

    #
    # struct MethodAccess < Action
    #   @method_name : StringName
    #   getter method_name
    #
    #   def initialize(method_name : ::String)
    #     @method_name = StringName.new(method_name)
    #   end
    #
    #   def intialize(method_name : StringName)
    #     @method_name = method_name
    #   end
    #
    #   def constant? : ::Bool
    #     true
    #   end
    #
    #   def apply(to : Variant, context : Context) : Variant
    #     to.get_method(@method_name)
    #   end
    # end

    struct MethodCall < Action
      @args : ::Array(ValueNode)
      @method_name : StringName
      getter args
      getter method_name

      def initialize(method_name : ::String, args : ::Array(ValueNode))
        @args = args
        @method_name = StringName.new(method_name)
      end

      def constant? : ::Bool
        @args.each do |a|
          return false unless a.constant?
        end
        true
      end

      def apply(to : Variant, context : Context) : Variant
        # args = @args.map &.evaluate(context)
        # args.unshift(to)
        args_size = @args.size + 1
        args = ::Array(Variant).build(args_size) do |ptr|
          ptr[0] = to
          @args.each_with_index(1) do |item, idx|
            ptr[idx] = item.evaluate(context)
          end
          args_size
        end
        # {%if flag?(:method_hash_caching)%}
        # p! "after call"
        # if method = to.get_method(@method_hash)
        # method.call(context, args)
        # else
        to.get_method(@method_name).call(context, args)
        # end
        # {% else %}
        # to.get_method(@method_name).call(context, args)
        # {% end %}
      end
    end

    struct AttributeAccess < Action
      @name : ::String

      def initialize(name : ::String)
        @name = name
      end

      def apply(to : Variant, context : Context) : Variant
        to.get_attribute(@name)
      end

      def constant? : ::Bool
        true
      end
    end

    struct AttributeAssignment < Action
      @name : StringName
      @value : ValueNode

      def initialize(name : ::String, value : ValueNode)
        @name = StringName.new(name)
        @value = value
      end

      def initialize(name : StringName, value : ValueNode)
        @name = name
        @value = value
      end

      def apply(to : Variant, context : Context) : Variant
        to.set_attribute(@name, @value.evaluate(context))
      end

      def constant? : ::Bool
        @value.constant?
      end
    end

    struct Call < Action
      @args : ::Array(ValueNode)

      def initialize(args : ::Array(ValueNode))
        @args = args
      end

      def apply(to : Variant, context : Context) : Variant
        args = @args.map &.evaluate(context).as(Variant)
        to.call(context, args)
      end

      def constant? : ::Bool
        @args.each do |a|
          return false unless a.constant?
        end
        true
      end
    end

    struct AsyncCall < Action
      @args : ::Array(ValueNode)

      def initialize(args : ::Array(ValueNode))
        @args = args
      end

      def apply(to : Variant, context : Context) : Variant
        args = @args.map &.evaluate(context).as(Variant)
        channel = Channel(Variant).new
        async_context = context.dup
        async_context.add_variable_stack
        # p! args
        spawn do
          val = to.call(async_context, args)
          channel.send(val)
        end
        Promise.new(channel)
      end

      def constant? : ::Bool
        @args.each do |a|
          return false unless a.constant?
        end
        true
      end
    end

    abstract class ValueNode < Node
      @actions : ::Deque(Action) = Deque(Action).new
      property actions

      def add_action(action : Action)
        @actions << action
        # puts action
      end

      def add_actions(other_actions : ::Deque(Action))
        if @actions.empty?
          @actions = other_actions
        else
          @actions.concat(other_actions)
        end
      end

      protected def apply_actions(to : Variant, context : Context) : Variant
        var = to
        # puts @actions
        @actions.each do |action|
          var = action.apply(var, context)
        end
        var
      end

      protected def actions_constant? : ::Bool
        @actions.each do |action|
          return false unless action.constant?
        end
        true
      end

      abstract def evaluate(context : Context) : Variant
      abstract def constant? : ::Bool
      abstract def fold : Variant?
    end

    class SingleValueNode < ValueNode
      @value : Variant | VariableRef

      def initialize(val : Variant | VariableRef)
        @value = val
      end

      def evaluate(context : Context) : Variant
        val = @value
        if val.is_a?(VariableRef)
          val = val.get(context)
        end
        apply_actions(val, context)
      end

      def constant? : ::Bool
        @value.is_a?(Variant) && !@value.is_a?(Function)
      end

      def fold : Variant?
        val = @value
        if val.is_a?(Variant)
          return val
        end
      end
    end

    class MathExpressionNode < ValueNode
      enum Operation
        None
        Add
        Sub
        Mul
        Div
        FDiv
        Pow
        Mod

        And
        Or
        Xor
      end

      # @parts = [] of Int64 | Float64 | MathExpressionNode | VariableRef | Operation
      @parts = [] of {Int64 | Float64 | MathExpressionNode | VariableRef, Operation}

      # @separated_parts
      # def add_part(part : Int64 | Float64 | MathExpressionNode | VariableRef | Operation)
      def add_part(part : Int64 | Float64 | MathExpressionNode | VariableRef, op : Operation)
        # @parts << part
        @parts << {part, op}
      end

      def constant? : ::Bool
        false
      end

      private def separate_parts
      end

      def evaluate_num : Int64 | Float64
        0.0
      end

      def evaluate(context : Context) : Variant
        p! @parts
        num = evaluate_num
        case num
        in Int64
          Int.new(num)
        in Float64
          Float.new(num)
        end
      end

      def fold : Variant?
      end
    end

    class StringNode < ValueNode
      enum ExpansionType
        PathSeparator
        SingleWildcard
        MultipleWildcard
        Home

        def to_s : ::String
          case self
          # when ExpansionType::PathSeparator
          #   return "/"
          # when ExpansionType::SingleWildcard
          #   return "?"
          # when ExpansionType::MultipleWildcard
          #   return "*"
          # when ExpansionType::Home
          #   return Path.home.to_s
          in .path_separator?    then return "/"
          in .single_wildcard?   then return "?"
          in .multiple_wildcard? then return "*"
          in .home?              then return Path.home.to_s
          end
        end
      end
      @parts : ::Array(ExpansionType | ValueNode | ::String) = [] of ExpansionType | ValueNode | ::String
      @absolute : ::Bool = false
      @path_dir_end : ::Bool = false

      def empty?
        @parts.empty?
      end

      @string_variant_cache : ::Hash(::String, String) = {} of ::String => String

      private def create_string(str)
        if variant = @string_variant_cache[str]?
          variant
        else
          variant = String.new(str)
          @string_variant_cache[str] = variant
          variant
        end
      end

      private def expand_path(cwd : ::String, dir_path : Path?, pattern : Regex | ::String, dirs_only : ::Bool) : ::Array(Path)?
        if dir_path
          if pattern.is_a?(Regex) && Dir.exists?(dir_path)
            arr = Dir.children(dir_path).select do |entry_name|
              pattern.match(entry_name) unless dirs_only && !Dir.exists?(dir_path / entry_name)
            end.map do |path|
              dir_path / path
            end
            arr unless arr.empty?
          else
            [dir_path / pattern] if pattern.is_a?(::String)
          end
        else
          if pattern.is_a?(Regex)
            arr = Dir.children(cwd).select do |entry_name|
              pattern.match(entry_name) unless dirs_only && !Dir.exists?(entry_name)
            end.map do |path|
              Path[path]
            end
            arr unless arr.empty?
          else
            [Path[pattern]]
          end
        end
      end

      private def exclude_hidden_files(str_reg : ::String)
        if str_reg != "\\." && str_reg != "\\.\\." && str_reg.starts_with?("\\.")
          str_reg
        else
          "^(?!\\.)" + str_reg.lchop("^\\.")
        end
      end

      private def assemble(parts : ::Array({::String, ::Bool}), regex_enabled : ::Bool) : ::String | Regex
        if regex_enabled
          str = ::String.build do |io|
            io << '^'
            parts.each do |part, is_regex|
              if is_regex
                io << part
              else
                io << Regex.escape(part)
              end
            end
            io << '$'
          end
          unless str.starts_with?("^\\.")
            str = exclude_hidden_files(str)
          end
          Regex.new(str)
        else
          ::String.build do |io|
            parts.each do |part, _|
              io << part
            end
          end
        end
      end

      private def separate(context : Context) : ::Array(Regex | ::String)
        separated = [] of Regex | ::String
        using_regex = false
        string_parts = [] of {::String, ::Bool}
        @parts.each do |part|
          if part.is_a?(::String)
            string_parts << {part, false}
          elsif part.is_a?(ValueNode)
            var = part.evaluate(context)
            # raise "Cannot interpolate non-string variable into a string" unless var.is_a?(String | Int | Float | Null)
            unless var.is_a?(Null)
              string_parts << {var.to_s, false}
            end
          elsif part.is_a?(ExpansionType)
            case part
            when ExpansionType::Home
              separated.concat(part.to_s[1..].split('/')) # .map { |str| {str, false} })
              string_parts.clear
              using_regex = false
            when ExpansionType::PathSeparator
              unless string_parts.empty?
                pathling = assemble(string_parts, using_regex)
                string_parts.clear
                separated << pathling
                using_regex = false
              end
            when ExpansionType::SingleWildcard
              string_parts << {".", true}
              using_regex = true
            when ExpansionType::MultipleWildcard
              string_parts << {".*", true}
              using_regex = true
            end
          end
        end
        unless string_parts.empty?
          pathling = assemble(string_parts, using_regex)
          string_parts.clear
          separated << pathling
        end
        separated
      end

      private def expand_paths(cwd : ::String, paths : ::Array(::Path), pattern : Regex | ::String, dirs_only : ::Bool)
        result = [] of ::Path
        paths.each do |path|
          begin
            if expanded_path = expand_path(cwd, path, pattern, dirs_only)
              # p! expanded_path
              result.concat(expanded_path)
            end
          rescue e
            puts "Error expanding path: #{e}"
          end
        end
        result
      end

      private def to_literal(context : Context) : String
        str = ::String.build do |io|
          @parts.each do |part|
            if part.is_a?(ValueNode)
              var = part.evaluate(context)
              # if var.is_a?(String) || var.is_a?(Float | Int)
              if var.is_a?(Null)
                # nothing
              else
                io << var.to_s
              end
            else
              io << part.to_s
            end
          end
        end
        create_string(str)
      end

      private def expand_attempt(context : Context) : Variant
        unless @string_will_expand
          return to_literal(context)
        end
        separated = separate(context)
        @path_dir_end = true if @parts.last == ExpansionType::PathSeparator
        if separated.empty?
          raise "Somehow the string is empty"
        end
        initial_path = @absolute ? Path["/"] : nil
        # p! separated
        expanded = expand_path(context.cwd, initial_path, separated[0], separated.size > 1 || @path_dir_end)
        return to_literal(context) unless expanded
        separated.each(within: 1...-1) do |pattern|
          expanded = expand_paths(context.cwd, expanded, pattern, true)
          return to_literal(context) if expanded.empty?
        end
        unless separated.size == 1
          expanded = expand_paths(context.cwd, expanded, separated.last, @path_dir_end)
        end
        # p! expanded
        return to_literal(context) if expanded.empty?
        array = [] of Variant
        expanded.each do |item|
          array << create_string(item.to_s)
        end
        Array.new(array)
      end

      def evaluate(context : Context) : Variant
        var = expand_attempt(context)
        apply_actions(var, context)
      end

      def constant? : ::Bool
        @parts.each do |part|
          return false if (part.is_a?(ExpansionType) && part != ExpansionType::PathSeparator) || part.is_a?(VariableRef)
        end
        true
      end

      @string_will_expand : ::Bool = false
      @pure_string : ::Bool = true

      def pure_string? : ::Bool
        @pure_string
      end

      def to_single_value_node : SingleValueNode
        if @parts.size == 1
          part = @parts[0]
          return SingleValueNode.new(create_string(part.to_s))
        end
        str = ::String.build do |io|
          @parts.each do |part|
            raise "Must be pure string to convert to SingleValueNode" unless part.is_a?(::String) || part == ExpansionType::PathSeparator
            io << part.to_s
          end
        end
        SingleValueNode.new(create_string(str))
      end

      def add_path_separator
        @absolute = true if @parts.empty?
        @parts << ExpansionType::PathSeparator
      end

      def add_home
        @absolute = true
        @pure_string = false
        @parts << ExpansionType::Home
      end

      def add_single_wildcard
        @parts << ExpansionType::SingleWildcard
        @string_will_expand = true
        @pure_string = false
      end

      def add_multiple_wildcard
        @parts << ExpansionType::MultipleWildcard
        @string_will_expand = true
        @pure_string = false
      end

      def add_string(str : ::String)
        @parts << str unless str.empty?
      end

      def add_node(var : ValueNode)
        @parts << var
        @pure_string = false
      end

      def fold : Variant?
      end
    end

    class ArrayValueNode < ValueNode
      @items : ::Array(ValueNode) = [] of ValueNode

      def initialize
      end

      def initialize(items : ::Array(ValueNode))
        @items = items
      end

      def <<(val : ValueNode)
        @items << val
      end

      def evaluate(context : Context) : Variant
        arr = @items.map do |item|
          item.evaluate(context)
        end
        apply_actions(Array.new(arr), context)
      end

      def constant? : ::Bool
        @items.each do |item|
          return false unless item.constant?
        end
        true
      end

      def fold : Variant?
        only_variants = true
        variants_arr = [] of Variant
        arr = @items.map do |item|
          if folded = item.fold
            variants_arr << folded if only_variants
            SingleValueNode.new(folded)
          else
            only_variants = false
            item
          end
        end
        if only_variants
          Array.new(variants_arr)
        else
          @items = arr
          nil
        end
      end
    end

    class SetValueNode < ValueNode
      @items : ::Array(ValueNode) = [] of ValueNode

      def initialize
      end

      def initialize(items : ::Array(ValueNode))
        @items = items
      end

      def <<(val : ValueNode)
        @items << val
      end

      def evaluate(context : Context) : Variant
        arr = @items.map do |item|
          item.evaluate(context)
        end
        apply_actions(Set.new(arr), context)
      end

      def constant? : ::Bool
        @items.each do |item|
          return false unless item.constant?
        end
        true
      end

      def fold : Variant?
        only_variants = true
        variants_arr = [] of Variant
        arr = @items.map do |item|
          if folded = item.fold
            variants_arr << folded if only_variants
            SingleValueNode.new(folded)
          else
            only_variants = false
            item
          end
        end
        if only_variants
          Set.new(variants_arr)
        else
          @items = arr
          nil
        end
      end
    end

    class DictionaryValueNode < ValueNode
      @keys_values : ::Array({ValueNode, ValueNode}) = [] of {ValueNode, ValueNode}

      def initialize
      end

      def initialize(pairs : ::Array({ValueNode, ValueNode}))
        @keys_values = pairs
      end

      def add_pair(key : ValueNode, value : ValueNode)
        @keys_values << {key, value}
      end

      def <<(pair : {ValueNode, ValueNode})
        @keys_values << pair
      end

      def evaluate(context : Context) : Variant
        dict = {} of Variant => Variant
        @keys_values.each do |k, v|
          k = k.evaluate(context)
          v = v.evaluate(context)
          dict[k] = v
        end
        apply_actions(Dictionary.new(dict), context)
      end

      def constant? : ::Bool
        @keys_values.each do |k, v|
          return false unless k.constant? && v.constant?
        end
        true
      end

      def fold : Variant?
        only_variants = true
        variants_arr = [] of {Variant, Variant}
        arr = @keys_values.map do |key, value|
          key_folded = nil
          value_folded = nil
          if folded = key.fold
            key_folded = folded
          else
            only_variants = false
          end
          if folded = value.fold
            value_folded = folded
          else
            only_variants = false
          end
          if only_variants && key_folded && value_folded
            variants_arr << {key_folded, value_folded}
          end
          {key_folded ? SingleValueNode.new(key_folded) : key, value_folded ? SingleValueNode.new(value_folded) : value}
        end
        if only_variants
          dict = Dictionary.new
          variants_arr.each do |k, v|
            dict[k] = v
          end
          dict
        else
          @keys_values = arr
          nil
        end
      end
    end

    class ConditionNode < ValueNode
      enum ContinueType
        And
        Or
      end

      @conditions : ::Array({ValueNode, ::Bool}) = [] of {ValueNode, ::Bool}
      @continue_types : ::Array(ContinueType) = [] of ContinueType

      def add_condition(condition : ValueNode, negate : ::Bool)
        @conditions << {condition, negate}
      end

      def add_and
        @continue_types << ContinueType::And
      end

      def add_or
        @continue_types << ContinueType::Or
      end

      def fold : Variant?
      end

      def evaluate(context : Context) : Variant
        res, negate = @conditions[0]
        res = res.evaluate(context)
        res = !res.truthy? ? TRUE : FALSE if negate
        @conditions[1..].each_with_index do |val, idx|
          cont = @continue_types[idx]
          if cont == ContinueType::And
            if res.truthy?
              res, negate = val
              res = res.evaluate(context)
              res = !res.truthy? ? TRUE : FALSE if negate
            else
              break
            end
          else
            if res.truthy?
              break
            else
              res, negate = val
              res = res.evaluate(context)
              res = !res.truthy? ? TRUE : FALSE if negate
            end
          end
        end
        res
      end

      def constant? : ::Bool
        false
      end
    end

    class CaptureCommandNode < ValueNode
      # @statements : ::Array(StatementNode)
      @body : StatementBlockNode
      @chomp : ::Bool = true
      @async : ::Bool = false
      @block_error : ::Bool = false
      @return_status : ::Bool = false
      @collect_array : ::Bool = false

      # def initialize(statements : ::Array(StatementNode))
      #   @statements = statements
      # end

      def initialize(body : StatementBlockNode)
        @body = body
      end

      private def capture(context)
        mem = IO::Memory.new
        # @statements.each do |statement|
        #   statement.execute(interpreter, mem)
        # end
        capture_context = context.dup
        capture_context.output = mem
        capture_context.error = nil if @block_error
        capture_context.add_variable_stack
        @body.execute(capture_context)
        str = mem.to_s
        str = str.chomp if @chomp
        var = String.new(str)
        # apply_actions(var, context)
      end

      private def capture_status(context)
        closed_context = context.dup
        closed_context.input = nil
        closed_context.output = nil
        closed_context.error = nil
        closed_context.add_variable_stack
        res = @body.execute(closed_context)
        if res.is_a?(CommandFinish)
          status = res.status
          status ? ExitStatus.new(status.exit_code, status) : NULL
        else
          NULL
        end
      end

      private def capture_depending(context : Context)
        unless @return_status
          capture(context)
        else
          capture_status(context)
        end
      end

      def evaluate(context : Context) : Variant
        result = unless @async
          capture_depending(context)
        else
          channel = Channel(Variant).new
          spawn do
            val = capture_depending(context)
            channel.send(val)
          end
          Promise.new(channel)
        end
        apply_actions(result, context)
      end

      def dont_chomp
        @chomp = false
      end

      def async
        @async = true
      end

      def block_error
        @block_error = true
      end

      def return_status
        @return_status = true
      end

      def constant? : ::Bool
        false
      end

      def fold : Variant?
      end
    end

    macro create_proc_func_end
      res = @body.execute(context)
      if res.is_a?(Return)
        result_value = res.value
      end
      # @body.unset_variables
      result_value
    end

    macro create_proc_func
      private def create_proc : Proc(Context, ::Array(Variant), Variant?)
        case {@last_is_splat, !@optional_start_index.nil?}
        # if optional_start_index = @optional_start_index
        # if @last_is_splat
        in {true, true} # splat and optional
          optional_start_index = @optional_start_index.not_nil!
          ->(context : Context, args : ::Array(Variant)) : Variant? {
            raise ArgumentError.new("Expected #{optional_start_index} or more arguments") if args.size < optional_start_index
            @argnames[...-1].each_with_index do |name, idx|
              if idx >= optional_start_index
                @body.set_variable(name, args[idx]? || NULL)
              else
                @body.set_variable(name, args[idx])
              end
            end
            splatted = args[(@argnames.size - 1)..]?
            if splatted && !splatted.empty?
              @body.set_variable(@argnames[-1], Array.new(splatted))
            else
              @body.set_variable(@argnames[-1], NULL)
            end
            TMBSH::Interpreter.create_proc_func_end
          }
          # else
        in {false, true} # optional
          optional_start_index = @optional_start_index.not_nil!
          ->(context : Context, args : ::Array(Variant)) : Variant? {
            if args.size > @argnames.size || args.size < optional_start_index
              raise ArgumentError.new("Expected #{optional_start_index + 1}..#{@argnames.size} arguments")
            end
            @argnames.each_with_index do |name, idx|
              if idx >= optional_start_index
                @body.set_variable(name, args[idx]? || NULL)
              else
                @body.set_variable(name, args[idx])
              end
            end
            TMBSH::Interpreter.create_proc_func_end
          }
          # end
          # else
          # if @last_is_splat
        in {true, false} # splat
          ->(context : Context, args : ::Array(Variant)) : Variant? {
            raise ArgumentError.new("Expected #{@argnames.size} or more arguments") if @argnames.size > args.size
            @argnames[...-1].each_with_index do |name, idx|
              @body.set_variable(name, args[idx])
            end
            @body.set_variable(@argnames[-1], Array.new(args[(@argnames.size - 1)..]))
            TMBSH::Interpreter.create_proc_func_end
          }
          # else
        in {false, false} # all args
          ->(context : Context, args : ::Array(Variant)) : Variant? {
            raise ArgumentError.new("Expected #{@argnames.size} arguments") if @argnames.size != args.size
            @argnames.each_with_index do |name, idx|
              @body.set_variable(name, args[idx])
            end
            TMBSH::Interpreter.create_proc_func_end
          }
          # end
          # end
        end
      end
    end

    class LambdaNode < ValueNode
      @argnames : ::Array(::String)
      @last_is_splat : ::Bool
      @optional_start_index : Int32?
      @body : StatementBlockNode

      def initialize(argnames : ::Array(::String), last_is_splat : ::Bool, optional_start_index : Int32?, body : StatementBlockNode)
        @argnames = argnames
        @last_is_splat = last_is_splat
        @body = body
        @optional_start_index = optional_start_index
      end

      def evaluate(context : Context) : Variant
        Function.new(create_proc)
      end

      def constant? : ::Bool
        false
      end

      def fold : Variant?
      end

      TMBSH::Interpreter.create_proc_func
    end

    abstract class StatementNode < Node
      abstract def execute(context : Context)

      def execute(interpreter : Interpreter)
        execute(
          Context.new(interpreter)
        )
      end

      property exit_code : Int32?
      # abstract def capture(interpreter )
    end

    class CommandNode < StatementNode
      enum ProceedType
        None
        Pipe
        OnSuccess
        OnFail
      end
      # @parts : ::Deque(ValueNode)
      # @folded_parts : ::Deque(ValueNode | Variant)?
      @parts : ::Array(ValueNode)
      @folded_parts : ::Array(ValueNode | Variant)?
      @proceed_type : ProceedType = ProceedType::None
      property proceed_type
      @write_to_file : ::Bool = true
      property write_to_file
      @file_write_target : ValueNode?
      property file_write_target
      @file_read_target : ValueNode?
      property file_read_target
      @proceeding : CommandNode?
      property proceeding
      @fork_command : ::Bool = false
      property fork_command
      @env_vars_pairs : ::Array({::String, ValueNode}) = [] of {::String, ValueNode}
      property env_vars_pairs
      @env_vars : Hash(::String, ::String | Nil)?

      @is_builtin : ::Bool = false
      property is_builtin

      @attached_process : Process?
      property attached_process

      private def add_env_var(key : ::String, value : Variant)
        if value.is_a?(Null)
          value = nil
        else
          value = value.to_s
        end
        env = @env_vars || {} of ::String => ::String | Nil
        env[key] = value
        @env_vars = env
      end

      private def set_env_vars_from_pairs(context : Context)
        @env_vars_pairs.each do |k, v|
          v = v.evaluate(context)
          add_env_var(k, v)
        end
      end

      def initialize
        # @parts = Deque(ValueNode).new
        @parts = [] of ValueNode
      end

      def <<(val : ValueNode)
        @parts << val
      end

      def constant? : ::Bool
        @parts.each do |part|
          return false unless parts.constant?
        end
        true
      end

      def fold
      end

      private def append_variant(target_arr : ::Deque(::String), variant : Variant) : Nil
        return if variant.is_a?(Null | Promise)
        if variant.is_a?(Array | Set)
          target_arr.concat(variant.to_string_array)
        elsif variant.is_a?(Dictionary)
          target_arr.concat(variant.pairs("=", "--"))
        else
          target_arr << variant.to_s
        end
      end

      private def create_str_args(context : Context) : ::Deque(::String)
        parts_str = ::Deque(::String).new
        if folded = @folded_parts
          first = folded[0]
          first = first.is_a?(Variant) ? first : first.evaluate(context)
          if first.is_a?(Dictionary)
            first.@value.each do |k, v|
              add_env_var(k.to_s, v)
            end
          else
            append_variant(parts_str, first)
          end
          folded.each(within: 1..) do |item|
            append_variant(parts_str, item.is_a?(Variant) ? item : item.evaluate(context))
          end
        else
          first = @parts[0].evaluate(context)
          if first.is_a?(Dictionary)
            first.@value.each do |k, v|
              add_env_var(k.to_s, v)
            end
          else
            append_variant(parts_str, first)
          end
          @parts.each(within: 1..) do |item|
            append_variant(parts_str, item.evaluate(context))
          end
        end
        parts_str
      end

      @file : ::File?

      private def get_write_file_io(context : Context)
        if target = @file_write_target
          @file = ::File.open(target.evaluate(context).to_s, @write_to_file ? "w" : "a")
        end
      end

      private def get_read_file_io(context : Context)
        if target = @file_read_target
          @file = ::File.open(target.evaluate(context).to_s)
        end
      end

      private def resolve_alias(context : Context, str_args : ::Deque(::String))
        while ary = context.interpreter.resolve_alias(str_args[0])
          str_args.shift
          ary.reverse_each do |e|
            str_args.unshift e
          end
        end
      end

      @shell_command_result : Result?

      def create_process(
        context : Context,
        input_io : IO | Process::Redirect = :Inherit,
        output_io : IO | Process::Redirect = :Inherit,
        error_io : IO | Process::Redirect = :Inherit, # lets keep the explicit ios to not duplicate the context every time
      ) : Process?
        set_env_vars_from_pairs(context)
        args = create_str_args(context)
        return if args.empty?
        resolve_alias(context, args)
        command = args.shift
        if shell_command = context.interpreter.get_shell_command(command)
          # execute_shell_command(shell_command, args, input_io, output_io, error_io)
          shell_command_input_io = if input_io.is_a?(Process::Redirect)
                                     case input_io
                                     when .inherit?
                                       STDIN
                                       # when .
                                     end
                                   else
                                     input_io
                                   end
          shell_command_output_io = if output_io.is_a?(Process::Redirect)
                                      case output_io
                                      when .inherit?
                                        STDIN
                                        # when .
                                      end
                                    else
                                      output_io
                                    end
          shell_command_error_io = if error_io.is_a?(Process::Redirect)
                                     case error_io
                                     when .inherit?
                                       STDIN
                                       # when .
                                     end
                                   else
                                     error_io
                                   end
          if @fork_command
            spawn do
              @shell_command_result = shell_command.call(
                context, shell_command_input_io, shell_command_output_io, shell_command_error_io, args
              )
            end
          else
            @shell_command_result = shell_command.call(
              context, shell_command_input_io, shell_command_output_io, shell_command_error_io, args
            )
          end
          return
        end
        process = nil
        write_file = get_write_file_io(context)
        read_file = get_read_file_io(context)
        if proceed_type == ProceedType::Pipe
          if proceeding_command = @proceeding
            process = Process.new(
              command, args,
              input: read_file || input_io,
              output: write_file || Process::Redirect::Pipe,
              error: error_io,
              env: @env_vars,
              chdir: context.cwd
            )
            proceeding_command.create_process(
              context, write_file ? Process::Redirect::Close : process.output, output_io
            )
          else
            raise "Expected other command when piping"
          end
        else
          process = Process.new(
            command, args,
            input: read_file || input_io,
            output: write_file || output_io,
            error: error_io,
            env: @env_vars,
            chdir: context.cwd
          )
        end
        @attached_process = process
        process
      end

      @status : Process::Status?

      def wait(context : Context) : Nil
        if process = @attached_process
          @status = process.wait
          @file.try &.close
          if proceeding = @proceeding
            process.output.finalize if process.output?
            proceeding.wait(context)
          end
        else
          if proceeding = @proceeding
            proceeding.wait(context)
          end
        end
        if proceeding = @proceeding
          exit_code = @status.try &.exit_code?
          case @proceed_type
          when .on_success?
            proceeding.execute(context, false) if exit_code == 0
          when .on_fail?
            proceeding.execute(context, false) if exit_code != 0
          end
        end
      end

      def execute(context : Context, allow_fork : ::Bool = true) : Result
        process_context = context
        if @fork_command
          process_context = context.dup
          process_context.add_variable_stack
        end
        process = create_process(process_context,
          input_io: context.input || Process::Redirect::Close,
          output_io: context.output || Process::Redirect::Close, error_io: context.error || Process::Redirect::Close)
        unless allow_fork && @fork_command
          wait(context)
        else
          spawn do
            wait(context)
          end
          Fiber.yield
        end
        # if status = @status
        #   exit_code = status.exit_code?
        # end
        if shell_command_result = @shell_command_result
          @shell_command_result = nil
          return shell_command_result
        end
        if status = @status
          # exit_code = status.exit_code?
          CommandFinish.new(status.exit_code?, status)
        else
          NOTHING_RESULT # TODO: maybe add some forked command result?
        end
      end
    end

    class VariableAssignmentNode < StatementNode
      @assignments : ::Array({StringName, ValueNode})

      def initialize(assignments : ::Array({StringName, ValueNode}))
        @assignments = assignments
      end

      def initialize(assignments : ::Array({::String, ValueNode}))
        @assignments = assignments.map { |str, val| {StringName.new(str), val}}
      end

      def execute(context : Context) : Result
        @assignments.each do |name, value|
          context.set_variable(name, value.evaluate(context))
        end
        NOTHING_RESULT
      end

      def constant? : ::Bool
        @assignments.each do |_, v|
          return false unless v.constant?
        end
        true
      end
    end

    class StatementBlockNode < StatementNode
      @statements : ::Array(StatementNode) = [] of StatementNode
      @vars : ::Hash(StringName, Variant) = {} of StringName => Variant

      # @auto_scope_managment = true
      # property auto_scope_managment
      def initialize
      end

      def <<(statement : StatementNode)
        @statements << statement
      end

      def execute(context : Context) : Result
        # if @auto_scope_managment
        context.enter_scope
        @vars.each do |name, value|
          context.shadow_variable(name, value)
        end
        # end
        res = nil
        @statements.each do |statement|
          res = statement.execute(context)
          if res.is_a?(Return | Break | Continue)
            context.exit_scope
            # context.exit_scope if @auto_scope_managment
            return res
          end
        end
        # context.exit_scope if @auto_scope_managment
        context.exit_scope
        res || NOTHING_RESULT
      end

      def set_variable(name : StringName, value : Variant)
        @vars[name] = value
      end

      def set_variable(name : ::String, value : Variant)
        set_variable(StringName.new(name), value)
      end

      def unset_variables
        @vars = {} of ::String => Variant
      end

      def constant? : ::Bool
        false
      end
    end

    BREAK_STATEMENT_NODE          = BreakStatementNode.new
    CONTINUE_STATEMENT_NODE       = ContinueStatementNode.new
    NOTHING_RETURN_STATEMENT_NODE = ReturnStatementNode.new

    class BreakStatementNode < StatementNode
      def execute(context : Context) : Result
        BREAK_RESULT
      end

      def constant? : ::Bool
        true
      end
    end

    class ContinueStatementNode < StatementNode
      def execute(context : Context)
        CONTINUE_RESULT
      end

      def constant? : ::Bool
        true
      end
    end

    class ReturnStatementNode < StatementNode
      @value : ValueNode?

      def initialize(value : ValueNode? = nil)
        @value = value
      end

      def execute(context : Context) : Result
        Return.new(@value.try &.evaluate(context))
      end

      def constant? : ::Bool
        if val = @value
          val.constant?
        else
          true
        end
      end
    end

    class IfStatementNode < StatementNode
      @condition : ConditionNode
      @varname : StringName?
      property varname
      @body : StatementBlockNode
      @elsif_bodies : ::Array({ConditionNode, StatementBlockNode, StringName?}) = [] of {ConditionNode, StatementBlockNode, StringName?}
      property elsif_bodies
      @else_body : StatementBlockNode?
      property else_body

      def initialize(condition : ConditionNode, body : StatementBlockNode, varname : StringName?)
        @condition = condition
        @body = body
        @varname = varname
      end
      def initialize(condition : ConditionNode, body : StatementBlockNode, varname : ::String?)
        @condition = condition
        @body = body
        @varname = StringName.new(varname) if varname
      end

      def execute(context : Context) : Result
        condition_result = @condition.evaluate(context)
        if condition_result.truthy?
          if varname = @varname
            @body.set_variable(varname, condition_result)
          end
          res = @body.execute(context)
          # @body.unset_variables
          # if res.is_a?(Result | Break)
          return res
          # end
        else
          @elsif_bodies.each do |condition, block, varname|
            # p! condition, block, varname
            condition_result = condition.evaluate(context)
            if condition_result.truthy?
              if varname
                block.set_variable(varname, condition_result)
              end
              res = block.execute(context)
              # block.unset_variables
              # if res.is_a?(Result | Break)
              return res
              # end
              return NOTHING_RESULT
            end
          end
          if else_body = @else_body
            res = else_body.execute(context)
            # else_body.unset_variables
            # if res.is_a?(Result | Break)
            return res
            # end
            # what was i thinking?
          end
        end
        NOTHING_RESULT
      end

      def constant? : ::Bool
        false
      end
    end

    class WhileStatementNode < StatementNode
      @body : StatementBlockNode
      @condition : ConditionNode
      @varname : StringName?
      property varname

      def initialize(condition : ConditionNode, body : StatementBlockNode, varname : ::String? = nil)
        @body = body
        @condition = condition
        @varname = StringName.new(varname) if varname
      end
      def initialize(condition : ConditionNode, body : StatementBlockNode, varname : StringName? = nil)
        @body = body
        @condition = condition
        @varname = varname
      end

      def execute(context : Context) : Result
        while true
          condition = @condition.evaluate(context)
          break unless condition.truthy?
          if varname = @varname
            @body.set_variable(varname, condition)
          end
          res = @body.execute(context)
          if res.is_a?(Return)
            return res
          end
          break if res.is_a?(Break)
        end
        NOTHING_RESULT
      end

      def constant? : ::Bool
        false
      end
    end

    class ForStatementNode < StatementNode
      @varnames : ::Array(StringName)
      @iterable : ValueNode
      @body : StatementBlockNode

      def initialize(varnames : ::Array(StringName), iterable : ValueNode, body : StatementBlockNode)
        # body.auto_scope_managment = false
        @varnames = varnames
        @iterable = iterable
        @body = body
      end
      def initialize(varnames : ::Array(::String), iterable : ValueNode, body : StatementBlockNode)
        # body.auto_scope_managment = false
        @varnames = varnames.map {|val| StringName.new(val)}
        @iterable = iterable
        @body = body
      end

      macro execute_block
        res = @body.execute(context)
        if res.is_a?(Break)
          break
        end
        if res.is_a?(Return)
          return res
        end
      end

      def execute(context : Context) : Result
        variant = @iterable.evaluate(context)
        iter = variant.is_a?(Iterator) ? variant : variant.iter_init(context)
        if @varnames.size == 1
          iter.each(context) do |val|
            @body.set_variable(@varnames[0], val)
            TMBSH::Interpreter::ForStatementNode.execute_block
          end
        elsif @varnames.empty?
          iter.each(context) do |val|
            TMBSH::Interpreter::ForStatementNode.execute_block
          end
        else
          iter.each(context) do |val|
            raise "Splatting is only allowed on Array" unless val.is_a?(Array)
            arr = val.@value
            @varnames.each_with_index do |name, i|
              @body.set_variable(name, arr[i]? || NULL)
            end
            TMBSH::Interpreter::ForStatementNode.execute_block
          end
        end
        NOTHING_RESULT
      end

      def constant? : ::Bool
        false
      end
    end

    class FunctionDefinitionNode < StatementNode
      @funcname : ::String
      @argnames : ::Array(::String)
      @last_is_splat : ::Bool
      @optional_start_index : Int32?
      @body : StatementBlockNode

      def initialize(funcname : ::String, argnames : ::Array(::String), optional_start_index : Int32?, last_is_splat : ::Bool, body : StatementBlockNode)
        @funcname = funcname
        @argnames = argnames
        @last_is_splat = last_is_splat
        @optional_start_index = optional_start_index
        @body = body
      end

      TMBSH::Interpreter.create_proc_func

      def execute(context : Context) : Result
        function = Function.new(create_proc)
        function.name = @funcname
        context.shadow_variable(@funcname, function)
        NOTHING_RESULT
      end

      def constant? : ::Bool
        false
      end
    end

    class EmptyStatementNode < StatementNode
      def execute(context : Context,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        NOTHING_RESULT
      end

      def constant? : ::Bool
        true
      end
    end

    EMPTY_STATEMENT_NODE = EmptyStatementNode.new

    NOTHING_RESULT  = Nothing.new
    BREAK_RESULT    = Break.new
    CONTINUE_RESULT = Continue.new

    abstract struct Result
    end

    struct Return < Result
      @value : Variant
      getter value

      def initialize(value : Variant?)
        @value = value || NULL
      end
    end

    struct Break < Result
    end

    struct Continue < Result
    end

    struct CommandFinish < Result
      @exit_code : Int32?
      getter exit_code
      @status : Process::Status?
      getter status

      def initialize(exit_code : Int32?, status : Process::Status? = nil)
        @exit_code = exit_code
        @status = status
      end
    end

    struct Nothing < Result
    end
  end
end
