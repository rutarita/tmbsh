require "./interpreter"
require "./exceptions"

module TMBSH
  class Interpreter
    class VariableRef
      @name : ::String

      def initialize(name : ::String)
        @name = name
      end

      def get(interpreter : Interpreter) : Variant
        interpreter.get_variable(@name)
      end
    end

    abstract class Node
      abstract def constant? : ::Bool
    end

    abstract struct Action
      abstract def constant? : ::Bool # means always the same regardless the context
      abstract def apply(to : Variant, interpreter : Interpreter) : Variant
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

      def apply(to : Variant, interpreter : Interpreter) : Variant
        to[@key.evaluate(interpreter)]
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

      def apply(to : Variant, interpreter : Interpreter) : Variant
        to[@key.evaluate(interpreter)]?
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

      def apply(to : Variant, interpreter : Interpreter) : Variant
        to[@key.evaluate(interpreter)] = @value.evaluate(interpreter)
      end
    end

    struct MethodAccess < Action
      @method_name : ::String
      getter method_name

      def initialize(method_name : ::String)
        @method_name = method_name
      end

      def constant? : ::Bool
        true
      end

      def apply(to : Variant, interpreter : Interpreter) : Variant
        to.get_method(@method_name)
      end
    end

    struct MethodCall < Action
      @args : ::Array(ValueNode)
      @method_name : ::String
      @method_hash : UInt64
      getter args
      getter method_name

      def initialize(method_name : ::String, args : ::Array(ValueNode))
        @args = args
        @method_name = method_name
        @method_hash = method_name.hash
      end

      def constant? : ::Bool
        @args.each do |a|
          return false unless a.constant?
        end
        true
      end

      def apply(to : Variant, interpreter : Interpreter) : Variant
        # args = @args.map &.evaluate(interpreter)
        # args.unshift(to)
        args_size = @args.size + 1
        args = ::Array(Variant).build(args_size) do |ptr|
          ptr[0] = to
          idx = 0
          @args.each do |item|
            idx += 1
            ptr[idx] = item.evaluate(interpreter)
          end
          args_size
        end
        {%if flag?(:method_hash_caching)%}
        if method = to.get_method(@method_hash)
          method.call(args)
        else
        to.get_method(@method_name).call(args)
        end
        {% else %}
        to.get_method(@method_name).call(args)
        {% end %}
      end
    end

    struct Call < Action
      @args : ::Array(ValueNode)

      def initialize(args : ::Array(ValueNode))
        @args = args
      end

      def apply(to : Variant, interpreter : Interpreter) : Variant
        args = @args.map &.evaluate(interpreter).as(Variant)
        to.call(args)
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

      protected def apply_actions(to : Variant, interpreter : Interpreter) : Variant
        var = to
        # puts @actions
        @actions.each do |action|
          var = action.apply(var, interpreter)
        end
        var
      end

      protected def actions_constant? : ::Bool
        @actions.each do |action|
          return false unless action.constant?
        end
        true
      end

      abstract def evaluate(interpreter : Interpreter) : Variant
      abstract def constant? : ::Bool
      abstract def fold : Variant?
    end

    class SingleValueNode < ValueNode
      @value : Variant | VariableRef

      def initialize(val : Variant | VariableRef)
        @value = val
      end

      def evaluate(interpreter : Interpreter) : Variant
        val = @value
        if val.is_a?(VariableRef)
          val = val.get(interpreter)
        end
        apply_actions(val, interpreter)
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

      @@string_pool : StringPool = StringPool.new
      private def create_string(str)
        String.new(@@string_pool.get(str))
      end

      private def expand_path(dir_path : Path?, pattern : Regex | ::String, dirs_only : ::Bool) : ::Array(Path)?
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
            arr = Dir.children(".").select do |entry_name|
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

      private def separate(interpreter : Interpreter) : ::Array(Regex | ::String)
        separated = [] of Regex | ::String
        using_regex = false
        string_parts = [] of {::String, ::Bool}
        @parts.each do |part|
          if part.is_a?(::String)
            string_parts << {part, false}
          elsif part.is_a?(ValueNode)
            var = part.evaluate(interpreter)
            raise "Cannot interpolate non-string variable into a string" unless var.is_a?(String | Int | Float | Null)
            unless var.is_a?(Null)
              string_parts << {var.to_s, false}
            end
          elsif part.is_a?(ExpansionType)
            case part
            when ExpansionType::Home
              string_parts.concat(part.to_s[1..].split('/').map { |str| {str, false} })
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

      private def expand_paths(paths : ::Array(::Path), pattern : Regex | ::String, dirs_only : ::Bool)
        result = [] of ::Path
        paths.each do |path|
          begin
            if expanded_path = expand_path(path, pattern, dirs_only)
              # p! expanded_path
              result.concat(expanded_path)
            end
          rescue e
            puts "Error expanding path: #{e}"
          end
        end
        result
      end

      private def to_literal(interpreter : Interpreter) : String
        str = ::String.build do |io|
          @parts.each do |part|
            if part.is_a?(ValueNode)
              var = part.evaluate(interpreter)
              if var.is_a?(String) || var.is_a?(Float | Int)
                io << var.to_s
              elsif var.is_a?(Null)
                # nothing
              else
                raise "Cannot interpolate non-string variable into a string" unless var.is_a?(String)
              end
            else
              io << part.to_s
            end
          end
        end
        create_string(str)
      end

      private def expand_attempt(interpreter : Interpreter) : Variant
        unless @string_will_expand
          return to_literal(interpreter)
        end
        separated = separate(interpreter)
        @path_dir_end = true if @parts.last == ExpansionType::PathSeparator
        if separated.empty?
          raise "Somehow the string is empty"
        end
        initial_path = @absolute ? Path["/"] : nil
        # p! separated
        expanded = expand_path(initial_path, separated[0], separated.size > 1 || @path_dir_end)
        return to_literal(interpreter) unless expanded
        separated.each(within: 1...-1) do |pattern|
          expanded = expand_paths(expanded, pattern, true)
          return to_literal(interpreter) if expanded.empty?
        end
        unless separated.size == 1
          expanded = expand_paths(expanded, separated.last, @path_dir_end)
        end
        # p! expanded
        return to_literal(interpreter) if expanded.empty?
        array = [] of Variant
        expanded.each do |item|
          array << create_string(item.to_s)
        end
        Array.new(array)
      end

      def evaluate(interpreter : Interpreter) : Variant
        var = expand_attempt(interpreter)
        apply_actions(var, interpreter)
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
        # to avoid copying strings too much but it didn't seem like it
        # affects the speed much so this one is gonna be used
        if @parts.size == 1
          part = @parts[0]
          return SingleValueNode.new(String.new(part.to_s))
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

      def evaluate(interpreter : Interpreter) : Variant
        arr = @items.map do |item|
          item.evaluate(interpreter)
        end
        apply_actions(Array.new(arr), interpreter)
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

      def evaluate(interpreter : Interpreter) : Variant
        arr = @items.map do |item|
          item.evaluate(interpreter)
        end
        apply_actions(Set.new(arr), interpreter)
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

      def evaluate(interpreter : Interpreter) : Variant
        dict = {} of Variant => Variant
        @keys_values.each do |k, v|
          k = k.evaluate(interpreter)
          v = v.evaluate(interpreter)
          dict[k] = v
        end
        apply_actions(Dictionary.new(dict), interpreter)
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

      def evaluate(interpreter : Interpreter) : Variant
        res, negate = @conditions[0]
        res = res.evaluate(interpreter)
        res = !res.truthy? ? TRUE : FALSE if negate
        @conditions[1..].each_with_index do |val, idx|
          cont = @continue_types[idx]
          if cont == ContinueType::And
            if res.truthy?
              res, negate = val
              res = res.evaluate(interpreter)
              res = !res.truthy? ? TRUE : FALSE if negate
            else
              break
            end
          else
            if res.truthy?
              break
            else
              res, negate = val
              res = res.evaluate(interpreter)
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
      @return_status : ::Bool = false
      @collect_array : ::Bool = false

      # def initialize(statements : ::Array(StatementNode))
      #   @statements = statements
      # end

      def initialize(body : StatementBlockNode)
        @body = body
      end

      private def capture(interpreter)
        mem = IO::Memory.new
        # @statements.each do |statement|
        #   statement.execute(interpreter, mem)
        # end
        @body.execute(interpreter, mem)
        str = mem.to_s
        str = str.chomp if @chomp
        var = String.new(str)
        apply_actions(var, interpreter)
      end

      private def capture_status(interpreter)
        res = @body.execute(interpreter, :Close, :Close)
        if res.is_a?(CommandFinish)
          status = res.status
          status ? ExitStatus.new(status) : NULL
        else
          NULL
        end
      end

      def evaluate(interpreter : Interpreter) : Variant
        unless @return_status
          capture(interpreter)
        else
          capture_status(interpreter)
        end
      end

      def dont_chomp
        @chomp = false
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
      res = @body.execute(interpreter)
      if res.is_a?(Return)
        result_value = res.value
      end
      @body.unset_variables
      result_value
    end

    macro create_proc_func
      private def create_proc(interpreter : Interpreter) : Proc(::Array(Variant), Variant?)
        case {@last_is_splat, !@optional_start_index.nil?}
        # if optional_start_index = @optional_start_index
        # if @last_is_splat
        in {true, true} # splat and optional
          optional_start_index = @optional_start_index.not_nil!
          ->(args : ::Array(Variant)) : Variant? {
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
          ->(args : ::Array(Variant)) : Variant? {
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
          ->(args : ::Array(Variant)) : Variant? {
            raise ArgumentError.new("Expected #{@argnames.size} or more arguments") if @argnames.size > args.size
            @argnames[...-1].each_with_index do |name, idx|
              @body.set_variable(name, args[idx])
            end
            @body.set_variable(@argnames[-1], Array.new(args[(@argnames.size - 1)..]))
            TMBSH::Interpreter.create_proc_func_end
          }
          # else
        in {false, false} # all args
          ->(args : ::Array(Variant)) : Variant? {
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

      def evaluate(interpreter : Interpreter) : Variant
        Function.new(create_proc(interpreter))
      end

      def constant? : ::Bool
        false
      end

      def fold : Variant?
      end

      TMBSH::Interpreter.create_proc_func
    end

    abstract class StatementNode < Node
      abstract def execute(interpreter : Interpreter,
                           output : IO | Process::Redirect = :Inherit,
                           error : IO | Process::Redirect = :Inherit) : Result

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

      private def set_env_vars_from_pairs(interpreter : Interpreter)
        @env_vars_pairs.each do |k, v|
          v = v.evaluate(interpreter)
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
        return if variant.is_a?(Null)
        if variant.is_a?(Array | Set)
          target_arr.concat(variant.to_string_array)
        elsif variant.is_a?(Dictionary)
          target_arr.concat(variant.pairs("=", "--"))
        else
          target_arr << variant.to_s
        end
      end

      private def create_str_args(interpreter : Interpreter) : ::Deque(::String)
        parts_str = ::Deque(::String).new
        if folded = @folded_parts
          first = folded[0]
          first = first.is_a?(Variant) ? first : first.evaluate(interpreter)
          if first.is_a?(Dictionary)
            first.@value.each do |k, v|
              add_env_var(k.to_s, v)
            end
          else
            append_variant(parts_str, first)
          end
          folded[1..].each do |item|
            append_variant(parts_str, item.is_a?(Variant) ? item : item.evaluate(interpreter))
          end
        else
          first = @parts[0].evaluate(interpreter)
          if first.is_a?(Dictionary)
            first.@value.each do |k, v|
              add_env_var(k.to_s, v)
            end
          else
            append_variant(parts_str, first)
          end
          @parts[1..].each do |item|
            append_variant(parts_str, item.evaluate(interpreter))
          end
        end
        parts_str
      end

      @file : ::File?

      private def get_write_file_io(interpreter : Interpreter)
        if target = @file_write_target
          @file = ::File.open(target.evaluate(interpreter).to_s, @write_to_file ? "w" : "a")
        end
      end

      private def get_read_file_io(interpreter : Interpreter)
        if target = @file_read_target
          @file = ::File.open(target.evaluate(interpreter).to_s)
        end
      end
      @builtin_result : Result?
      def create_process(
        interpreter : Interpreter,
        input_io : IO | Process::Redirect = :Inherit,
        output_io : IO | Process::Redirect = :Inherit,
        error_io : IO | Process::Redirect = :Inherit,
      ) : Process?
        set_env_vars_from_pairs(interpreter)
        args = create_str_args(interpreter)
        return if args.empty?
        command = args.shift
        if builtin = interpreter.get_builtin(command)
          # execute_builtin(builtin, args, input_io, output_io, error_io)
          builtin_input_io = if input_io.is_a?(Process::Redirect)
            case input_io
              when .inherit?
                STDIN
              # when .
            end
          else
            input_io
          end
          builtin_output_io = if output_io.is_a?(Process::Redirect)
            case output_io
              when .inherit?
                STDIN
              # when .
            end
          else
            output_io
          end
          builtin_error_io = if error_io.is_a?(Process::Redirect)
            case error_io
              when .inherit?
                STDIN
              # when .
            end
          else
            error_io
          end

          @builtin_result = builtin.call(
          interpreter, builtin_input_io, builtin_output_io, builtin_error_io, args
          )
          return
        end
        process = nil
        write_file = get_write_file_io(interpreter)
        read_file = get_read_file_io(interpreter)
        if proceed_type == ProceedType::Pipe
          if proceeding_command = @proceeding
            process = Process.new(
              command, args,
              input: read_file || input_io,
              output: write_file || Process::Redirect::Pipe,
              error: error_io,
              env: @env_vars
            )
            proceeding_command.create_process(
              interpreter, write_file ? Process::Redirect::Close : process.output, output_io
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
            env: @env_vars
          )
        end
        @attached_process = process
        process
      end

      # private def execute_builtin(
      # builtin : BuiltinCommand, args : ::Array(::String)
      # input_io, output_io, error_io
      # )
      # builtin.call(args, input_io, output_io, error_io)
      # end

      @status : Process::Status?

      def wait : Nil
        if process = @attached_process
          @status = process.wait
          @file.try &.close
          if proceeding = @proceeding
            process.output.finalize if process.output?
            proceeding.wait
          end
        else
          if proceeding = @proceeding
            proceeding.wait
          end
        end
      end

      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        process = create_process(interpreter, output_io: output, error_io: error)
        wait unless @fork_command
        # if status = @status
        #   exit_code = status.exit_code?
        # end
        if builtin_result = @builtin_result
          @builtin_result = nil
          return builtin_result
        end
        if status = @status
          # exit_code = status.exit_code?
          CommandFinish.new(status.exit_code?)
        else
          NOTHING_RESULT # TODO: maybe add some forked command result?
        end
      end
    end

    class VariableAssignmentNode < StatementNode
      @assignments : ::Array({::String, ValueNode})

      def initialize(assignments : ::Array({::String, ValueNode}))
        @assignments = assignments
      end

      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        @assignments.each do |name, value|
          interpreter.set_variable(name, value.evaluate(interpreter))
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
      @vars : ::Hash(::String, Variant) = {} of ::String => Variant

      # @auto_scope_managment = true
      # property auto_scope_managment
      def initialize
      end

      def <<(statement : StatementNode)
        @statements << statement
      end

      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        # if @auto_scope_managment
        interpreter.enter_scope
        @vars.each do |name, value|
          interpreter.shadow_variable(name, value)
        end
        # end
        res = nil
        @statements.each do |statement|
          res = statement.execute(interpreter, output, error)
          if res.is_a?(Return | Break | Continue)
            interpreter.exit_scope
            # interpreter.exit_scope if @auto_scope_managment
            return res
          end
        end
        # interpreter.exit_scope if @auto_scope_managment
        interpreter.exit_scope
        res || NOTHING_RESULT
      end

      def set_variable(name : ::String, value : Variant)
        @vars[name] = value
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
      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        BREAK_RESULT
      end

      def constant? : ::Bool
        true
      end
    end

    class ContinueStatementNode < StatementNode
      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
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

      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        Return.new(@value.try &.evaluate(interpreter))
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
      @varname : ::String?
      property varname
      @body : StatementBlockNode
      @elsif_bodies : ::Array({ConditionNode, StatementBlockNode, ::String?}) = [] of {ConditionNode, StatementBlockNode, ::String?}
      property elsif_bodies
      @else_body : StatementBlockNode?
      property else_body

      def initialize(condition : ConditionNode, body : StatementBlockNode, varname : ::String?)
        @condition = condition
        @body = body
        @varname = varname
      end

      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        condition_result = @condition.evaluate(interpreter)
        if condition_result.truthy?
          if varname = @varname
            @body.set_variable(varname, condition_result)
          end
          res = @body.execute(interpreter, output, error)
          # @body.unset_variables
          # if res.is_a?(Result | Break)
            return res
          # end
        else
          @elsif_bodies.each do |condition, block, varname|
            # p! condition, block, varname
            condition_result = condition.evaluate(interpreter)
            if condition_result.truthy?
              if varname
                block.set_variable(varname, condition_result)
              end
              res = block.execute(interpreter, output, error)
              # block.unset_variables
              # if res.is_a?(Result | Break)
                return res
              # end
              return NOTHING_RESULT
            end
          end
          if else_body = @else_body
            res = else_body.execute(interpreter, output, error)
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
      @varname : ::String?
      property varname

      def initialize(condition : ConditionNode, body : StatementBlockNode, varname : ::String? = nil)
        @body = body
        @condition = condition
        @varname = varname
      end

      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        while true
          condition = @condition.evaluate(interpreter)
          break unless condition.truthy?
          if varname = @varname
            @body.set_variable(varname, condition)
          end
          res = @body.execute(interpreter, output, error)
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
      @varnames : ::Array(::String)
      @iterable : ValueNode
      @body : StatementBlockNode

      def initialize(varnames : ::Array(::String), iterable : ValueNode, body : StatementBlockNode)
        # body.auto_scope_managment = false
        @varnames = varnames
        @iterable = iterable
        @body = body
      end

      macro execute_block
        res = @body.execute(interpreter, output, error)
        if res.is_a?(Break)
          break
        end
        if res.is_a?(Return)
          return res
        end
      end

      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        variant = @iterable.evaluate(interpreter)
        iter = variant.is_a?(Iterator) ? variant : variant.iter_init
        if @varnames.size == 1
          iter.each do |val|
            @body.set_variable(@varnames[0], val)
            TMBSH::Interpreter::ForStatementNode.execute_block
          end
        elsif @varnames.empty?
          iter.each do |val|
            TMBSH::Interpreter::ForStatementNode.execute_block
          end
        else
          iter.each do |val|
            raise "Splatting is only allowed only on Array" unless val.is_a?(Array)
            arr = val.@value
            @varnames.each_with_index do |name, i|
              @body.set_variable(name, arr[i]? || NULL)
            end
            TMBSH::Interpreter::ForStatementNode.execute_block
          end
        end
        # interpreter.enter_scope
        # if @varnames.size == 1
        #   iter.each do |val|
        #     interpreter.shadow_variable(@varnames[0], val)
        #     res = @body.execute(interpreter, output, error)
        #     if res.is_a?(Break)
        #       interpreter.exit_scope
        #       break
        #     end
        #     if res.is_a?(Return)
        #       interpreter.exit_scope
        #       return res
        #     end
        #   end
        # elsif @varnames.empty?
        #   iter.each do |val|
        #     res = @body.execute(interpreter, output, error)
        #     if res.is_a?(Break)
        #       interpreter.exit_scope
        #       break
        #     end
        #     if res.is_a?(Return)
        #       interpreter.exit_scope
        #       return res
        #     end
        #   end
        # else
        #   iter.each do |val|
        #     raise "Splatting is only allowed only on Array" unless val.is_a?(Array)
        #     arr = val.@value
        #     @varnames.each_with_index do |name, i|
        #       interpreter.shadow_variable(name, arr[i]? || NULL)
        #     end
        #     res = @body.execute(interpreter, output, error)
        #     if res.is_a?(Break)
        #       interpreter.exit_scope
        #       break
        #     end
        #     if res.is_a?(Return)
        #       interpreter.exit_scope
        #       return res
        #     end
        #   end
        # end
        # interpreter.exit_scope
        # interpreter.enter_scope
        # iter.each do |val|
        #   if @varnames.size == 1
        #     interpreter.shadow_variable(@varnames[0], val)
        #   elsif @varnames.empty?
        #   else
        #     raise "Splatting is only allowed only on Array" unless val.is_a?(Array)
        #     arr = val.@value
        #     @varnames.each_with_index do |name, i|
        #       interpreter.shadow_variable(name, arr[i]? || NULL)
        #     end
        #   end
        #   res = @body.execute(interpreter, output, false)
        #   if res.is_a?(Break)
        #     break
        #   end
        #   if res.is_a?(Return)
        #     return res
        #   end
        # end
        # interpreter.exit_scope
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

      def execute(interpreter : Interpreter,
                  output : IO | Process::Redirect = :Inherit,
                  error : IO | Process::Redirect = :Inherit) : Result
        function = Function.new(create_proc(interpreter))
        function.name = @funcname
        interpreter.shadow_variable(@funcname, function)
        NOTHING_RESULT
      end

      def constant? : ::Bool
        false
      end
    end

    class EmptyStatementNode < StatementNode
      def execute(interpreter : Interpreter,
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
      @status : Int32?
      getter status

      def initialize(status : Int32?)
        @status = status
      end
    end

    struct Nothing < Result
    end
  end
end
