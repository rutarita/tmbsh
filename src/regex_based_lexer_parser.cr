require "./nodes"
require "string_scanner"

module TMBSH
  module RegexBasedLexerParser
    extend self
    COMMENT_CHAR = '#'

    VARNAME_REGEX = /[a-zA-Z0-9_]+|\?\??/

    private def is_end_of_statement(scanner : StringScanner)
      (scanner.current_char? == ';' && scanner.previous_char? != '\\') || scanner.current_char? == '\n' || scanner.eos?
    end

    ESCAPED_CHARS = {
      ' '  => ' ',
      't'  => '\t',
      'r'  => '\r',
      'n'  => '\n',
      '0'  => '\0',
      '%'  => '%',
      '\\' => '\\',
      ';'  => ';',
      '-'  => '-',
      '\n' => '\0',
      '#'  => '#',
    }

    DEFAULT_STRING_REGEX = /\\|;|\s|\$|'|"|\*|\?/

    DELIMER_REGEX_RULES = {
      '\'' => /\\|'/,
      '"'  => /\\|\$|"/,
    }

    def parse_string(scanner : StringScanner, stop_at : ::Char? = nil) : StringNode | SingleValueNode
      # start_offset = scanner.offset
      current_delimer = ' '
      default_regex = /(\\|\(|\[|;|\s|#|\$|'|->|"|\/|\*|\?#{stop_at ? "|" + Regex.escape(stop_at.to_s) : ""})/
      regex = default_regex
      node = StringNode.new
      if scanner.scan(/~(?=\/|\s|;|$|-)/)
        node.add_home
      end
      while true
        read = scanner.scan_until(regex)
        unless read
          read = scanner.scan(/.+/)
          if read
            node.add_string(read)
          end
          break
        end
        if read.empty?
          break
        end
        # p! scanner[0]
        char = read[-1]
        case char
        when '$'
          if scanner.scan('{')
            node.add_string(read[...-1])
            value = parse_value(scanner, '}')
            node.add(value)
            raise "Expected closign } and not end" unless scanner.scan(/\h*\}/)
          else
            node.add_string(read[...-1])
            varname = scanner.scan(VARNAME_REGEX)
            raise "Expected variable name after $" unless varname
            ref = VariableRef.new(varname)
            node.add(SingleValueNode.new(ref))
          end
        when '\\'
          sym = scanner.current_char
          scanner.skip(1)
          sym_escaped = ESCAPED_CHARS[sym]? || sym
          read = read[...-1] + sym_escaped if sym != '\0'
          node.add_string(read[...-1] + sym_escaped)
        when '"', '\''
          if current_delimer == ' '
            regex = DELIMER_REGEX_RULES[char]
            current_delimer = char
          else
            regex = default_regex
            current_delimer = ' '
          end
          node.add_string(read[...-1])
        when '*'
          node.add_string(read[...-1])
          node.add_multiple_wildcard
        when '?'
          node.add_string(read[...-1])
          node.add_single_wildcard
        when '/'
          node.add_string(read[...-1])
          node.add_path_separator
        when '>'
          node.add_string(read[...-2])
          scanner.rewind(2)
          break
        when '#', ';', '(', '[', stop_at
          node.add_string(read[...-1])
          scanner.rewind(1)
          break
        end
        if char.whitespace?
          scanner.rewind(1)
          node.add_string(read[0...-1])
          break
        end
      end
      if node.pure_string?
        node.to_single_value_node
      else
        node
      end
    end

    SKIP_TO_CONTENTS_REGEX = /(?:;|\s|\\\n)*/

    def parse_multiple_value(scanner : StringScanner, stop_at : ::Char? = nil) : ::Array(ValueNode)
      values = [] of ValueNode
      return values if stop_at && scanner.scan(stop_at)
      while true
        val = parse_value(scanner, stop_at)
        break if val == NULL
        scanner.skip(/\s*/)
        values << val
        scanner.skip(/\s*/)
        break if scanner.scan(stop_at)
        if is_end_of_statement(scanner)
          raise "Expected closing #{stop_at} not end of statement"
        end
      end
      values
    end

    def parse_array(scanner : StringScanner) : ArrayValueNode
      raise "Not a beginning of an Array" unless scanner.scan('[')
      array_node = ArrayValueNode.new
      return array_node if scanner.scan(/\s*\]/)
      while true
        scanner.skip(/\s*/)
        array_node << parse_value(scanner, ']')
        break if scanner.scan(/\s*\]/)
        raise "Expected closing ']' not end of statement" if is_end_of_statement(scanner)
      end
      array_node
    end

    def parse_dictionary(scanner : StringScanner) : DictionaryValueNode
      raise "Not a beginning of a Dictionary" unless scanner.scan('{')
      dict = DictionaryValueNode.new
      return dict if scanner.scan(/\s*\}/)
      while true
        k = parse_value(scanner, '}')
        raise "Expected value or ':' and not the end" if scanner.scan('}') || is_end_of_statement(scanner)
        scanner.scan(/\s*(:\s+)?/)
        v = parse_value(scanner, '}')
        dict << {k, v}
        scanner.scan(/\s+/)
        raise "Expected closing '}' not end of statement" if is_end_of_statement(scanner)
        break if scanner.scan('}')
      end
      dict
    end

    def parse_set(scanner : StringScanner, stop_at : ::Char? = nil) : SetValueNode
      items = parse_multiple_value(scanner, stop_at)
      SetValueNode.new(items)
    end

    def parse_variable(scanner : StringScanner) : SingleValueNode
      raise "Expected $" unless scanner.scan('$')
      varname = scanner.scan(VARNAME_REGEX)
      raise "Expected variable name after $" unless varname
      SingleValueNode.new(VariableRef.new(varname))
    end

    def parse_numerical_expression(scanner : StringScanner) : SingleValueNode
      raise "Expected %" unless scanner.scan('%')
      if scanner.scan('(')
        raise "to do :,)"
      elsif scanner.scan(/(-?[0-9]+)?\.\.(\.)?(-?[0-9]+)?/)
        first_num = scanner[1]?.try &.to_i64
        is_exclusive = !!scanner[2]?
        last_num = scanner[3]?.try &.to_i64
        var = Range.new(first_num, last_num, is_exclusive)
      elsif num = scanner.scan(/-?(0([bx]?))?([0-9A-Fa-f]+(\.[0-9]+)?)/)
        base = 10
        if scanner[1]?
          base = case scanner[2]?
            when "b" then 2
            when "x" then 16
            else 8
          end
        end
        if scanner[4]?
          raise "Can't specify base on floats" unless base == 10
          var = Float.new(scanner[3].to_f64)
        else
          var = Int.new(scanner[3].to_i64(base))
        end
      else
        raise "NumberParser: Error parsing"
      end
      SingleValueNode.new(var)
    end

    def parse_value(scanner : StringScanner, stop_at : ::Char? = nil) : ValueNode
      scanner.skip(SKIP_TO_CONTENTS_REGEX)
      return SingleValueNode.new(NULL) if scanner.scan(/#.*/)
      value_node = nil
      return SingleValueNode.new(NULL) if is_end_of_statement(scanner)
      case scanner.current_char
      when '['
        value_node = parse_array(scanner)
      when '{'
        value_node = parse_dictionary(scanner)
      when '^', '`'
        scanner.skip(1)
        value_node = parse_set(scanner, scanner.current_char)
      when '%'
        value_node = parse_numerical_expression(scanner)
      when '$'
        if scanner.scan("$(")
          value_node = parse_capture_command(scanner)
        else
          value_node = parse_variable(scanner)
        end
      when '-'
        if scanner.scan("->")
          value_node = parse_lambda(scanner, stop_at)
        else
          value_node = parse_string(scanner, stop_at)
        end
      else
        value_node = parse_string(scanner, stop_at)
      end
      return value_node if scanner.scan(SKIP_COMMENT)
      if stop_at
        return value_node if scanner.check(stop_at)
      end
      while true
        if scanner.scan("->")
          attribute_name = scanner.scan(/[a-zA-Z_][a-zA-Z0-9_!?]*/)
          raise "Expected attribute name" unless attribute_name
          if scanner.scan('(')
            args = parse_multiple_value(scanner, ')')
            value_node.add_action MethodCall.new(attribute_name, args)
          else
            value_node.add_action MethodCall.new(attribute_name, [] of ValueNode)
          end
        elsif scanner.scan('[')
          key = parse_value(scanner, ']')
          raise "Expected ']'" unless scanner.scan(/\s*\]/)
          if scanner.scan('=')
            new_val = parse_value(scanner)
            value_node.add_action KeyAssignment.new(key, new_val)
          elsif scanner.scan('?')
            value_node.add_action OptionalKeyAccess.new(key)
          else
            value_node.add_action KeyAccess.new(key)
          end
        elsif scanner.scan('(')
          args = parse_multiple_value(scanner, ')')
          value_node.add_action Call.new(args)
        else
          break
        end
      end
      value_node
    end

    def parse_assignments(scanner : StringScanner, stop_at : ::Char? = nil) : ::Array({::String, ValueNode})
      scanner.skip(SKIP_TO_CONTENTS_REGEX)
      assigned = [] of {::String, ValueNode}
      while scanner.scan(/(?:([a-zA-Z0-9_?]+)=)|@/)
        var_name = scanner[1]? || "_"
        value = parse_value(scanner, stop_at)
        assigned << {var_name, value}
        scanner.skip(/\h+/)
      end
      assigned
    end

    def parse_condition(scanner : StringScanner, stop_at : ::Char? = nil) : ConditionNode
      scanner.skip(SKIP_TO_CONTENTS_REGEX)
      node = ConditionNode.new
      while true
        negate = false
        negate = true if scanner.scan('!')
        scanner.skip(/\h*/)
        raise "Expected value not end of statement" if is_end_of_statement(scanner)
        val = parse_value(scanner, stop_at)
        node.add_condition(val, negate)
        scanner.skip(/\s*/)
        if scanner.scan(/(\|\||&&)/)
          if scanner[1] == "||"
            node.add_or
          else
            node.add_and
          end
        else
          break
        end
      end
      node
    end

    private def parse_varname_condition(scanner : StringScanner, stop_at : ::Char? = nil) : {::String?, ConditionNode}
      scanner.skip(/\h*/)
      varname = nil
      if scanner.scan(/([a-zA-Z0-9_]+)=/)
        varname = scanner[1]
      end
      condition = parse_condition(scanner, stop_at)
      {varname, condition}
    end

    private def parse_if_block(scanner : StringScanner, stop_at : ::Char? = nil) : {StatementBlockNode, ::String}
      block = StatementBlockNode.new
      while true
        scanner.skip(SKIP_TO_CONTENTS_REGEX)
        if scanner.scan(/\h*(elsif|elif|else|end)/)
          return {block, scanner[1]}
        end
        block << parse_statement(scanner, stop_at)
        raise "Expected end, elsif, elif, else and not literal end" if scanner.eos?
      end
    end

    def parse_if_statement(scanner : StringScanner, stop_at : ::Char? = nil) : IfStatementNode
      varname, condition = parse_varname_condition(scanner, stop_at)
      first_block, closing = parse_if_block(scanner, stop_at)
      if_statement = IfStatementNode.new(condition, first_block)
      if_statement.varname = varname
      return if_statement if closing == "end"
      if closing == "else"
        block, closing = parse_if_block(scanner, stop_at)
        if_statement.else_body = block
        raise "Expected 'end' not #{closing}" unless closing == "end"
        return if_statement
      end
      while true
        varname, condition = parse_varname_condition(scanner, stop_at)
        block, closing = parse_if_block(scanner, stop_at)
        if_statement.elsif_blocks << {condition, block, varname}
        if closing == "else"
          block, closing = parse_if_block(scanner, stop_at)
          if_statement.else_body = block
          raise "Expected 'end' not #{closing}" unless closing == "end"
          return if_statement
        end
        if closing == "end"
          return if_statement
        end
      end
    end

    private def parse_block_until_end(scanner : StringScanner, stop_at : ::Char? = nil) : StatementBlockNode
      block = StatementBlockNode.new
      while true
        scanner.skip(SKIP_TO_CONTENTS_REGEX)
        if scanner.scan(/end(?![a-zA-Z0-9])/)
          return block
        end
        block << parse_statement(scanner, stop_at)
        raise "Expected end end" if scanner.eos?
      end
      block
    end

    def parse_while_statement(scanner : StringScanner, stop_at : ::Char? = nil) : WhileStatementNode
      varname, condition = parse_varname_condition(scanner, stop_at)
      block = parse_block_until_end(scanner, stop_at)
      WhileStatementNode.new(condition, block, varname)
    end

    def parse_for_statement(scanner : StringScanner, stop_at : ::Char? = nil) : ForStatementNode
      scanner.skip(/\s*/)
      varnames = [] of ::String
      while true
        scanner.skip(/\s/)
        break if scanner.scan(/in(?=\s)/)
        if varname = scanner.scan(VARNAME_REGEX)
          varnames << varname
        else
          raise "Expected varname"
        end
      end
      # raise "Expected var name" unless varname
      # raise "Expected 'in'" unless scanner.scan(/\s*in\s*/)
      iterable = parse_value(scanner, stop_at)
      block = parse_block_until_end(scanner, stop_at)
      ForStatementNode.new(varnames, iterable, block)
    end

    def parse_capture_command(scanner : StringScanner, stop_at : ::Char? = nil) : CaptureCommandNode
      statements = [] of StatementNode
      while true
        scanner.skip(SKIP_TO_CONTENTS_REGEX)
        break if scanner.scan(')')
        node = parse_statement(scanner, ')')
        statements << node
      end
      CaptureCommandNode.new(statements)
    end

    private def parse_argnames(scanner : StringScanner, stop_at : ::Char? = nil) : {::Array(::String), ::Bool, ::Int32 | Nil}
      argnames = [] of ::String
      last_is_splat = false
      optional_start_index = nil
      if scanner.scan('(')
        while true
          scanner.skip(/\s*/)
          break if scanner.scan(')')
          unless scanner.scan('*')
            argname = scanner.scan(VARNAME_REGEX)
            raise "Expected var name" unless argname
            argnames << argname
            if optional_start_index
              raise "Expected every argument after first opional one to be optional" unless scanner.scan('?')
            elsif scanner.scan('?')
              optional_start_index = argnames.size - 1
            end
          else
            last_is_splat = true
            argname = scanner.scan(VARNAME_REGEX)
            if optional_start_index
              raise "Expected every argument after first opional one to be optional" unless scanner.scan('?')
            elsif scanner.scan('?')
              optional_start_index = argnames.size - 1
            end
            raise "Expected var name" unless argname
            argnames << argname
            raise "Expected closing ) after only allowed paranthesis" unless scanner.scan(/\s*\)/)
            break
          end
        end
      end
      {argnames, last_is_splat, optional_start_index}
    end

    def parse_function_definition(scanner : StringScanner, stop_at : ::Char? = nil) : FunctionDefinitionNode
      scanner.skip(/\s*/)
      funcname = scanner.scan(VARNAME_REGEX)
      raise "Expected function name" unless funcname
      argnames, last_is_splat, optional_start_index = parse_argnames(scanner, stop_at)
      block = parse_block_until_end(scanner, stop_at)
      FunctionDefinitionNode.new(funcname, argnames, optional_start_index, last_is_splat, block)
    end

    private def parse_lambda_block(scanner : StringScanner, stop_at : ::Char? = nil)
      block = StatementBlockNode.new
      while true
        scanner.skip(SKIP_TO_CONTENTS_REGEX)
        if scanner.scan('}')
          return block
        end
        block << parse_statement(scanner, '}')
        raise "Expected closing }" if scanner.eos?
      end
      block
    end

    def parse_lambda(scanner : StringScanner, stop_at : ::Char? = nil)
      argnames, last_is_splat, optional_start_index = parse_argnames(scanner, stop_at)
      scanner.skip(/\h*/)
      if scanner.scan('{')
        block = parse_lambda_block(scanner, stop_at)
      else
        block = StatementBlockNode.new
        value = parse_value(scanner, stop_at)
        statement = ReturnStatementNode.new(value)
        block << statement
      end
      LambdaNode.new(argnames, last_is_splat, optional_start_index, block)
    end

    KEYWORDS_REGEX = /(for(?=\h)|while(?=\h)|if(?=\h)|def(?=\h)|return|break|continue)/
    SKIP_COMMENT   = /\h*#.*\n/

    def parse_statement(scanner : StringScanner, stop_at : ::Char? = nil) : StatementNode
      scanner.skip(SKIP_TO_CONTENTS_REGEX)
      if scanner.scan(SKIP_COMMENT)
        return EmptyStatementNode.new
      end
      assigned = parse_assignments(scanner, stop_at)
      if is_end_of_statement(scanner) || scanner.scan(SKIP_COMMENT)
        return VariableAssignmentNode.new(assigned)
      end
      statement_end_regex = /\h*(?:\n|;#{stop_at ? "|" + Regex.escape(stop_at.to_s) : ""})/
      if scanner.scan(KEYWORDS_REGEX)
        case scanner[1]
        when "if"
          return parse_if_statement(scanner, stop_at)
        when "while"
          return parse_while_statement(scanner, stop_at)
        when "for"
          return parse_for_statement(scanner, stop_at)
        when "def"
          return parse_function_definition(scanner, stop_at)
        when "break"
          raise "Expected end of statement after break" unless scanner.check(statement_end_regex)
          return BREAK_STATEMENT_NODE
        when "continue"
          raise "Expected end of statement after continue" unless scanner.check(statement_end_regex)
          return CONTINUE_STATEMENT_NODE
        when "return"
          scanner.skip(/\h*/)
          if is_end_of_statement(scanner)
            return ReturnStatementNode.new
          else
            val = parse_value(scanner, stop_at)
            raise "Expected end of statement after return" unless scanner.check(statement_end_regex)
            return ReturnStatementNode.new(val)
          end
        end
        raise "to do brah"
      else
        command = parse_command(scanner, stop_at)
        command.env_vars_pairs = assigned
        command
      end
    end

    PROCEED_REGEX = /(?:(?:\||>|>>|<|&&|\|\|)(?=\h))|(&)(?!&)/

    def parse_command(scanner : StringScanner, stop_at : ::Char? = nil) : CommandNode
      proceed_type = nil
      node = CommandNode.new
      while true
        scanner.skip(SKIP_TO_CONTENTS_REGEX)
        if res = scanner.scan(PROCEED_REGEX)
          proceed_type = res
          if proceed_type == ">>" || proceed_type == ">"
            node.write_to_file = proceed_type == ">"
            target = parse_value(scanner, stop_at)
            node.file_write_target = target
            next
          elsif proceed_type == "<"
            target = parse_value(scanner, stop_at)
            node.file_read_target = target
          else
            break
          end
        end
        node << parse_value(scanner, stop_at)
        break if scanner.check(')')
        break if scanner.check(stop_at) if stop_at
        break if is_end_of_statement(scanner)
      end
      # p! proceed_type
      case proceed_type
      when "|"
        node.proceed_type = CommandNode::ProceedType::Pipe
        proceeding_command = parse_command(scanner, stop_at)
        node.proceeding = proceeding_command
      when "||"
        node.proceed_type = CommandNode::ProceedType::OnFail
        proceeding_command = parse_command(scanner, stop_at)
        node.proceeding = proceeding_command
      when "&&"
        node.proceed_type = CommandNode::ProceedType::OnSuccess
        proceeding_command = parse_command(scanner, stop_at)
        node.proceeding = proceeding_command
      end
      node
    end
  end
end
