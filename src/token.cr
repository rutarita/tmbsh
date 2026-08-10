module TMBSH
class Token
  enum Kind
    None
    Whitespace
    String
    SingleApostrophe
    DoubleApostrophe
    ParenthesisOpen
    ParenthesisClose
    SquareBracketOpen
    SquareBracketClose
    CurlyBracketOpen
    CurlyBracketClose
    Caret
    Semicolon
    At

    Newline
    ArrowRight
    InwardArrowRight
    ArrowLeft
    VariableAccess
    Splat
    Question
    Exclamation
    PathSeparator
    HeredocBegin
    Equal
    Percent
    Varname

    Ampersand
    AppendToFile
    GreaterThan # WriteToFile
    LessThan # ReadFromFile
    Pipe

    GreaterThanOrEqual
    LessThanOrEqual
    DoubleEqual
    NotEqual

    AssignmentTo

    DefKeyword
    IfKeyword
    ElseKeyword
    ElifKeyword
    EndKeyword
    InKeyword
    WhileKeyword
    ForKeyword
    ReturnKeyword
    BreakKeyword
    ContinueKeyword

    OrOperator
    AndOperator

    Comment
    EOF
    def eos?
      semicolon? || newline? || eof?
    end
  end
  property raw_value : ::String = ""
  property kind : Kind = :None
  property row : Int32 = 0
  property column : Int32 = 0
  def inspect
    "#{kind} (#{to_s}) [#{@row}:#{@column}]"
  end

  def inspect(io)
    io << inspect
  end

  def to_s
    case kind
      in .none?, .eof?, .comment? then ""
      in .whitespace?, .string?, .varname? then raw_value
      in .single_apostrophe? then "'"
      in .double_apostrophe? then "\""
      in .square_bracket_open? then "["
      in .square_bracket_close? then "]"
      in .parenthesis_open? then "("
      in .parenthesis_close? then ")"
      in .curly_bracket_open? then "{"
      in .curly_bracket_close? then "}"
      in .caret? then "^"
      in .semicolon? then ";"
      in .at? then "@"
      in .newline? then "\n"
      in .arrow_right? then "->"
      in .inward_arrow_right? then "-<"
      in .arrow_left? then "<-"
      in .variable_access? then "$"
      in .splat? then "*"
      in .question? then "?"
      in .exclamation? then "!"
      in .path_separator? then "/"
      in .pipe? then "|"
      in .ampersand? then "&"
      in .and_operator? then "&&"
      in .or_operator? then "||"
      in .append_to_file? then ">>"
      in .greater_than? then ">"
      in .less_than? then "<"
      in .greater_than_or_equal? then ">="
      in .less_than_or_equal? then "<="
      in .double_equal? then "=="
      in .not_equal? then "!="
      in .equal? then "="
      in .percent? then "%"
      in .heredoc_begin? then "<<"
      in .def_keyword? then "def"
      in .if_keyword? then "if"
      in .else_keyword? then "else"
      in .elif_keyword? then "elif"
      in .for_keyword? then "for"
      in .while_keyword? then "while"
      in .in_keyword? then "in"
      in .return_keyword? then "return"
      in .continue_keyword? then "continue"
      in .break_keyword? then "break"
      in .end_keyword? then "end"
      in .assignment_to? then "#{raw_value}="
    end
  end

  def to_s(io)
    io << to_s
  end

  def eos?
    kind.semicolon? || kind.newline? || kind.eof?
  end
end
end
