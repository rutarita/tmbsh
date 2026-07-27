require "./token"

module TMBSH
  abstract class Lexer
    @row : Int32 = 1
    @column : Int32 = 1
    getter row
    getter column
    @token : Token = Token.new
    getter token
    getter current_char : Char = '\0'
    # @current_string_delimiter : Char = '\0'
    @start_of_statement : ::Bool = true

    private def start_statement
      if @string_mode.plain?
        @start_of_statement = false
      end
    end

    private def end_statement
      if @string_mode.plain?
        @start_of_statement = true
        @lex_assignments = true
      end
    end

    private abstract def next_char_no_column_increment : Char

    # private def advance_position
    #   if @current_char == '\n'
    #     @column = 1
    #     @row += 1
    #   end
    #   @column += 1
    # end

    def next_char : Char
      if @current_char == '\n'
        @column = 1
        @row += 1
      end
      @current_char = next_char_no_column_increment
      @column += 1 unless @current_char == '\0'
      @current_char
    end

    def next_char(kind : Token::Kind)
      token.raw_value = ""
      token.kind = kind
      next_char
    end

    private abstract def peek_char : Char

    private def next_char_string_or(token : Token::Kind)
      if @string_mode.plain?
        next_char token
        # elsif @lex_varname
        # next_varname
      else
        # str = current_char.to_s
        str = consume_string
        # next_char Token::Kind::String
        @token.kind = :String
        @token.raw_value = str
      end
    end

    private def next_char_string_or_varname_or(token : Token::Kind)
      if @lex_varname
        char = current_char
        next_char :Varname
        @token.raw_value = char.to_s
        @token.kind = :Varname
      else# str = current_char.to_s
        next_char_string_or token
      end
    end

    @after_for : ::Bool = false
    @lex_for_varnames : ::Bool = false
    @lex_varname : ::Bool = false
    property lex_varname
    @lex_assignments : ::Bool = true
    property lex_assignments
    @lexing_assignment_value : ::Bool = false
    @lex_argnames : ::Bool = false
    property lex_argnames
    def next_token : Token
      # p! "#{@lex_for_varnames} #{token}"
      # skip_whitespace
      skip_comment
      # p! @string_mode
      @token.row = @row
      @token.column = @column
      char = current_char
      case char
      when '\''
        start_statement
        @string_mode = @string_mode.single_apostrophe? ? StringMode::Plain : StringMode::SingleApostrophe
        next_char :SingleApostrophe
      when '"'
        start_statement
        @string_mode = @string_mode.double_apostrophe? ? StringMode::Plain : StringMode::DoubleApostrophe
        next_char :DoubleApostrophe
      when '['
        start_statement
        next_char_string_or :SquareBracketOpen
      when ']'
        start_statement
        next_char_string_or :SquareBracketClose
      when '('
        start_statement
        next_char_string_or :ParenthesisOpen
      when ')'
        start_statement
        next_char_string_or :ParenthesisClose
      when '{'
        start_statement
        next_char_string_or :CurlyBracketOpen
      when '}'
        start_statement
        next_char_string_or :CurlyBracketClose
      when ';'
        end_statement
        next_char_string_or :Semicolon
      when '@'
        end_statement
        next_char_string_or_varname_or :At
      when '^'
        start_statement
        next_char_string_or :Caret
      when '$'
        start_statement
        if @string_mode.single_apostrophe?
          str = consume_string
          next_char :String
          @token.raw_value = str
        else
          @lex_varname = true
          next_char :VariableAccess
        end
      when '/'
        start_statement
        next_char :PathSeparator
      when '*'
        start_statement
        next_char_string_or_varname_or :Splat
      when '?'
        start_statement
        next_char_string_or_varname_or :Question
      when '!'
        start_statement
        next_char_string_or_varname_or :Exclamation
      when '&'
        start_statement
        if peek_char == '&'
          if @string_mode.plain?
            next_char
            next_char :AndOperator
          else
            next_char
            next_char
            @token.kind = :String
            @token.raw_value = "&&"
          end
        else
          next_char_string_or :Ampersand
        end
      when '|'
        start_statement
        if peek_char == '|'
          if @string_mode.plain?
            next_char
            next_char :OrOperator
          else
            next_char
            next_char
            @token.kind = :String
            @token.raw_value = "||"
          end
        else
          next_char_string_or :Pipe
        end
      when '%'
        start_statement
        next_char_string_or :Percent
      when '>'
        start_statement
        if peek_char == '>'
          if @string_mode.plain?
            next_char
            next_char :AppendToFile
          else
            next_char
            next_char
            @token.kind = :String
            @token.raw_value = ">>"
          end
        else
          next_char_string_or :WriteToFile
        end
      when '<'
        start_statement
        if peek_char == '<'
          if @string_mode.plain?
            next_char
            next_char :HeredocBegin
          else
            next_char
            next_char
            @token.kind = :String
            @token.raw_value = "<<"
          end
        else
          next_char_string_or :ReadFromFile
        end
      when '='
        start_statement
        next_char_string_or :Equal
      when ' ', '\t'
        # next_char :Whitespace
        if @string_mode.plain?
          str = skip_whitespace
          @token.kind = :Whitespace
          @token.raw_value = str
        else
          start_statement
          str = skip_whitespace
          @token.raw_value = str
          @token.kind = :String
        end
      when '\\'
        if peek_char == '\n'
          next_char
          next_char
          str = skip_whitespace
          @token.kind = :Whitespace
          @token.raw_value = str
        else
          str = consume_string
          @token.kind = :String
          @token.raw_value = str
        end
      when '\n'
        end_statement
        next_char_string_or :Newline
        # skip_whitespace
        # str = skip_whitespace
        # @token.raw_value = str
      when '-'
        start_statement
        if peek_char == '>'
          if @string_mode.plain?
            @lex_varname = true
            next_char
            next_char :ArrowRight
          else
            next_char
            next_char
            @token.kind = :String
            @token.raw_value = "->"
          end
        else
          next_char :String
          @token.raw_value = "-"
        end
      when '\0'
        token.kind = :EOF
      else
        # @token.kind = :String
        # p! @lex_argnames
        if @lex_varname || @lex_for_varnames || @lex_argnames
          next_varname
        else
          str = consume_string
          if current_char.in?(' ', '\n', ';', '\0')
            if @start_of_statement && str.size <= LONGEST_KEYWORD_LENGTH
              if kind = KEYWORDS[str]?
                @token.kind = kind
                if kind.for_keyword?
                  # @after_for = true
                  # puts "WHT THE FU"
                  @lex_for_varnames = true
                elsif kind.def_keyword?
                  @lex_varname = true
                end
              else
                @token.kind = :String
                @token.raw_value = str
              end
            else
              @token.raw_value = str
              @token.kind = :String
            end
          else
          # elsif current_char == '='
            # next_char :String
            if current_char == '=' # current workaround i suppose
            # if @lex_assignments && current_char == '='
              next_char
              @token.raw_value = str
              @token.kind = :AssignmentTo
              @lexing_assignment_value = true
            else
              @token.raw_value = str
              @token.kind = :String
            end
          end
        end
        start_statement
      end
      skip_comment if @string_mode.plain?
      @lex_varname = false unless token.kind.variable_access? || token.kind.arrow_right?
      # @lex_assignments = false unless token.kind.assignment_to?
      # make sure it finishes lexing tokens as varnames unless we just announced that it should do it
      @token
    end

    KEYWORDS = {
      "def"    => :DefKeyword,
      "if"     => :IfKeyword,
      "else"   => :ElseKeyword,
      "elsif"  => :ElifKeyword,
      "elif"   => :ElifKeyword,
      "for"    => :ForKeyword,
      "while"  => :WhileKeyword,
      "return" => :ReturnKeyword,
      "continue" => :ContinueKeyword,
      "next"    => :ContinueKeyword,
      "break"  => :BreakKeyword,
      "end"    => :EndKeyword,
    } of ::String => Token::Kind

    LONGEST_KEYWORD_LENGTH = 8


    private enum StringMode
      Plain
      SingleApostrophe
      DoubleApostrophe
      # maybe raw next?
      # def escape_char?(char : Char)
      #   case self
      #     in .plain?
      #       char.in?(' ', '\t', ';', '$', '<', '>', '|', '[', '?', '*')
      #     in .single_apostrophe?
      #       char == '\''
      #     in .double_apostrophe?
      #       char.in?('"', '$')
      #   end
      # end
    end
    @string_mode : StringMode = :Plain

    private def resolve_escaped(char : Char) : Char
      case char
      when 'n'
        '\n'
      when 't'
        '\t'
      when 'r'
        '\r'
      when '\n'
        '\0'
      else
        char
      end
    end

    PLAIN_MODE_STOP_CHARACTERS_SET = ::Set(Char).new({
    ' ', '\t', '\n', ';', '$', '<', '>', '|', '(', ')', '[', ']', '{', '}', '?', '*', '\0', '"', '\'', '/', '=', '#', '^'
    })
    # @@string_stop_characters_set = Set(Char).new({})
    DOUBLE_APOSTROPHE_MODE_STOP_CHARACTERS_SET = ::Set(Char).new({'$', '/'})
    SINGLE_APOSTROPHE_MODE_STOP_CHARACTERS_SET = ::Set(Char).new({'/'})

    private def consume_string : ::String
      buffer = IO::Memory.new
      buffer << current_char
      escaped = false
      loop do
        # p! buffer.to_s
        # if string_mode.escape_char?(peek_char)
        #   break
        # end
        # if @@string_stop_characters_set.includes?(peek_char)
        #   break
        # end
        char = next_char
        # p! char, @string_mode
        case @string_mode
        when .plain?
          break if PLAIN_MODE_STOP_CHARACTERS_SET.includes?(char)
        when .double_apostrophe?
          break if DOUBLE_APOSTROPHE_MODE_STOP_CHARACTERS_SET.includes?(char)
        when .single_apostrophe?
          break if SINGLE_APOSTROPHE_MODE_STOP_CHARACTERS_SET.includes?(char)
        end
        # if PLAIN_MODE_STOP_CHARACTERS_SET.includes?(char)
        #   break
        # end
        if char == '\0'
          unexpected_char
        end
        if char == '-' && peek_char == '>'
          break
        end
        if escaped
          unexpected_char if char == '\0'
          escaped_char = resolve_escaped(char)
          buffer << escaped_char unless escaped_char == '\0'
          escaped = false
          # next_char
          next
        elsif char == '\\'
          break if @string_mode.plain? && peek_char == '\n'
          escaped = true
          next
        end
        case @string_mode
        in .plain?
          if char == '\''
            # @string_mode = :SingleApostrophe
            break
          elsif char == '"'
            # @string_mode = :DoubleApostrophe
            break
          end
        in .single_apostrophe?
          if char == '\''
            # @string_mode = :Plain
            break
          end
        in .double_apostrophe?
          if char == '"'
            # @string_mode = :Plain
            break
          end
        end
        # if !@string_mode.plain? && char == '#'
        #   skip_comment
        #   break
        # end
        buffer << char
      end
      buffer.to_s
    end

    private def valid_varname_char(char)
      ('0'..'9').includes?(char) ||
        ('a'..'z').includes?(char) ||
        ('A'..'Z').includes?(char) || char == '_'
    end

    def next_varname : Token
      str = consume_varname
      if @lex_for_varnames && str == "in"
        @token.kind = :InKeyword
        # @after_for = false
        @lex_for_varnames = false
      else
        @token.raw_value = str
        @token.kind = :Varname
      end
      @token
    end

    private def consume_varname : ::String
      buf = IO::Memory.new
      if current_char.in?('*', '?')
        buf << current_char
        next_char
        return buf.to_s
      end
      while true
        if valid_varname_char(current_char)
          buf << current_char
        elsif current_char == '?'
          buf << current_char
          next_char
          break
        else
          break
        end
        next_char
      end
      # next_char
      buf.to_s
    end

    private def skip_comment
      # raise "Skip triggered #{@string_mode}"
      # p! @string_mode
      return unless current_char == '#'
      while char = next_char
        break if char == '\n' || char == '\0'
      end
      # next_char
    end

    private def skip_whitespace : ::String
      return "" unless current_char == ' ' || current_char == '\t'
      mem = IO::Memory.new
      mem << current_char
      while char = next_char
        break unless char == ' ' || char == '\t' || (char == '\\' && peek_char == '\n')
        if char == '\\'
          next_char
          # next_char
        else
        mem << char
        end
      end
      mem.to_s
    end

    class UnexpectedCharacterException < ::Exception
    end

    private def unexpected_char
      raise UnexpectedCharacterException.new("Unexpected character at #{@row}, #{@column}: #{current_char}")
    end
  end
end
