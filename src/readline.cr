@[Link("readline")]
lib LibReadLine
  fun readline(prompt : UInt8*) : UInt8*
  fun add_history(line : UInt8*) : Void
  fun rl_bind_key(key : LibC::Int, function : LibC::Int, LibC::Int -> LibC::Int) : LibC::Int
end

module ReadLine

  extend self

  def readline(prompt : String) : String?
    ptr = LibReadLine.readline(prompt.to_unsafe)
    String.new(ptr) unless ptr.null?
  end

  def add_history(line : String) : Void
    LibReadLine.add_history(line.to_unsafe)
  end

  def bind_key(key : Char, function : Int32, Int32 -> Int32)
    LibReadLine.rl_bind_key(key.ord, function)
  end
end

