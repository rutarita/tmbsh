struct StringName
  @@strings : Array(String) = [] of String
  @@strings_hash : Hash(String, Int32) = {} of String => Int32
  @@rw_lock = Sync::RWLock.new

  @index : Int32
  @string_hash : UInt64

  def initialize(str : String)
    @string_hash = str.hash
    index = @@rw_lock.read do
      @@strings_hash[str]?
    end
    if index
      @index = index
    else
      @@strings << str
      index = @@strings.size - 1
      @@rw_lock.write do
        @@strings_hash[str] = index
      end
      @index = index
    end
  end

  def ==(other : StringName)
    @index == other.@index
  end

  def ==(other : String)
    @@strings[@index] == other
  end

  def to_s
    @@strings[@index]
  end

  def hash
    @string_hash
  end
end
