module TMBSH
  class MathToken
    enum Kind
      None
      Plus
      Minus
      Slash
      DoubleSlash
      Star
      DoubleStar
      Ampersand
      Pipe
      Caret
      Number
      Variable
      ParenthesisOpen
      ParenthesisClose
    end
  @raw_value : Int64 | Float64 | ::String = ""
  property raw_value
  @kind : Kind = :None
  property kind
  end
end
