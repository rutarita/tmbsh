require "./nodes"

module TMBSH
  class UserDefinedFunction < Variant
    @proc : ::Proc(Interpreter::Context, ::Array(Variant), Variant?)
    @binded_args : ::Array(Variant) = [] of Variant
    @parent_class : ::String?
    @name : ::String?
    property name
    property parent_class
    def initialize(proc : ::Proc(Interpreter::Context, ::Array(Variant), Variant?), binded_args : ::Array(Variant)? = nil)
      @proc = proc
    end
    def initialize(name : ::String, proc : ::Proc(Interpreter::Context, ::Array(Variant), Variant?), binded_args : ::Array(Variant)? = nil)
      @name = name
      @proc = proc
    end
    def initialize(parent_class : ::String,name : ::String, proc : ::Proc(Interpreter::Context, ::Array(Variant), Variant?), binded_args : ::Array(Variant)? = nil)
      @proc = proc
      @parent_class = parent_class
    end

    def call(args : ::Array(Variant)) : Variant
      raise TypeError.new("Please call user defined functions with context")
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      @proc.call(context, args) || NULL
    end

    def [](key : Variant) : Variant
      raise "Cannot do access on UserDefinedFunction"
    end

    def []?(key : Variant) : Variant
      raise "Cannot do access on UserDefinedFunction"
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot set on UserDefinedFunction"
    end

    def to_s : ::String
      if parent_class = @parent_class
        "<Method name: #{@name} on class: #{parent_class}>"
      else
        if name = @name
          "<UserDefinedFunction name: #{@name}>"
        else
          "<Anonymus UserDefinedFunction id: #{object_id}>"
        end
      end
    end

    def to_f64 : Float64
      raise "Cannot convert UserDefinedFunction to Float"
    end

    def to_i64 : Int64
      raise "Cannot convert UserDefinedFunction to Int"
    end

    def to_a : ::Array(Variant)
      raise "Cannot convert UserDefinedFunction to Array"
    end

    def dup : UserDefinedFunction
      self.class.new(@proc, @binded_args.dup)
    end

    def clone : UserDefinedFunction
      self.class.new(@proc, @binded_args.clone)
    end

    def ==(other : Variant)
      other.is_a?(UserDefinedFunction) && @proc == other.@proc && @binded_args == other.@binded_args
    end

    def to_json : ::String
      raise "Cannot convert function to JSON"
    end

    def to_json(builder : JSON::Builder)
      raise "Cannot convert function to JSON"
    end

    def iter_init : Iterator
      raise "Cannot iterate over UserDefinedFunction"
    end

    def truthy? : ::Bool
      true
    end

    def bind!(args : ::Array(Variant)) : Nil
      @binded_args.concat(args)
    end

    def bind(args : ::Array(Variant)) : UserDefinedFunction
      fn = dup
      fn.bind!(args)
      fn
    end

    def hash : UInt64
      @proc.hash
    end
  end
end
