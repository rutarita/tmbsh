require "./lexer/*"
require "./nodes"
require "./math_parser"
module TMBSH
  class Parser
    @lexer : Lexer

    def initialize(str : ::String)
      @lexer = StringBased.new(str)
      next_token
    end

    def initialize(io : IO)
      @lexer = IOBased.new(io)
      next_token
    end
    delegate row, to: @lexer
    delegate column, to: @lexer
    delegate token, to: @lexer
    delegate next_token, to: @lexer
    delegate next_char, to: @lexer
    delegate peek_char, to: @lexer
    class UnexpectedToken < ::Exception
    end
    private def unexpected_token(*expected)
      raise UnexpectedToken.new(
      "Unexpected token: #{token.kind} #{token.raw_value} at \
      #{row}:#{column} #{expected.size > 0 ? ::String.build { |io| io << "Expected: "; expected.each { |e| io << " '#{e}'"}} : ""}"
      )
    end

    private enum StringMode
      Plain
      SingleApostrophe
      DoubleApostrophe
    end


    def parse_value : Interpreter::ValueNode
      val = case token.kind
        when
        .string?,
        .single_apostrophe?,
        .double_apostrophe?,
        .path_separator?,
        .splat?,
        .question?,
        .exclamation?,
        .assignment_to?,
        .at?,
        .equal?,
        .greater_than_or_equal?,
        .less_than_or_equal?,
        .double_equal?
          parse_string
        when .square_bracket_open?
          parse_array
        when .curly_bracket_open?
          parse_dictionary
        when .caret?
          parse_set
        when .percent?
          parse_numerical
        when .variable_access?
          next_token
          if token.kind.parenthesis_open?
            @lexer.lex_varname = false
            parse_capture_command
          else
            parse_variable_access
          end
        when .arrow_right?
          parse_lambda
        else
          unexpected_token
      end
      actions = parse_actions
      val.add_actions actions
      val
    end

    def parse_variable_access : Interpreter::SingleValueNode
      # next_token
      if token.kind.varname?
        name = token.raw_value
        node = if var = VARIABLES_AS_LITERALS[name]?
          Interpreter::SingleValueNode.new(var)
        else
        Interpreter::SingleValueNode.new(
          Interpreter::VariableRef.new(name)
        )
        end
        next_token
        node
      elsif token.kind.curly_bracket_open?
        @lexer.lex_varname = true
        mode = @lexer.string_mode
        @lexer.string_mode = :Plain
        next_token
        unexpected_token("Varname") unless token.kind.varname?
        name = token.raw_value
        node = Interpreter::SingleValueNode.new(
          Interpreter::VariableRef.new(name)
        )
        next_token
        unless token.kind.curly_bracket_close?
          actions = parse_actions
          node.add_actions actions
        end
        @lexer.string_mode = mode
        # next_token
        skip_whitespaces_and_newlines
        unexpected_token("CurlyBracketClose") unless token.kind.curly_bracket_close?
        next_token
        node
      else
        unexpected_token("Varname", "CurlyBracketOpen")
      end
    end

    PLAIN_STRING_MODE_STOP_TOKENS = ::Set(Token::Kind).new({
      Token::Kind::Whitespace,
      Token::Kind::Newline,
      Token::Kind::EOF,
      Token::Kind::Caret,
      Token::Kind::SquareBracketOpen,
      Token::Kind::SquareBracketClose,
      Token::Kind::CurlyBracketOpen,
      Token::Kind::CurlyBracketClose,
      Token::Kind::ParenthesisOpen,
      Token::Kind::ParenthesisClose,
      Token::Kind::ArrowRight,
      Token::Kind::Pipe,
      Token::Kind::AppendToFile,
      Token::Kind::GreaterThan,
      Token::Kind::LessThan,
    })
    def parse_string : Interpreter::SingleValueNode | Interpreter::StringNode
      string_mode = StringMode::Plain
      buf = IO::Memory.new
      string_node = Interpreter::StringNode.new
      loop do
        if token.kind.single_apostrophe?
          case string_mode
            when .plain?
              string_mode = StringMode::SingleApostrophe
              next_token
              next
            when .single_apostrophe?
              string_mode = StringMode::Plain
              next_token
              next
          end
        elsif token.kind.double_apostrophe?
          case string_mode
            when .plain?
              string_mode = StringMode::DoubleApostrophe
              next_token
              next
            when .double_apostrophe?
              string_mode = StringMode::Plain
              next_token
              next
          end
        end
        # puts "current token in string parsing: #{token.inspect}"
        case string_mode
          when .plain?
            break if token.eos? || PLAIN_STRING_MODE_STOP_TOKENS.includes?(token.kind)
        end
        # puts "didn't break"
        unexpected_token if !string_mode.plain? && token.kind.eof?
        # case string_mode
          # in .plain?
        # p! token
        case token.kind
          when .string?
            str = token.to_s
            if string_node.empty? && str == "~"
              string_node.add_home
            else
            string_node.add_string(str)
            end
          when .assignment_to?
            string_node.add_string(token.to_s)
          when .equal?
            string_node.add_string("=")
          when .splat?
            # unless string_mode.plain?
              string_node.add_multiple_wildcard
            # else
              # string_node.add_string("*")
            # end
          when .question?
            # unless string_mode.plain?
            string_node.add_single_wildcard
          when .path_separator?
            string_node.add_path_separator
          when .variable_access?
            next_token
            # unexpected_token unless token.kind.varname? || token.kind
            # # p! "opegjpho"
            # var = Interpreter::SingleValueNode.new(
            #   Interpreter::VariableRef.new(token.raw_value)
            # )
            var = parse_variable_access
            string_node.add_node(var)
            next
          else
            unexpected_token
        end
          # in .
        # end

        next_token
      end
      # Interpreter::SingleValueNode.new(String.new(buf.to_s))
      if string_node.pure_string?
        string_node.to_single_value_node
      else
        string_node
      end
    end

    def parse_numerical : Interpreter::SingleValueNode | Interpreter::MathExpressionNode
      next_token
      # p! token
      case token.kind
        when .string?
          str = token.raw_value
          next_token
          prefix, octal = if str.size > 1 && str[0] == '0'
            if str[1]?.in?('b', 'x')
              {true, false}
            else
              {false, true}
            end
          else
            {false, false}
          end
          val = str.to_i64?(whitespace: true, underscore: true, prefix: prefix, leading_zero_is_octal: octal) ||
          str.to_f64?
          case val
          when Int64
            Interpreter::SingleValueNode.new(
              Int.new(val)
            )
          when Float64
            Interpreter::SingleValueNode.new(
              Float.new(val)
            )
          else
            raise UnexpectedToken.new("Invalid number at #{row}:#{column}")
          end
        when .parenthesis_open?
          e = parse_math_expression
          next_token
          e
        else
          unexpected_token
      end
    end

    def parse_array : Interpreter::ArrayValueNode
      node = Interpreter::ArrayValueNode.new
      next_token # skip open bracket
      skip_whitespaces_and_newlines
      loop do
        break if token.kind.square_bracket_close?
        val = parse_value
        node << val
        skip_whitespaces_and_newlines
      end
      next_token
      node
    end

    def parse_set : Interpreter::SetValueNode
      node = Interpreter::SetValueNode.new
      next_token
      skip_whitespaces_and_newlines
      loop do
        break if token.kind.caret?
        val = parse_value
        node << val
        skip_whitespaces_and_newlines
      end
      # p! token
      next_token
      node
    end


    def parse_dictionary : Interpreter::DictionaryValueNode
      dict = Interpreter::DictionaryValueNode.new
      next_token
      skip_whitespaces_and_newlines
      loop do
        break if token.kind.curly_bracket_close?
        key = parse_value
        skip_whitespaces_and_newlines
        if token.kind.equal?
          next_token
          skip_whitespaces_and_newlines
        end
        val = parse_value
        dict << {key, val}
        skip_whitespaces_and_newlines
      end
      next_token
      dict
    end

    def parse_lambda : Interpreter::LambdaNode
      next_token
      argnames, optional_start_index, last_is_splat = token.kind.parenthesis_open? ?
        parse_args_definition
        :
        NO_ARGUMENTS
      skip_whitespaces
      if token.kind.curly_bracket_open?
        @lexer.start_of_statement = true
        next_token
        block = parse_block(:CurlyBracketClose)
        next_token
      else
        block = Interpreter::StatementBlockNode.new
        block << Interpreter::ReturnStatementNode.new(
          parse_value
        )
      end
      Interpreter::LambdaNode.new(argnames, last_is_splat, optional_start_index, block)
    end

    def parse_capture_command : Interpreter::CaptureCommandNode
      @lexer.start_of_statement = true
      next_token
      block = parse_block(:ParenthesisClose)
      next_token
      node = Interpreter::CaptureCommandNode.new(block)
      loop do
        case token.kind
        when .question?
          node.return_status
          next_token
        when .exclamation?
          node.dont_chomp
          next_token
        when .ampersand?
          node.async
          next_token
        when .at?
          node.block_error
          next_token
        else
          break
        end
      end
      node
    end

    def parse_actions : Deque(Interpreter::Action)
      deq = Deque(Interpreter::Action).new
      loop do
        # p! token
        case token.kind
          when .square_bracket_open?
            next_token
            skip_whitespaces
            # puts "start key #{token.inspect}"
            key = parse_value
            # puts "end key"
            skip_whitespaces
            unexpected_token unless token.kind.square_bracket_close?
            next_token
            if token.kind.equal?
              next_token
              val = parse_value
              deq << Interpreter::KeyAssignment.new(key, val)
              break
              # next_token
            elsif token.kind.question?
              next_token
              deq << Interpreter::OptionalKeyAccess.new(key)
            else
              deq << Interpreter::KeyAccess.new(key)
            end
          when .arrow_right?
            next_token
            unexpected_token unless token.kind.varname?
            method_name = token.raw_value
            next_token
            if token.kind.parenthesis_open?
              args = parse_func_args
            else
              args = [] of Interpreter::ValueNode
            end
            deq << Interpreter::MethodCall.new(method_name, args)
          when .inward_arrow_right?
            next_token
            unexpected_token unless token.kind.varname?
            attribute_name = token.raw_value
            next_token
            if token.kind.equal?
              next_token
              val = parse_value
              deq << Interpreter::AttributeAssignment.new(attribute_name, val)
            else
              deq << Interpreter::AttributeAccess.new(attribute_name)
            end
          when .parenthesis_open?
            args = parse_func_args
            # p! @lexer.token
            if token.kind.ampersand?
              next_token
              deq << Interpreter::AsyncCall.new(args)
            else
              deq << Interpreter::Call.new(args)
            end
          else
          # when
          # .whitespace?,
          # .eof?,
          # .newline?,
          # .semicolon?,
          # .square_bracket_close?,
          # .curly_bracket_close?,
          # .parenthesis_close?
            break
          # else
            # unexpected_token
        end
      end
      # puts "actions finished with #{token.inspect}"
      deq
    end

    private def parse_func_args : ::Array(Interpreter::ValueNode)
      # puts "entered func args"
      next_token
      args = [] of Interpreter::ValueNode
      skip_whitespaces_and_newlines
      loop do
        break if token.kind.parenthesis_close?
        # puts "start"
        # p! token
        val = parse_value
        args << val
        # puts "end"
        # p! token
        # puts
        # p! val
        skip_whitespaces_and_newlines
      end
      # puts "broken"
      # puts "exit func args"
      next_token
      # p! token
      args
    end

    def parse_statement(*stop_at) : Interpreter::StatementNode
      p!
      skip_whitespaces_and_newlines_and_semicolons
      # p! token
      assignments = parse_assignments
      # p! assignments
      skip_whitespaces
      if token.eos?
        if assignments.empty?
          return Interpreter::EMPTY_STATEMENT_NODE
        else
          return Interpreter::VariableAssignmentNode.new(assignments)
        end
      end
      unless assignments.empty?
        command = parse_command(*stop_at)
        command.env_vars_pairs = assignments
        return command
      end
      # p! token
      case token.kind
        when .if_keyword?
          parse_if_statement
        when .while_keyword?
          parse_while_statement
        when .for_keyword?
          parse_for_statement
        when .def_keyword?
          parse_function_definition
        when .return_keyword?
          parse_return
        when .continue_keyword?
          next_token
          skip_whitespaces
          unexpected_token unless token.eos?
          Interpreter::CONTINUE_STATEMENT_NODE
        when .break_keyword?
          next_token
          skip_whitespaces
          unexpected_token unless token.eos?
          Interpreter::BREAK_STATEMENT_NODE
        else
          unless token.kind.in?(stop_at)
            parse_command(*stop_at)
          else
            Interpreter::EMPTY_STATEMENT_NODE
          end
      end
      # case token.kind
      #   when
      # end
    end

    def parse_assignments : ::Array({::String, Interpreter::ValueNode})
      assignments = [] of {::String, Interpreter::ValueNode}
      skip_whitespaces
      loop do
        # case token.kind
          # when .assignment_to?
          if token.kind.assignment_to?
            name = token.raw_value
            next_token
            val = parse_value
            assignments << {name, val}
          elsif token.kind.at?
            next_token
            val = parse_value
            assignments << {"_", val}
          else
            break
          end
          skip_whitespaces
        # end
      end
      assignments
    end

    private def parse_command_with_assignments(*stop_tokens)
      assignments = parse_assignments
      skip_whitespaces
      command = parse_command(*stop_tokens)
      command.env_vars_pairs = assignments
      command
    end

    def parse_command(*stop_tokens) : Interpreter::CommandNode
      # parts = [] of Interpreter::ValueNode
      # initial_command = Interpreter::CommandNode.new
      command = Interpreter::CommandNode.new
      # command = initial_command
      loop do
        case token.kind
          when .eos?
            break
          when .and_operator?
            next_token
            skip_whitespaces_and_newlines
            next_command = parse_command_with_assignments(*stop_tokens)
            command.fork_command = true if next_command.fork_command
            command.proceed_type = :OnSuccess
            command.proceeding = next_command
            break
          when .or_operator?
            next_token
            skip_whitespaces_and_newlines
            next_command = parse_command_with_assignments(*stop_tokens)
            command.fork_command = true if next_command.fork_command
            command.proceed_type = :OnFail
            command.proceeding = next_command
            break
          when .pipe?
            next_token
            skip_whitespaces_and_newlines
            next_command = parse_command_with_assignments(*stop_tokens)
            command.fork_command = true if next_command.fork_command
            command.proceed_type = :Pipe
            command.proceeding = next_command
            break
          when .greater_than?
            next_token
            skip_whitespaces_and_newlines
            target = parse_value
            command.file_write_target = target
          when .append_to_file?
            next_token
            skip_whitespaces_and_newlines
            target = parse_value
            command.file_write_target = target
            command.write_to_file = false
          when .less_than?
            next_token
            skip_whitespaces_and_newlines
            target = parse_value
            command.file_read_target = target
          when .ampersand?
            next_token
            skip_whitespaces
            command.fork_command = true
            raise UnexpectedToken.new("Expected end of statement after ampersand") unless token.eos? || token.kind.in?(stop_tokens)
            break
          else
            break if token.kind.in?(stop_tokens)
            command << parse_value
        end
        # break if token.eos?
        # command << parse_value
        skip_whitespaces
      end
      command
    end

    private macro get_other_value_and_call_method_on_val(method)
      next_token
      skip_whitespaces_and_newlines
      other = parse_value
      val.add_action(
        TMBSH::Interpreter::MethodCall.new({{method}}, [other] of TMBSH::Interpreter::ValueNode)
      )
    end

    def parse_condition(enclosed : ::Bool = false) : Interpreter::ConditionNode
      condition = Interpreter::ConditionNode.new
      loop do
        negated = false
        if token.kind.exclamation?
          negated = true
          next_token
        end
        val = if token.kind.parenthesis_open?
          next_token
          skip_whitespaces_and_newlines
          parse_condition(true)
        else
          parse_value
        end
        skip_whitespaces
        case token.kind
          when .double_equal?
            get_other_value_and_call_method_on_val("eq")
          when .not_equal?
            get_other_value_and_call_method_on_val("neq")
          when .greater_than?
            get_other_value_and_call_method_on_val("gt")
          when .less_than?
            get_other_value_and_call_method_on_val("lt")
          when .greater_than_or_equal?
            get_other_value_and_call_method_on_val("gte")
          when .less_than_or_equal?
            get_other_value_and_call_method_on_val("lte")
        end
        condition.add_condition(val, negated)
        case token.kind
          when .and_operator?
            next_token
            skip_whitespaces_and_newlines
            condition.add_and
          when .or_operator?
            next_token
            skip_whitespaces_and_newlines
            condition.add_or
          when .eos?
            unexpected_token if enclosed
            next_token
            break
          when .parenthesis_close?
            unexpected_token unless enclosed
            next_token
            break
          else
            unexpected_token
        end
      end
      condition
    end

    def parse_block(*stop_tokens : Token::Kind) : Interpreter::StatementBlockNode
      block = Interpreter::StatementBlockNode.new
      @lexer.start_of_statement = true
      skip_whitespaces_and_newlines_and_semicolons
      loop do
        # skip_whitespaces_and_newlines_and_semicolons
        break if token.kind.in?(stop_tokens)
        unexpected_token if token.kind.eof?
        statement = parse_statement(*stop_tokens)
        break if statement.is_a?(Interpreter::EmptyStatementNode)
        block << statement
        skip_whitespaces_and_newlines_and_semicolons

      end
      block
    end

    private def parse_condition_varname : ::String?
      varname = nil
      if token.kind.assignment_to?
        varname = token.raw_value
        next_token
      end
      varname
    end

    def parse_if_statement : Interpreter::IfStatementNode
      next_token
      skip_whitespaces_and_newlines
      varname = parse_condition_varname
      condition = parse_condition
      block = parse_block(:EndKeyword, :ElseKeyword, :ElifKeyword)
      if_statement = Interpreter::IfStatementNode.new(condition, block, varname)
      case token.kind
        when .else_keyword?
          next_token
          skip_whitespaces_and_newlines_and_semicolons
          block = parse_block(:EndKeyword)
          if_statement.else_body = block
        when .elif_keyword?
          while token.kind.elif_keyword?
            next_token
            varname = parse_condition_varname
            skip_whitespaces_and_newlines
            condition = parse_condition
            skip_whitespaces_and_newlines_and_semicolons
            block = parse_block(:EndKeyword, :ElseKeyword, :ElifKeyword)
            if_statement.elsif_bodies << {condition, block, varname}
          end
          # p! token
          if token.kind.else_keyword?
            # puts "parsing block"
            next_token
            skip_whitespaces_and_newlines_and_semicolons
            # p! token
            block = parse_block(:EndKeyword)
            # p! block
            if_statement.else_body = block
          end
      end
      next_token
      if_statement
    end

    def parse_while_statement : Interpreter::WhileStatementNode
      next_token
      skip_whitespaces_and_newlines
      varname = parse_condition_varname
      condition = parse_condition
      block = parse_block(:EndKeyword)
      next_token
      Interpreter::WhileStatementNode.new(condition, block, varname)
    end

    def parse_for_statement : Interpreter::ForStatementNode
      next_token
      varnames = [] of ::String
      loop do
        skip_whitespaces_and_newlines
        # p! token
        break if token.kind.in_keyword?
        varnames << token.raw_value
        next_token
      end
      next_token
      skip_whitespaces_and_newlines
      val = parse_value
      block = parse_block(:EndKeyword)
      next_token
      Interpreter::ForStatementNode.new(varnames, val, block)
    end
    NO_ARGUMENTS = {[] of ::String, nil, false}
    private def parse_args_definition : {::Array(::String), Int32?, ::Bool}
      last_is_splat = false
      optional_start_index = nil
      argnames = [] of ::String
      @lexer.lex_argnames = true
      next_token
      # @lexer.lex_varname = true
      skip_whitespaces_and_newlines
      loop do
        unexpected_token("ParenthesisClose") if last_is_splat && !token.kind.parenthesis_close?
        break if token.kind.parenthesis_close?
        if token.kind.splat?
          last_is_splat = true
          next_token
        end
        unexpected_token("Varname") unless token.kind.varname?
        argname = token.raw_value
        if argname[-1] == '?'
          unless optional_start_index
            optional_start_index = argnames.size
          end
          argname = argname[0...-1]
        else
          raise "Expected variable to be optional" if optional_start_index
        end
        next_token
        # if optional_start_index
        #   unexpected_token("Question") unless token.kind.question?
        #   next_token
        # else
        #   if token.kind.question?
        #     optional_start_index = argnames.size
        #     next_token
        #   end
        # end
        argnames << argname
        skip_whitespaces_and_newlines
        # @lexer.lex_varname = true
      end
      @lexer.lex_argnames = false
      next_token
      {argnames, optional_start_index, last_is_splat}
    end

    def parse_function_definition : Interpreter::FunctionDefinitionNode
      next_token
      @lexer.lex_varname = true
      skip_whitespaces_and_newlines
      @lexer.lex_varname = false
      # next_token
      unexpected_token unless token.kind.varname?
      funcname = token.raw_value
      next_token
      argnames, optional_start_index, last_is_splat = token.kind.parenthesis_open? ?
        parse_args_definition
      :
        NO_ARGUMENTS
      block = parse_block(:EndKeyword)
      next_token
      Interpreter::FunctionDefinitionNode.new(funcname, argnames, optional_start_index, last_is_splat, block)
    end

    def parse_return : Interpreter::ReturnStatementNode
      next_token
      skip_whitespaces
      node = if token.eos?
        Interpreter::NOTHING_RETURN_STATEMENT_NODE
      else
        Interpreter::ReturnStatementNode.new(parse_value)
      end
      unexpected_token unless token.eos? || token.kind.curly_bracket_close?
      node
    end

    private def skip_whitespaces
      return unless token.kind.whitespace?
      loop do
        break unless token.kind.whitespace?
        next_token
      end
    end

    private def skip_whitespaces_and_newlines
      return unless token.kind.whitespace? || token.kind.newline?
      loop do
        break unless token.kind.whitespace? || token.kind.newline?
        next_token
      end
    end

    private def skip_whitespaces_and_newlines_and_semicolons
      return unless token.kind.whitespace? || token.kind.newline? || token.kind.semicolon?
      loop do
        break unless token.kind.whitespace? || token.kind.newline? || token.kind.semicolon?
        next_token
      end
    end

    # def find_next_stra

    private def unexpected_node(node, expected)
      raise UnexpectedNode.new("Unexpected node: #{node.class.to_s.lchop("TMBSH::Interpreter")}, expected: #{expected}")
    end

    class UnexpectedNode < ::Exception
    end

  end


end
