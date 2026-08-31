require "../lexer"

module TMBSH
  class StringBased < Lexer
    @string : ::String
    @reader : Char::Reader

    def initialize(str : ::String)
      @string = str
      @reader = Char::Reader.new(str)
      @current_char = @reader.current_char? || '\0'
    end

    private def next_char_no_column_increment : Char
      @reader.next_char? || '\0'
    end

    private def peek_char : Char
      if @reader.has_next?
        @reader.peek_next_char
      else
        '\0'
      end
    end
  end
end
