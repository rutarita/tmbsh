require "../lexer"

class TMBSH::IOBased < TMBSH::Lexer
  @io : IO
  @last_char : Char = '\0'
  def initialize(io : IO)
    @io = io
    @current_char = @io.read_char || '\0'
  end

  private def next_char_no_column_increment : Char
      # puts "uw9"
      if @last_char == '\0'
        @io.read_char || '\0'
      else
        char = @last_char
        @last_char = '\0'
        char
      end
    end

    private def peek_char : Char
      # puts "peek"
      if @last_char == '\0'
        char = next_char_no_column_increment
        @last_char = char
        char
      else
        @last_char
      end
    end

end
