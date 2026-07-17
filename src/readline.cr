@[Link("readline")]
lib LibReadLine
  alias HistData = Void*
  struct HIST_ENTRY
    line : UInt8*
    timestamp : UInt8*
    data : HistData
  end
  fun readline(prompt : UInt8*) : UInt8*
  fun history_list : HIST_ENTRY**
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

  def history_list : ::Array(::String)
    ptr = LibReadLine.history_list
    return [] of ::String if ptr.null?
    ary = [] of ::String
    until ptr.value.null?
      ary << ::String.new(ptr.value.value.line)
      ptr += 1
    end
    ary
    # size = (0..).each do |i|
    #   if ptr[i].null?
    #     break i
    #   end
    # end
    # ptr.to_slice(size).map { |entry| ::String.new(entry.value.line) }.to_a
  end
end
