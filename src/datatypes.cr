require "json"
require "./exceptions"
module TMBSH
  macro abstract_method(name, &body)
    Function.new(self.to_s.lchop("TMBSH::"), {{name}}, ->(args : ::Array(Variant)) : Variant? {
    this = args[0]
    {{body.body}}
    })
  end

  macro method(name, &body)
    Function.new(self.to_s.lchop("TMBSH::"), {{name}}, ->(args : ::Array(Variant)) : Variant? {
    this = args[0] # .as(self)
    raise "Wrong self" unless this.is_a?(self)
    {{body.body}}
    })
  end

  protected def self.variant_from_json(json : JSON::Any) : Variant
    raw = json.raw
    case raw
      in ::String then String.new(raw)
      in ::Int64 then Int.new(raw)
      in ::Float64 then Float.new(raw)
      in ::Array(JSON::Any)
        variants = raw.map do |item|
          variant_from_json(item)
        end
        Array.new(variants)
      in ::Bool then raw ? TRUE : FALSE
      in ::Hash(::String, JSON::Any)
        map = {} of Variant => Variant
        raw.each do |k, v|
          map[String.new(k)] = variant_from_json(v)
        end
        Dictionary.new(map)
      in Nil then NULL
    end
  end

    macro variant(val)
      {% if val.is_a?(::String) %}
        String.new(val)
      {% elsif val.is_a?(::Int) %}
        Int.new(val)
      {% elsif val.is_a?(::Float) %}
        Float.new(val)
      {% elsif val.is_a?(::Array)%}
        Array.new(val.map { |item| variant(val)})
      {% end %}
    end

  abstract class Variant
    @@methods : Hash(::String, Function) = {} of ::String => Function
    @@unstable_methods : ::Set(::String) = ::Set(::String).new # means methods that can vary in result even if the value is consistent
    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    ITER_METHOD = TMBSH.abstract_method("iter") do
      this.iter_init
    end

    CLONE_METHOD = TMBSH.abstract_method("clone") do
      this.clone
    end

    DUP_METHOD = TMBSH.abstract_method("dup") do
      this.dup
    end

    IS_A_METHOD = TMBSH.abstract_method("is_a") do
      this.variant_type?(args[1]?.to_s) ? TRUE : FALSE
    end

    EQ_METHOD = TMBSH.abstract_method("eq") do
      this == (args[1]? || NULL) ? TRUE : FALSE
    end

    STR_METHOD = TMBSH.abstract_method("str") do
      String.new(this.to_s)
    end

    ORELSE_METHOD = TMBSH.abstract_method("orelse") do
      raise "orelse method requires one argument" unless args.size == 2
      if this.is_a?(Null)
        args[1]
      else
        this
      end
    end

    TRUTHY_METHOD = TMBSH.abstract_method("truthy?") do
      raise "truthy? method expects no arguments" unless args.size == 1
      this.truthy? ? TRUE : FALSE
    end

    abstract def call(args : ::Array(Variant)) : Variant
    abstract def to_f64 : Float64

    abstract def to_i64 : Int64
    def to_i : Int32
      to_i64.to_i
    end

    def to_u8 : UInt8
      to_i.to_u8
    end

    abstract def to_s : ::String
    abstract def to_a : ::Array(Variant)

    def to_shfloat : Float
      Float.new(to_f64)
    end

    def to_shint : Int
      Int.new(to_i64)
    end

    def to_sharr : Array
      Array.new(to_a)
    end

    def to_shs : String
      String.new(to_s)
    end

    abstract def to_json : ::String
    abstract def to_json(builder : JSON::Builder)
    abstract def hash : UInt64
    abstract def clone
    abstract def dup
    abstract def [](key : Variant) : Variant
    abstract def []?(key : Variant) : Variant
    abstract def []=(key : Variant, value : Variant)

    abstract def ==(other : Variant)

    abstract def iter_init : Iterator

    abstract def truthy? : ::Bool
    {% if flag?(:method_hash_caching)%}
    def get_method(method_hash : UInt64) : Function?
      @@methods_hash_cache[method_hash]?
    end
    {% end %}


    def get_method(name : ::String)
      if method = @@methods[name]?
        {% if flag?(:method_hash_caching) %}
        @@methods_hash_cache[name.hash] = method
        {% end %}
        method
      else
        raise MethodDoesNotExist.new("Method #{name} doesn't exist on #{self.class}")
      end
    end

    @@type_aliases : ::Set(::String) = ::Set(::String).new

    def variant_type?(typename : ::String)
      @@type_aliases.includes? typename.downcase
    end

    def get_method_list : ::Array(::String)
      @@methods.keys
    end
  end


  abstract class Iterator < Variant

    private module IteratorBoilerplate
      @iterator : Iterator
      @func : Function
      def initialize(iterator : Iterator, func : Function)
        @iterator = iterator
        @func = func
      end
      def clone : self
        self.class.new(@iterator.clone, @func)
      end

      def dup : self
        self.class.new(@iterator.dup, @func)
      end
    end

    class MapIterator < Iterator
      include IteratorBoilerplate

      def iter_next : Variant?
        val = @iterator.iter_next
        return unless val
        @func.call([val] of Variant)
      end

    end

    class SelectIterator < Iterator

      include IteratorBoilerplate

      def iter_next : Variant?
        while true
          val = @iterator.iter_next
          return unless val
          if @func.call([val] of Variant).truthy?
            return val
          end
        end
      end
    end
    class RejectIterator < Iterator

      include IteratorBoilerplate

      def iter_next : Variant?
        while true
          val = @iterator.iter_next
          return unless val
          unless @func.call([val] of Variant).truthy?
            return val
          end
        end
      end
    end


    NEXT_METHOD = TMBSH.method("next") do
      this.iter_next || NULL
    end
    TO_A_METHOD = TMBSH.method("to_a") do
      this.to_sharr
    end
    {% for itertype in ["map", "select", "reject"] %}
      {{itertype.id.upcase}}_METHOD = TMBSH.method({{itertype}}) do
        func = args[1]?
        raise "Expected 1 argument that is a function" unless args.size == 2 && func.is_a?(Function)
        this.{{itertype.id}}(func)
      end
    {% end %}

    FOLD_METHOD = TMBSH.method("fold") do
      into = args[1]?
      func = args[2]?
      raise "Expected 1 collector argument and second Function argument" unless into && func.is_a?(Function)
      this.fold(into, func)
    end

    @@methods = {
      "next"   => NEXT_METHOD,
      "to_a"   => TO_A_METHOD,
      "eq?"    => EQ_METHOD,
      "str"    => STR_METHOD,
      "map"    => MAP_METHOD,
      "select" => SELECT_METHOD,
      "reject" => REJECT_METHOD,
      "fold"   => FOLD_METHOD,

      "orelse" => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"iter", "iterator"}

    abstract def iter_next : Variant?

    def call(args : ::Array(Variant)) : Variant
      iter_next || NULL
    end

    def to_f64 : Float64
      raise "Cannot convert iterator to Float"
    end

    def to_i64 : Int64
      raise "Cannot convert iterator to Int"
    end

    def to_s : ::String
      "<#{self.class.to_s.lchop("TMBSH::")} iterator>"
    end

    def to_a : ::Array(Variant)
      arr = [] of Variant
      while val = iter_next
        arr << val
      end
      arr
    end

    def to_json : ::String
      raise "Cannot convert Iterator to JSON"
    end

    def to_json(builder : JSON::Builder)
      raise "Cannot convert Iterator to JSON"
    end

    def hash : UInt64
      raise "Do not use Iterator as key"
    end

    def [](key : Variant) : Variant
      raise "Cannot do key access on Iterator (Try converting it to array first)"
    end

    def []?(key : Variant) : Variant
      raise "Cannot do key access on Iterator (Try converting it to array first)"
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot do key assignment on Iterator"
    end

    def iter_init : Iterator
      self
    end

    def each(& : Variant ->)
      while val = iter_next
        yield val
      end
    end

    def ==(other : Variant) : ::Bool
      same?(other)
    end

    def truthy? : ::Bool
      true
    end

    {% for itertype in ["map", "select", "reject"]%}
      def {{itertype.id}}(func : Function)
        {{itertype.id.titleize}}Iterator.new(self, func)
      end
    {% end %}

    def fold(into : Variant, func : Function)
      each do |i|
        func.call([into, i] of Variant)
      end
      into
    end

  end

  macro num_type_def(name,num_type, conversion)
  class {{name}} < Variant
    class NumberIterator < Iterator
      @current : {{num_type}} = {{num_type}}.zero
      @target : {{num_type}}
      property current
      property target

      def initialize(val : {{num_type}})
        @target = val
      end

      def iter_next : Variant?
        if @current < @target
          cur = @current
          @current += 1
          {{name}}.new(cur.{{conversion}})
        end
      end

      def clone : self
        v = self.class.new(@target)
        v.current = @current
        v
      end

      def dup : self
        v = self.class.new(@target)
        v.current = @current
        v
      end
    end

    @value : {{num_type}}

    ADD_METHOD = TMBSH.method("add") do
      num = this.@value
      args[1..].each do |arg|
        num += arg.{{conversion}}
      end
      {{name}}.new(num)
    end

    SUB_METHOD = TMBSH.method("sub") do
      num = this.@value
      args[1..].each do |arg|
        num -= arg.{{conversion}}
      end
      {{name}}.new(num)
    end

    MUL_METHOD = TMBSH.method("mul") do
      num = this.@value
      args[1..].each do |arg|
        num *= arg.{{conversion}}
      end
      {{name}}.new(num)
    end

    DIV_METHOD = TMBSH.method("div") do
      num = this.@value
      args[1..].each do |arg|
        num /= arg.{{conversion}}
      end
      {{name}}.new(num)
    end

    AND_METHOD = TMBSH.method("and") do
      res = this.@value.to_i64
      args[1..].each do |arg|
        res &= arg.to_i
      end
      Int.new(res)
    end
    OR_METHOD = TMBSH.method("or") do
      res = this.@value.to_i64
      args[1..].each do |arg|
        res |= arg.to_i
      end
      Int.new(res)
    end

    XOR_METHOD = TMBSH.method("xor") do
      res = this.@value.to_i64
      args[1..].each do |arg|
        res ^= arg.to_i
      end
      Int.new(res)
    end

    FDIV_METHOD = TMBSH.method("fdiv") do
      num = this.@value
      args[1..].each do |arg|
        num //= arg.{{conversion}}
      end
      {{name}}.new(num)
    end
    POW_METHOD = TMBSH.method("pow") do
      num = this.@value
      args[1..].each do |arg|
        num **= arg.{{conversion}}
      end
      {{name}}.new(num)
    end
    # IS_A_METHOD = TMBSH.method("is_a") do
    #   this.variant_type?(args[1]?.to_s) ? TRUE : FALSE
    # end
    FLOAT_METHOD = TMBSH.method("float") do
      Float.new(this.to_f64)
    end
    INT_METHOD = TMBSH.method("int") do
      Int.new(this.to_i64)
    end
    TO_METHOD = TMBSH.method("to") do
      if dest = args[1]?
        this.to(dest, args[2]?)
      end
    end

    TOE_METHOD = TMBSH.method("toe") do
      if dest = args[1]?
        this.toe(dest, args[2]?)
      end
    end

    GT_METHOD = TMBSH.method("gt") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      this.@value > args[1].{{conversion}} ? TRUE : FALSE
    end

    LT_METHOD = TMBSH.method("lt") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      this.@value < args[1].{{conversion}} ? TRUE : FALSE
    end

    GTE_METHOD = TMBSH.method("gte") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      this.@value >= args[1].{{conversion}} ? TRUE : FALSE
    end

    LTE_METHOD = TMBSH.method("lte") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      this.@value <= args[1].{{conversion}} ? TRUE : FALSE
    end

    RANGE_METHOD = TMBSH.method("range") do
      Range.new(this.@value.to_i64, args[1]?.try &.to_i64, false)
    end

    ERANGE_METHOD = TMBSH.method("erange") do
      Range.new(this.@value.to_i64, args[1]?.try &.to_i64, true)
    end

    HUMANIZE_METHOD = TMBSH.method("humanize") do
      String.new(this.@value.humanize)
    end

    {% for i in ["round", "ceil", "floor", "abs", "abs2"] %}
      {{i.id.upcase}}_METHOD = TMBSH.method("{{i.id.upcase}}") do
        {{name}}.new(this.@value.{{i.id}})
      end
    {% end %}

    SIGNIFICANT_METHOD = TMBSH.method("significant") do
      raise ArgumentError.new("Expected 1-2 arguments to significant") if args.size < 2 || args.size > 3
      digits = args[1].to_i64
      base = args[2]? ? args[2].to_i64 : 10
      {{name}}.new(this.@value.significant(digits, base))
    end

    STR_METHOD = TMBSH.method("str") do
      {% if num_type.id[0..2] == "Int" %}
        base = 10
        if arg = args[1]?
          base = arg.to_i
        end
        String.new(this.@value.to_s(base))
      {% else %}
        String.new(this.to_s)
      {% end %}
    end
    @@methods = {
      "add"         => ADD_METHOD,
      "sub"         => SUB_METHOD,
      "mul"         => MUL_METHOD,
      "div"         => DIV_METHOD,
      "and"         => AND_METHOD,
      "or"         => OR_METHOD,
      "xor"         => XOR_METHOD,
      "pow"         => POW_METHOD,
      "fdiv"        => FDIV_METHOD,
      "significant" => SIGNIFICANT_METHOD,
      "round"       => ROUND_METHOD,
      "ceil"        => CEIL_METHOD,
      "floor"       => FLOOR_METHOD,
      "abs"         => ABS_METHOD,
      "abs2"        => ABS2_METHOD,
      "gt"          => GT_METHOD,
      "lt"          => LT_METHOD,
      "gte"         => GTE_METHOD,
      "lte"         => LTE_METHOD,
      "iter"        => ITER_METHOD,
      "str"         => STR_METHOD,
      "humanize"    => HUMANIZE_METHOD,
      "hum"         => HUMANIZE_METHOD,
      "float"       => FLOAT_METHOD,
      "int"         => INT_METHOD,
      "range"       => RANGE_METHOD,
      "erange"      => ERANGE_METHOD,
      "r"           => RANGE_METHOD,
      "er"          => ERANGE_METHOD,
      "to"          => TO_METHOD,
      "toe"         => TOE_METHOD,

      "is_a?"       => IS_A_METHOD,
      "eq?"         => EQ_METHOD,
      "eq"          => EQ_METHOD,
      "orelse"      => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"{{name.id.downcase}}", "{{num_type.id.downcase}}"}

    def initialize(val : ::Number)
      @value = val.{{conversion}}
    end

    def initialize
      @value = {{num_type}}.zero
    end

    def to_s : ::String
      @value.format(delimiter: nil)
    end

    def to_f64 : Float64
      @value.to_f64
    end

    def to_i64 : Int64
      @value.to_i64
    end

    def to_a : ::Array(Variant)
      arr = [] of Variant
      @value.to_i.times do |i|
        arr << {{name}}.new(i)
      end
      arr
    end

    def dup : {{name}}
      self.class.new(@value)
    end

    def clone : {{name}}
      self.class.new(@value)
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      raise "Cannot do access on {{name}}"
    end

    def []?(key : Variant) : Variant
      raise "Cannot do access on {{name}}"
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot ::Set on {{name}}"
    end

    def call(args : ::Array(Variant)) : Variant
      raise "Cannot call {{name}}"
    end

    def ==(other : Variant)
      other.is_a?({{name}}) && @value == other.@value
    end

    def to_json : ::String
      to_s
    end

    def to_json(builder : JSON::Builder)
      builder.number(@value)
    end

    def to(destination : Variant, step : Variant?) : Array
      destination = destination.{{conversion}}
      arr = [] of Variant
      num = @value
      diff_sign = (destination - @value).sign
      step = step ? step.{{conversion}} : diff_sign.{{conversion}}
      step_sign = step.sign
      raise "From #{@value} to #{destination} is unreachable with this step #{step}" if step_sign != diff_sign
      if diff_sign == 1
        while num <= destination
          arr << {{name}}.new(num)
          num += step
        end
      else
        while num >= destination
          arr << {{name}}.new(num)
          num += step
        end
      end
      Array.new(arr)
    end

    def toe(destination : Variant, step : Variant?) : Array
      destination = destination.{{conversion}}
      arr = [] of Variant
      num = @value
      diff_sign = (destination - @value).sign
      step = step ? step.{{conversion}} : diff_sign.{{conversion}}
      step_sign = step.sign
      raise "From #{@value} to #{destination} is unreachable with this step #{step}" if step_sign != diff_sign
      if diff_sign == 1
        while num < destination
          arr << {{name}}.new(num)
          num += step
        end
      else
        while num > destination
          arr << {{name}}.new(num)
          num += step
        end
      end
      Array.new(arr)
    end

    def iter_init : Iterator
      NumberIterator.new(@value.to_i)
    end

    def truthy? : ::Bool
      @value != 0.0
    end
  end
  end

  num_type_def(Float, Float64, to_f64)
  num_type_def(Int, Int64, to_i64)

  class Range < Variant
    class RangeIterator < Iterator
      @iterator : ::Iterator(Int64)
      property iterator

      def initialize(i : ::Iterator(Int64))
        @iterator = i
      end

      def initialize(val : AnyRange)
        unless val.is_a?(::Range(Nil, Int64) | ::Range(Nil, Nil))
          @iterator = val.each
        else
          raise "Can't iterate over beginingless ranges"
        end
      end

      def iter_next : Variant?
        val = @iterator.next
        return if val.is_a?(::Iterator::Stop)
        return Float.new(val.to_f64)
      end

      def clone : self
        self.class.new(@iterator.dup)
      end

      def dup : self
        self.class.new(@iterator.dup)
      end
    end

    alias AnyRange = ::Range(Int64, Int64) | ::Range(Nil, Int64) | ::Range(Int64, Nil) | ::Range(Nil, Nil)

    @value : AnyRange

    TO_A_METHOD = TMBSH.method("to_a") do
      this.to_sharr
    end

    BEGIN_METHOD = TMBSH.method("begin") do
      val = this.@value.begin
      if val
        Float.new(val.to_f64)
      else
        NULL
      end
    end

    END_METHOD = TMBSH.method("end") do
      val = this.@value.end
      if val
        Float.new(val.to_f64)
      else
        NULL
      end
    end

    @@methods = {
      "begin"  => BEGIN_METHOD,
      "end"    => END_METHOD,
      "to_a"   => TO_A_METHOD,
      "iter"   => ITER_METHOD,
      "str"    => STR_METHOD,

      "truthy?" => TRUTHY_METHOD,
      "is_a?"  => IS_A_METHOD,
      "eq?"    => EQ_METHOD,
      "orelse" => ORELSE_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"range"}

    def initialize(from : Int64?, to : Int64?, is_exclusive : ::Bool)
      if from && to
        @value = ::Range(Int64, Int64).new(from, to, is_exclusive)
      elsif from
        @value = ::Range(Int64, Nil).new(from, nil, is_exclusive)
      elsif to
        @value = ::Range(Nil, Int64).new(nil, to, is_exclusive)
      else
        @value = ::Range(Nil, Nil).new(nil, nil, is_exclusive)
      end
    end

    def initialize(range : AnyRange)
      @value = range
    end

    def to_s : ::String
      @value.to_s
    end

    def to_f64 : Float64
      raise "Cannot conver Range to Float"
    end

    def to_i64 : Int64
      raise "Cannot conver Range to Int"
    end

    def to_a : ::Array(Variant)
      arr = [] of Variant
      @value.each do |i|
        arr << Float.new(i)
      end
      arr
    end

    def dup : Range
      self.class.new(@value)
    end

    def clone : Range
      self.class.new(@value)
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      raise "Cannot do access on Range"
    end

    def []?(key : Variant) : Variant
      raise "Cannot do access on Range"
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot ::Set on Range"
    end

    def call(args : ::Array(Variant)) : Variant
      raise "Cannot call Range"
    end

    def ==(other : Variant)
      other.is_a?(Range) && @value == other.@value
    end

    def to_json : ::String
      raise "Cannot convert Range to json"
    end

    def to_json(builder : JSON::Builder)
      raise "Cannot convert Range to json"
    end

    def iter_init : Iterator
      RangeIterator.new(@value)
    end

    def truthy? : ::Bool
      true
    end
  end

  class Array < Variant
    class ArrayIterator < Iterator
      @array : ::Array(Variant)
      @current_idx : Int32 = 0
      property array
      property current_idx

      def initialize(val : ::Array(Variant))
        @array = val
      end

      def iter_next : Variant?
        if @current_idx < @array.size
          idx = @current_idx
          @current_idx += 1
          @array[idx]
        end
      end

      def clone : self
        v = self.class.new(@array.dup)
        v.current_idx = @current_idx
        v
      end

      def dup : self
        v = self.class.new(@array)
        v.current_idx = @current_idx
        v
      end
    end

    @value : ::Array(Variant)
    SIZE_METHOD = TMBSH.method("size") do
      Int.new(this.@value.size)
    end
    APPEND_METHOD = TMBSH.method("append") do
      args[1..].each do |item|
        this << item
      end
      this
    end

    POP_METHOD = TMBSH.method("pop") do
      this.@value.pop?
    end

    EMPTY_METHOD = TMBSH.method("empty") do
      this.@value.empty? ? TRUE : FALSE
    end

    INDEX_METHOD = TMBSH.method("index") do
      obj = args[1]? || NULL
      if offset = args[2]?
        offset = offset.to_i
        this.@value.index(obj, offset)
      else
        this.@value.index(obj)
      end
    end

    DELETE_METHOD = TMBSH.method("delete") do
      args[1..].each do |item|
        this.delete item
      end
      this
    end
    CONCAT_METHOD = TMBSH.method("concat") do
      copy = this.dup
      args[1..].each do |item|
        arr = item.to_a
        copy.@value.concat(arr)
      end
      copy
    end
    REVERSE_METHOD = TMBSH.method("reverse") do
      Array.new(this.@value.reverse)
    end
    CLEAR_METHOD = TMBSH.method("clear") do
      this.@value.clear
      this
    end
    TO_JSON_METHOD = TMBSH.method("to_json") do
      String.new(this.to_json)
    end

    {% for i in ["sum", "sort", "sort_num"] %}
    {{i.id.upcase}}_METHOD = TMBSH.method("{{i.id.upcase}}") do
      raise ArgumentError.new("Expected no arguments") unless args.size == 1
      this.{{i.id}}
    end
    {% end %}

    SHIFT_METHOD = TMBSH.method("shift") do
      this.@value.shift
    end
    UNSHIFT_METHOD = TMBSH.method("unshift") do
      args[1..].each do |arg|
        this.@value.unshift arg
      end
      this
    end

    FETCH_METHOD = TMBSH.method("fetch") do
      raise ArgumentError.new("Expected one or two arguments") if args.size > 3 || args.size < 2
      key = args[1]
      if alt = args[2]?
        this[key]? || alt
      else
        this[key]?
      end
    end

    {% for name in ["map", "select", "reject"] %}
        {{name.id.upcase}}_METHOD = TMBSH.method("{{name.id.upcase}}") do
          fn = args[1]?
          raise ArgumentError.new("First argument to {{name.id}} must be a function") unless fn.is_a?(Function)
          this.{{name.id}}(fn)
        end
        {{name.id.upcase}}_IN_PLACE_METHOD = TMBSH.method("{{name.id.upcase}}_in_place") do
          fn = args[1]?
          raise ArgumentError.new("First argument to {{name.id}} must be a function") unless fn.is_a?(Function)
          this.{{name.id}}!(fn)
        end
      {% end %}
    REDUCE_METHOD = TMBSH.method("reduce") do
      if args.size == 3
        initial_value = args[1]
        fn = args[2]
        raise ArgumentError.new("Expected argument 2 to be a Function") unless fn.is_a?(Function)
        this.reduce(args[1], fn)
      elsif args.size == 2
        fn = args[1]
        raise ArgumentError.new("Expected argument 1 to be a Function") unless fn.is_a?(Function)
        this.reduce(fn)
      else
        raise ArgumentError.new("Expected 1 or 2 arguments (optional initial value and callback)") unless args.size == 3
      end
    end

    FIND_METHOD = TMBSH.method("find") do
      if args.size == 3
        if_none = args[2]
        fn = args[1]
        raise ArgumentError.new("Expected argument 2 to be a Function") unless fn.is_a?(Function)
        this.find(fn, if_none)
      elsif args.size == 2
        fn = args[1]
        raise ArgumentError.new("Expected argument 1 to be a Function") unless fn.is_a?(Function)
        this.find(fn)
      else
        raise ArgumentError.new("Expected 1 or 2 arguments (optional initial value and callback)") unless args.size == 3
      end
    end
    RESIZE_METHOD = TMBSH.method("resize") do
      num = args[1]
      raise ArgumentError.new("Expected only one argument to resize") unless args.size == 2
      raise ArgumentError.new("Only argument to resize must be a number") unless num.is_a?(Float | Int | String)
      new_size = num.to_i
      this.resize(new_size)
      this
    end

    JOIN_METHOD = TMBSH.method("join") do
      sep = args[1]?.try &.to_s || ""
      String.new(this.join(sep))
    end

    INCLUDES_METHOD = TMBSH.method("includes") do
      raise ArgumentError.new("Expected only one argument to includes") unless args.size == 2
      this.@value.includes?(args[1]) ? TRUE : FALSE
    end

    PARTITION_METHOD = TMBSH.method("partition") do
      fn = args[1]?
      raise ArgumentError.new("Expected first and only argument to be a Function") unless fn.is_a?(Function)
      this.partition(fn)
    end

    DECODE_METHOD = TMBSH.method("decode") do
      this.decode
    end

    @@methods = {
      "size"     => SIZE_METHOD,
      "append"   => APPEND_METHOD,
      "fetch"    => FETCH_METHOD,
      "pop"      => POP_METHOD,
      "ap"       => APPEND_METHOD,
      "delete"   => DELETE_METHOD,
      "del"      => DELETE_METHOD,
      "concat"   => CONCAT_METHOD,
      "join"     => JOIN_METHOD,
      "reverse"  => REVERSE_METHOD,
      "clear"    => CLEAR_METHOD,
      "str"      => STR_METHOD,
      "sum"      => SUM_METHOD,
      "map"      => MAP_METHOD,
      "map!"     => MAP_IN_PLACE_METHOD,
      "select"   => SELECT_METHOD,
      "select!"  => SELECT_IN_PLACE_METHOD,
      "reject"   => REJECT_METHOD,
      "reject!"  => REJECT_IN_PLACE_METHOD,
      "partition" => PARTITION_METHOD,
      "reduce"   => REDUCE_METHOD,
      "find"     => FIND_METHOD,
      "shift"    => SHIFT_METHOD,
      "unshift"  => UNSHIFT_METHOD,
      "resize"   => RESIZE_METHOD,
      "includes?"=> INCLUDES_METHOD,
      "has"      => INCLUDES_METHOD,
      "has?"      => INCLUDES_METHOD,

      "decode" => DECODE_METHOD,

      "to_json"  => TO_JSON_METHOD,

      "is_a?"    => IS_A_METHOD,
      "iter"     => ITER_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "eq?"      => EQ_METHOD,
      "sort"     => SORT_METHOD,
      "sort_num" => SORT_NUM_METHOD,
      "orelse"   => ORELSE_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"arr", "array", "list"}

    def initialize
      @value = [] of Variant
    end

    def initialize(arr : ::Array(Variant))
      @value = arr
    end

    def dup : Array
      self.class.new(@value.dup)
    end

    def clone : Array
      self.class.new(@value.clone)
    end

    def to_s : ::String
      join(" ")
    end

    def to_f64 : Float64
      raise TypeError.new("Cannot convert Array type to Float")
    end
    def to_i64 : Int64
      raise TypeError.new("Cannot convert Array type to Int")
    end

    def to_a : ::Array(Variant)
      @value.dup
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      if key.is_a?(Range)
        Array.new(@value[key.@value])
      else
        @value[key.to_i64]
      end
    end

    def []?(key : Variant) : Variant
      @value[key.to_i64]? || NULL
    end

    def []=(key : Variant, value : Variant)
        @value[key.to_i64] = value
    end

    def call(args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call Array")
    end

    def ==(other : Variant)
      other.is_a?(Array) && @value == other.@value
    end

    def <<(val : Variant)
      @value << val
    end

    def to_json : ::String
      ::String.build do |io|
        io << '['
        @value[0...-1].each do |item|
          io << item.to_json
          io << ','
        end
        io << @value[-1]?.try &.to_json
        io << ']'
      end
    end

    def to_json(builder : JSON::Builder)
      builder.array do
        @value.each do |item|
          item.to_json(builder)
        end
      end
    end

    def to_string_array : ::Array(::String)
      str_arr = [] of ::String
      @value.each do |item|
        if item.is_a?(Array | Set)
          str_arr.concat(item.to_string_array)
        elsif item.is_a?(Dictionary)
          str_arr.concat(item.pairs("=", "--"))
        else
          str_arr << item.to_s
        end
      end
      str_arr
    end

    def delete(var : Variant)
      @value.delete(var)
    end

    def sum : Float
      res = @value.reduce(0.0) { |acc, item| acc + item.to_f64}
      Float.new(res)
    end

    def sort! : self
      # to_s operations can be expensive like on arrays so we can precalculate them
      pairs = @value.map { |item| {item, item.to_s} }
      pairs.sort! {|left, right| left[1] <=> right[1]}
      sorted_arr = pairs.map { |v, _| v }
      @value = sorted_arr
      self
    end

    def sort : self
      dup.sort!
    end

    def sort_num : Array
      pairs = @value.map { |item| {item, item.to_f64} }
      pairs.sort! {|left, right| left[1] <=> right[1]}
      sorted_arr = pairs.map { |v, _| v }
      Array.new(sorted_arr)
    end

    def iter_init : Iterator
      ArrayIterator.new(@value)
    end

    def truthy? : ::Bool
      !@value.empty?
    end

    def map!(fn : Function)
      @value.map! do |var|
        fn.call([var] of Variant)
      end
      self
    end

    def map(fn : Function)
      dup.map!(fn)
    end

    def select!(fn : Function)
      @value.select! do |var|
        fn.call([var] of Variant).truthy?
      end
      self
    end

    def select(fn : Function)
      dup.select!(fn)
    end

    def reject!(fn : Function)
      @value.reject! do |var|
        fn.call([var] of Variant).truthy?
      end
      self
    end

    def reject(fn : Function)
      dup.reject!(fn)
    end

    def reduce(fn : Function)
      initial_value = @value[0]
      @value[1..].reduce(initial_value) do |acc, i|
        fn.call([acc, i] of Variant)
      end
    end

    def reduce(initial_value : Variant, fn : Function)
      @value.reduce(initial_value) do |acc, i|
        fn.call([acc, i] of Variant)
      end
    end

    def find(fn : Function, if_none : Variant = NULL)
      @value.find(if_none) do |item|
        fn.call([item] of Variant).truthy?
      end
    end

    def resize(new_size : Int32)
      if new_size == 0
        @value.clear
      elsif new_size < 0
        raise "New size cannot be negative"
      elsif new_size > @value.size
        (new_size - @value.size).times do
          @value << NULL
        end
      elsif new_size < @value.size
        @value = @value[...new_size]
      end
    end

    def join(sep : ::String = "") : ::String
      return "" if @value.empty?
      str_arr = @value.map &.to_s
      # bytesize = str_arr.reduce(0) { |acc, item| acc + item.bytesize} + sep.bytesize * (str_arr.size - 1)
      bytesize, codepoints_count = str_arr.reduce({0, 0}) { |acc, item| {acc[0] + item.bytesize, acc[1] + item.size}}
      sep_count = str_arr.size - 1
      bytesize += sep.bytesize * sep_count
      codepoints_count += sep.size * sep_count
      # codepoints_count = str_arr.reduce(0) { |acc, item| acc + item.size} + sep.size * (str_arr.size - 1)
      ::String.new(bytesize) do |buffer|
        io = buffer.appender
        str_arr[0...-1].each do |item|
          item.each_byte { |b| io << b }
          sep.each_byte { |b| io << b}
          # io << item
          # io << sep
        end
        # io << str_arr[-1]
        str_arr.last.each_byte { |b| io << b }
        {bytesize, codepoints_count}
      end
    end

    def partition(func : Function) : Array
      a, b = @value.partition do |val|
        func.call([val] of Variant).truthy?
      end
      a = Array.new(a)
      b = Array.new(b)
      Array.new([a, b] of Variant)
    end

    def decode : String
      arr = @value.map {|v| v.to_u8}
      slice = Bytes.new(arr.size) do |i|
        arr[i]
      end
      String.new(::String.new(slice))
    end
  end

  class Set < Variant
    @value : ::Set(Variant)

    ADD_METHOD = TMBSH.method("add") do
      args[1..].each do |item|
        this << item
      end
      this
    end

    {%for i in ["subset_of", "superset_of"]%}
      {{i.id.upcase}}_METHOD = TMBSH.method("{{i.id.upcase}}") do
        raise ArgumentError.new("Expected one argument") unless args.size == 2
        other = args[1]
        raise TypeError.new("Expected the argument to be of type Set") unless other.is_a?(Set)
        this.{{i.id}}?(other) ? TRUE : FALSE
      end

      PROPER_{{i.id.upcase}}_METHOD = TMBSH.method("proper_{{i.id.upcase}}") do
        raise ArgumentError.new("Expected one argument") unless args.size == 2
        other = args[1]
        raise TypeError.new("Expected the argument to be of type Set") unless other.is_a?(Set)
        this.proper_{{i.id}}?(other) ? TRUE : FALSE
      end
    {%end%}
    # SUBSET_OF_METHOD = TMBSH.method("subset_of") do
    #   raise "Expected one argument" unless args.size == 2
    #   this.subset_of?(args[1])
    # end
    #
    # SUPERSET_OF_METHOD = TMBSH.method("superset_of") do
    #   raise "Expected one argument" unless args.size == 2
    #   this.superset_of?(args[1])
    # end
    #
    # PROPER_SUBSET_OF_METHOD = TMBSH.method("proper_subset_of") do
    #   raise "Expected one argument" unless args.size == 2
    #   this.proper_subset_of?(args[1])
    # end
    #
    # PROPER_SUPERSET_OF_METHOD = TMBSH.method("proper_superset_of") do
    #   raise "Expected one argument" unless args.size == 2
    #   this.proper_superset_of?(args[1])
    # end

    AND_METHOD = TMBSH.method("and") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      other = args[1]
      raise TypeError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this & other
    end
    OR_METHOD = TMBSH.method("or") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      other = args[1]
      raise TypeError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this | other
    end
    XOR_METHOD = TMBSH.method("xor") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      other = args[1]
      raise TypeError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this ^ other
    end
    UNION_METHOD = TMBSH.method("union") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      other = args[1]
      raise TypeError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this + other
    end
    DIFFERENCE_METHOD = TMBSH.method("difference") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      other = args[1]
      raise TypeError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this - other
    end

    TO_A_METHOD = TMBSH.method("to_a") do
      this.to_sharr
    end

    INCLUDES_METHOD = TMBSH.method("includes") do
      raise ArgumentError.new("Expected one argument") unless args.size == 2
      this.includes?(args[1])
    end

    CLEAR_METHOD = TMBSH.method("clear") do
      this.clear
      this
    end

    DELETE_METHOD = TMBSH.method("delete") do
      args[1..].each do |item|
        this.delete item
      end
      this
    end

    @@methods = {
      "add"        => ADD_METHOD,
      "delete"     => DELETE_METHOD,
      "del"        => DELETE_METHOD,
      "includes?"  => INCLUDES_METHOD,
      "has?"       => INCLUDES_METHOD,
      "has"        => INCLUDES_METHOD,
      "union"      => UNION_METHOD,
      "diff"       => DIFFERENCE_METHOD,
      "difference" => DIFFERENCE_METHOD,
      "and"        => AND_METHOD,
      "or"         => OR_METHOD,
      "xor"        => XOR_METHOD,
      "subset_of?" => SUBSET_OF_METHOD,
      "proper_subset_of?" => PROPER_SUBSET_OF_METHOD,
      "superset_of?" => SUPERSET_OF_METHOD,
      "proper_superset_of?" => PROPER_SUPERSET_OF_METHOD,
      "to_a"       => TO_A_METHOD,
      "clear"      => CLEAR_METHOD,

      "is_a?"      => IS_A_METHOD,
      "eq?"        => EQ_METHOD,
      "str"        => STR_METHOD,
      "orelse"     => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"set", "hash"}

    def initialize
      @value = ::Set(Variant).new
    end

    def initialize(set : ::Set(Variant))
      @value = set
    end

    def initialize(set : ::Array(Variant))
      @value = set.to_set
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      raise TypeError.new("Cannot do access on Set")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot do access on Set")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot set key on Set")
    end

    def to_s : ::String
      ::String.build do |io|
        io << '^'
        io << to_sharr.join(" ")
        io << '^'
      end
    end

    def to_f64 : Float64
      raise TypeError.new("Cannot convert Set to Float")
    end

    def to_i64 : Int64
      raise TypeError.new("Cannot convert Set to Int")
    end

    def to_a : ::Array(Variant)
      @value.to_a
    end

    def dup : Set
      self.class.new(@value.dup)
    end

    def clone : Set
      self.class.new(@value.clone)
    end

    def call(args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call Set")
    end

    def ==(other : Variant)
      other.is_a?(Set) && @value == other.@value
    end

    def to_json : ::String
      @value.to_json
    end

    def to_json(builder : JSON::Builder)
      @value.to_json(builder)
    end

    def iter_init : Iterator
      to_sharr.iter_init
    end

    def truthy? : ::Bool
      !@value.empty?
    end

    def to_string_array : ::Array(::String)
      str_arr = [] of ::String
      @value.each do |item|
        if item.is_a?(Array | Set)
          str_arr.concat(item.to_string_array)
        elsif item.is_a?(Dictionary)
          str_arr.concat(item.pairs("=", "--"))
        else
          str_arr << item.to_s
        end
      end
      str_arr
    end

    def empty? : Bool
      @value.empty? ? TRUE : FALSE
    end

    {% for i in ["&", "|", "^", "-", "+"] %}
      def {{i.id}}(other : Set)
        self.class.new(@value {{i.id}} other.@value)
      end
    {% end %}

    def <<(other : Variant)
      @value << other
    end

    def delete(item : Variant)
      @value.delete item
    end

    {%for i in ["subset_of", "superset_of"]%}
      def {{i.id}}?(other : Set) : ::Bool
        @value.{{i.id}}?(other.@value)
      end

      def proper_{{i.id}}?(other : Set) : ::Bool
        @value.proper_{{i.id}}?(other.@value)
      end
    {%end%}

    def concat(other : Variant)
      @value.concat(other.to_a)
    end

    def clear
      @value.clear
    end

    def delete(el : Variant)
      @value.delete(el)
    end

    def includes?(var : Variant)
      @value.includes?(var) ? TRUE : FALSE
    end

    def size : Float
      Float.new(@value.size.to_f64)
    end
  end

  class String < Variant
    class StringIterator < Iterator
      @str : ::String
      @current_idx : Int32 = 0
      property str
      property current_idx

      @@string_pool : StringPool = StringPool.new

      def initialize(val : ::String)
        @str = @@string_pool.get(val)
      end

      def iter_next : Variant?
        if @current_idx < @str.size
          idx = @current_idx
          @current_idx += 1
          String.new(@str[idx].to_s)
        end
      end

      def clone : self
        v = self.class.new(@str)
        v.current_idx = @current_idx
        v
      end

      def dup : self
        v = self.class.new(@str)
        v.current_idx = @current_idx
        v
      end
    end

    class DirIterator < Iterator

      @dir_iter : ::Iterator(::String)

      def initialize(path : ::String | Path)
        @dir_iter =  Dir.new(path).each_child
      end

      def clone : self
        self
      end

      def dup : self
        self
      end

      def iter_next : Variant?
        val = @dir_iter.next
        return val.is_a?(::String) ? String.new(val) : nil
      end

    end

    class WalkIterator < Iterator
      @next_dirs : ::Deque(::Array(Path)) = Deque(::Array(Path)).new
      def initialize(path : ::String | Path)
        raise ArgumentError.new("Expected directory to walk") unless Dir.exists?(path)
        @next_dirs << [Path[path]] of Path
      end

      def iter_next : Variant?
        if first = @next_dirs.first?
          path = first.pop
          entries = Dir.children(path)
          dirs, files = entries.partition { |entry| Dir.exists?(path / entry) }
          @next_dirs << dirs.map { |dir| path / dir } unless dirs.empty?
          dirs = Array.new(dirs.map {|e| String.new(e).as(Variant)})
          files = Array.new(files.map {|e| String.new(e).as(Variant)})
          path = String.new(path.to_s)
          @next_dirs.shift if first.empty?
          Array.new([path, dirs, files] of Variant)
        end
      end

      def clone : self
        self
      end

      def dup : self
        self
      end
    end

    SIZE_METHOD = TMBSH.method("size") do
      Int.new(this.@value.size)
    end
    STRIP_METHOD = TMBSH.method("strip") do
      if v = args[1]?
        String.new(this.@value.strip(v.to_s))
      else
        String.new(this.@value.strip)
      end
    end
    RSTRIP_METHOD = TMBSH.method("rstrip") do
      if v = args[1]?
        String.new(this.@value.rstrip(v.to_s))
      else
        String.new(this.@value.rstrip)
      end
    end
    LSTRIP_METHOD = TMBSH.method("lstrip") do
      if v = args[1]?
        String.new(this.@value.lstrip(v.to_s))
      else
        String.new(this.@value.lstrip)
      end
    end
    SPLIT_METHOD = TMBSH.method("split") do
      arr = nil
      if sep = args[1]?
        arr = this.@value.split(sep.to_s)
      else
        arr = this.@value.split
      end
      Array.new(
        arr.map do |item|
          String.new(item).as(Variant)
        end
      )
    end
    CONCAT_METHOD = TMBSH.method("concat") do
      res = this
      args[1..].each do |item|
        res = res.concat(item)
      end
      res
    end
    TO_JSON_METHOD = TMBSH.method("to_json") do
      String.new(this.to_json)
    end

    FROM_JSON_METHOD = TMBSH.method("from_json") do
      this.from_json
    end

    ENTRIES_METHOD = TMBSH.method("entries") do
      this.entries
    end

    ITERDIR_METHOD = TMBSH.method("iterdir") do
      this.iterdir
    end

    REVERSE_METHOD = TMBSH.method("reverse") do
      String.new(this.@value.reverse)
    end

    READ_METHOD = TMBSH.method("read") do
      begin
        contents = ::File.read(this.@value)
        String.new(contents)
      rescue
        NULL
      end
    end

    EXISTS_METHOD = TMBSH.method("exists") do
      ::File.exists?(this.@value) ? TRUE : FALSE
    end

    CHOMP_METHOD = TMBSH.method("chomp") do
      if suf = args[1]?
        String.new(this.@value.chomp(suf.to_s))
      else
        String.new(this.@value.chomp)
      end
    end

    LCHOP_METHOD = TMBSH.method("lchop") do
      if suf = args[1]?
        String.new(this.@value.lchop(suf.to_s))
      else
        String.new(this.@value.lchop)
      end
    end

    COUNT_METHOD = TMBSH.method("count") do
      res = 0
      args[1..].each do |arg|
        target = arg.to_s
        res += this.@value.count(target)
      end
      Float.new(
        res.to_f64
      )
    end

    ENDS_WITH_METHOD = TMBSH.method("ends_with") do
      res = false
      args[1..].each do |arg|
        target = arg.to_s
        if this.@value.ends_with?(target)
          res = true
          break
        end
      end
      res ? TRUE : FALSE
    end

    STARTS_WITH_METHOD = TMBSH.method("starts_with") do
      res = false
      args[1..].each do |arg|
        target = arg.to_s
        if this.@value.starts_with?(target)
          res = true
          break
        end
      end
      res ? TRUE : FALSE
    end

    INDEX_METHOD = TMBSH.method("index") do
      if args.size == 2
        search = args[1].to_s
        idx = this.@value.index(search)
        idx ? Float.new(idx.to_f64) : NULL
      elsif args.size == 3
        search = args[1].to_s
        offset = args[2].to_i
        idx = this.@value.index(search, offset)
        idx ? Float.new(idx.to_f64) : NULL
      else
        raise TypeError.new("Expected 1 or 2 arguments")
      end
    end

    {% for i in ["downcase", "upcase", "titleize", "camelcase", "underscore", "capitalize"] %}
      {{i.id.upcase}}_METHOD = TMBSH.method("{{i.id.upcase}}") do
        raise ArgumentError.new("Expected no arguments") unless args.size == 1
        String.new(this.@value.{{i.id}})
      end
    {% end %}

    PARTITION_METHOD = TMBSH.method("partition") do
      raise ArgumentError.new("Expected one argument to partition") unless args[1]?
      left, sep, right = this.@value.partition(args[1].to_s)
      Array.new(
        [String.new(left), String.new(sep), String.new(right)] of Variant
      )
    end

    RPARTITION_METHOD = TMBSH.method("rpartition") do
      raise ArgumentError.new("Expected one argument to rpartition") unless args[1]?
      left, sep, right = this.@value.rpartition(args[1].to_s)
      Array.new(
        [String.new(left), String.new(sep), String.new(right)] of Variant
      )
    end

    JOIN_METHOD = TMBSH.method("join") do
      path = Path[this.@value]
      args[1..].each do |arg|
        path = path / arg.to_s
      end
      String.new(path.to_s)
    end

    CHARS_METHOD = TMBSH.method("chars") do
      arr = this.@value.chars.map do |char|
        String.new(char.to_s).as(Variant)
      end
      Array.new(arr)
    end

    IS_FILE_METHOD = TMBSH.method("is_file") do
      ::File.file?(this.@value) ? TRUE : FALSE
    end
    IS_DIR_METHOD = TMBSH.method("is_dir") do
      ::Dir.exists?(this.@value) ? TRUE : FALSE
    end

    WALK_METHOD = TMBSH.method("walk") do
      this.walk
    end

    ABSOLUTE_METHOD = TMBSH.method("absolute") do
      this.absolute
    end

    INT_METHOD = TMBSH.method("int") do
      base = (args[1]?.try &.to_i64) || 10
      if res = this.@value.to_i64?(base)
      Int.new(res)
      end
    end

    FLOAT_METHOD = TMBSH.method("float") do
      if res = this.@value.to_f64?
      Float.new(res)
      end
    end

    STAT_METHOD = TMBSH.method("stat") do
      raise ArgumentError.new("Expected no arguments") unless args.size == 1
      this.stat
    end

    ENCODE_METHOD = TMBSH.method("encode") do
      this.encode
    end

    @@methods = {
      # string operations
      "size"         => SIZE_METHOD,
      "concat"       => CONCAT_METHOD,
      "join"         => JOIN_METHOD,
      "strip"        => STRIP_METHOD,
      "rstrip"       => RSTRIP_METHOD,
      "lstrip"       => LSTRIP_METHOD,
      "split"        => SPLIT_METHOD,
      "lower"        => DOWNCASE_METHOD,
      "downcase"     => DOWNCASE_METHOD,
      "upper"        => UPCASE_METHOD,
      "titleize"     => TITLEIZE_METHOD,
      "title"        => TITLEIZE_METHOD,
      "camelcase"    => CAMELCASE_METHOD,
      "camel"        => CAMELCASE_METHOD,
      "underscore"   => UNDERSCORE_METHOD,
      "snakecase"    => UNDERSCORE_METHOD,
      "capitalize"   => CAPITALIZE_METHOD,
      "partition"    => PARTITION_METHOD,
      "rpartition"   => RPARTITION_METHOD,
      "chomp"        => CHOMP_METHOD,
      "lchop"        => LCHOP_METHOD,
      "count"        => COUNT_METHOD,
      "upcase"       => UPCASE_METHOD,
      "starts_with?" => STARTS_WITH_METHOD,
      "ends_with?"   => ENDS_WITH_METHOD,
      "index"        => INDEX_METHOD,
      "chars"        => CHARS_METHOD,
      "entries"      => ENTRIES_METHOD,
      "str"          => STR_METHOD,
      "reverse"      => REVERSE_METHOD,
      "encode"       => ENCODE_METHOD,
      "float"          => FLOAT_METHOD,
      "int"          => INT_METHOD,
      # filesystem methods
      "dir?"         => IS_DIR_METHOD,
      "file?"        => IS_FILE_METHOD,
      "absolute"     => ABSOLUTE_METHOD,
      "abs"          => ABSOLUTE_METHOD,
      "walk"         => WALK_METHOD,
      "stat"         => STAT_METHOD,
      "info"         => STAT_METHOD,
      "read"         => READ_METHOD,
      "exists?"      => EXISTS_METHOD,
      "iterdir"      => ITERDIR_METHOD,

      "to_json"      => TO_JSON_METHOD,
      "from_json"    => FROM_JSON_METHOD,

      "is_a?"        => IS_A_METHOD,
      "iter"         => ITER_METHOD,
      "eq?"          => EQ_METHOD,
      "orelse"       => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"str", "string", "text"}

    @value : ::String

    def initialize
      @value = ""
    end

    def initialize(val : ::String)
      @value = val
    end

    def to_s : ::String
      @value
    end

    def to_f64 : Float64
      @value.to_f64
    end
    #TODO: rework method do support conversion from other bases
    def to_i64 : Int64
      @value.to_i64
    end

    def to_a : ::Array(Variant)
      arr = [] of Variant
      @value.each_char do |char|
        arr << String.new(char.to_s)
      end
      arr
    end

    def dup : String
      self.class.new(@value)
    end

    def clone : String
      self.class.new(@value)
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      if key.is_a?(Range)
        String.new(@value[key.@value])
      else
        String.new(@value[key.to_i].to_s)
      end
    end

    def []?(key : Variant) : Variant
      if val = @value[key.to_i]?
        String.new(val.to_s)
      else
        NULL
      end
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot ::Set on String"
    end

    def call(args : ::Array(Variant)) : Variant
      raise "Cannot call String"
    end

    def ==(other : Variant)
      other.is_a?(String) && @value == other.@value
    end

    def concat(other : Variant) : String
      other = other.to_shs
      String.new(@value + other.@value)
    end

    def to_json : ::String
      "\"#{@value}\""
    end

    def to_json(builder : JSON::Builder)
      builder.string(@value)
    end

    def from_json : Variant
      json = JSON.parse(@value)
      TMBSH.variant_from_json(json)
    end

    def entries : Array
      raise "Directory #{@value} doesn't exist" unless Dir.exists?(@value)
      Array.new(
        Dir.children(@value).map do |item|
          String.new(item).as(Variant)
        end
      )
    end

    def iter_init : Iterator
      StringIterator.new(@value)
    end

    def truthy? : ::Bool
      !@value.empty?
    end

    def walk : Iterator
      WalkIterator.new(@value)
    end

    def absolute : String
      String.new(Path[@value].expand.to_s)
    end

    def stat : Dictionary?
      info = ::File.info? @value
      puts @value
      return unless info
      info_hash = {
        String.new("directory?") => info.directory? ? TRUE : FALSE,
        String.new("file?") => info.file? ? TRUE : FALSE,
        String.new("symlink?") => info.symlink? ? TRUE : FALSE,
        String.new("flags") => Int.new(info.flags.to_i64),
        String.new("group_id") => String.new(info.group_id),
        String.new("owner_id") => String.new(info.owner_id),
        String.new("modification_time") => Int.new(info.modification_time.to_unix),
        String.new("modification_time_ns") => Int.new(info.modification_time.nanosecond),
        String.new("permissions") => Int.new(info.permissions.to_i64),
        String.new("size")      => Int.new(info.size),
      } of Variant => Variant
      Dictionary.new(info_hash)
    end

    def encode : Array
      Array.new(@value.to_slice.to_a.map { |v| Int.new(v).as(Variant)})
    end

    def iterdir
      if Dir.exists?(@value)
        DirIterator.new(@value)
      end
    end
  end

  class Dictionary < Variant
    class DictionaryIterator < Iterator
      @hash : ::Hash(Variant, Variant)
      @keys : ::Array(Variant)
      @current_idx : Int32 = 0
      property current_idx

      def initialize(val : ::Hash(Variant, Variant))
        @hash = val
        @keys = val.keys
      end

      def iter_next : Variant?
        if @current_idx < @keys.size
          key = @keys[@current_idx]
          @current_idx += 1
          arr = [key, @hash[key]] of Variant
          Array.new(arr)
        end
      end

      def clone : self
        v = self.class.new(@hash.dup)
        v.current_idx = @current_idx
        v
      end

      def dup : self
        v = self.class.new(@hash)
        v.current_idx = @current_idx
        v
      end
    end

    @value : Hash(Variant, Variant)

    KEYS_METHOD = TMBSH.method("keys") do
      Array.new(this.@value.keys)
    end

    VALUES_METHOD = TMBSH.method("values") do
      Array.new(this.@value.values)
    end

    TO_JSON_METHOD = TMBSH.method("to_json") do
      String.new(this.to_json)
    end

    INVERT_METHOD = TMBSH.method("invert") do
      Dictionary.new(this.@value.dup.invert)
    end

    PAIRS_METHOD = TMBSH.method("pairs") do
      connection = args[1]? || ""
      prefix = args[2]? || ""
      postfix = args[3]? || ""

      connection = connection.to_s
      prefix = prefix.to_s
      postfix = postfix.to_s
      Array.new(
        this.pairs(connection, prefix, postfix).map do |item|
          String.new(item).as(Variant)
        end
      )
    end

    FETCH_METHOD = TMBSH.method("fetch") do
      raise "Expected one or two arguments" if args.size > 3 || args.size < 2
      key = args[1]
      if alt = args[2]?
        this[key]? || alt
      else
        this[key]?
      end
    end

    HAS_KEY_METHOD = TMBSH.method("has_key") do
      raise "Expected one argument" unless args.size == 1
      this.@value.has_key?(args[1]) ? TRUE : FALSE
    end

    HAS_VALUE_METHOD = TMBSH.method("has_value") do
      raise "Expected one argument" unless args.size == 1
      this.@value.has_value?(args[1]) ? TRUE : FALSE
    end

    @@methods = {
      "fetch"      => FETCH_METHOD,
      "keys"       => KEYS_METHOD,
      "values"     => VALUES_METHOD,
      "has_key?"   => HAS_KEY_METHOD,
      "has_value?" => HAS_VALUE_METHOD,
      "str"        => STR_METHOD,
      "to_json"    => TO_JSON_METHOD,
      "invert"     => INVERT_METHOD,
      "pairs"      => PAIRS_METHOD,
      "iter"       => ITER_METHOD,

      "is_a?"      => IS_A_METHOD,
      "eq?"        => EQ_METHOD,
      "orelse"     => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"dict", "hash", "dictionary"}

    def initialize
      @value = {} of Variant => Variant
    end

    def initialize(from : Hash(Variant, Variant))
      @value = from
    end

    def dup : Dictionary
      self.class.new(@value.dup)
    end

    def clone : Dictionary
      self.class.new(@value.clone)
    end

    def to_s : ::String
      ::String.build do |io|
        io << "{ "
        @value.each do |k, v|
          io << k.to_s
          io << " : "
          io << v.to_s
          io << ' '
        end
        io << "}"
      end
    end

    def to_a : ::Array(Variant)
      arr = [] of Variant
      @value.each do |k, v|
        arr << Array.new([k, v] of Variant)
      end
      arr
    end

    def to_f64 : Float64
      raise "Cannot convert Dictionary to Float"
    end

    def to_i64 : Int64
      raise "Cannot convert Dictionary to Int"
    end

    def pairs(connection : ::String, prefix : ::String = "", postfix : ::String = "") : ::Array(::String)
      arr = [] of ::String
      @value.each do |k, v|
        arr << ::String.build do |io|
          io << prefix
          io << k.to_s
          io << connection
          io << v.to_s
          io << postfix
        end
      end
      arr
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      @value[key]
    end

    def []?(key : Variant) : Variant
      @value[key]? || NULL
    end

    def []=(key : Variant, value : Variant) : Variant
      @value[key] = value
    end

    def call(args : ::Array(Variant)) : Variant
      raise "Cannot call Dictionary"
    end

    def ==(other : Variant)
      other.is_a?(Dictionary) && @value == other.@value
    end

    def to_json : ::String
      ::String.build do |io|
        io << '{'
        @value.keys[0...-1].each do |k|
          io << k.to_json
          io << ':'
          io << @value[k].to_json
          io << ','
        end
        k = @value.keys[-1]
        io << k.to_json
        io << ':'
        io << @value[k].to_json
        io << '}'
      end
    end

    def to_json(builder : JSON::Builder)
      builder.object do
        @value.each do |k, v|
          builder.field(k.to_shs, v)
        end
      end
    end

    def iter_init : Iterator
      DictionaryIterator.new(@value)
    end

    def truthy? : ::Bool
      !@value.empty?
    end
  end

  NULL = Null.new

  class Null < Variant
    RANGE_METHOD = TMBSH.method("range") do
      Range.new(nil, args[1]?.try &.to_i64, false)
    end

    ERANGE_METHOD = TMBSH.method("erange") do
      Range.new(nil, args[1]?.try &.to_i64, true)
    end
    @@methods = {
      "range"  => RANGE_METHOD,
      "erange" => ERANGE_METHOD,
      "r"      => RANGE_METHOD,
      "er"     => ERANGE_METHOD,

      "is_a?"  => IS_A_METHOD,
      "eq?"    => EQ_METHOD,
      "str"    => STR_METHOD,
      "orelse" => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"null", "nil", "none"}

    def initialize
    end

    def dup : Null
      self
    end

    def clone : Null
      self
    end

    def hash : UInt64
      0_u64
    end

    def to_shnum : Float
      Float.new
    end

    def to_sharr : Array
      Array.new
    end

    def call(args : ::Array(Variant)) : Variant
      raise "Cannot call Null"
    end

    def to_s : ::String
      "Null"
    end

    def to_f64 : Float64
      0.0
    end

    def to_i64 : Int64
      0_i64
    end

    def to_a : ::Array(Variant)
      [] of Variant
    end

    def [](key : Variant) : Variant
      raise "Cannot access key on Null"
    end

    def []?(key : Variant) : Variant
      raise "Cannot access key on Null"
    end

    def []=(key : Variant, value : Variant) : Variant
      raise "Cannot access key on Null"
    end

    def ==(other : Variant)
      false
    end

    def to_json : ::String
      "null"
    end

    def to_json(builder : JSON::Builder)
      builder.null
    end

    def iter_init : Iterator
      raise "Cannot iterate over Null"
    end

    def truthy? : ::Bool
      false
    end
  end

  FALSE = Bool.new(false)
  TRUE  = Bool.new(true)

  class Bool < Variant
    @value : ::Bool

    OR_METHOD = TMBSH.method("or") do
      if this.truthy?
        args[1]? || NULL
      else
        this
      end
    end

    AND_METHOD = TMBSH.method("and") do
      if this.truthy?
        this
      else
        args[1]? || NULL
      end
    end

    STR_METHOD = TMBSH.method("str") do
      String.new(this.@value ? "True" : "False")
    end

    @@methods = {
      "or"     => OR_METHOD,
      "and"    => AND_METHOD,
      "str"    => STR_METHOD,

      "is_a?"  => IS_A_METHOD,
      "eq?"    => EQ_METHOD,
      "orelse" => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"bool", "boolean", "the universal"}

    def initialize(bool : ::Bool)
      @value = bool
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      raise "Cannot do access on Bool"
    end

    def []?(key : Variant) : Variant
      raise "Cannot do access on Bool"
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot ::Set on Bool"
    end

    def to_s : ::String
      @value ? "0" : "1"
    end

    def to_f64 : Float64
      @value ? 0.0 : 1.0
    end

    def to_i64 : Int64
      @value ? 0_i64 : 0_i64
    end

    def to_a : ::Array(Variant)
      raise "Cannot convert Bool to Array"
    end

    def dup : Bool
      self
    end

    def clone : Bool
      self
    end

    def call(args : ::Array(Variant)) : Variant
      raise "Cannot call a Bool"
    end

    def ==(other : Variant)
      other.is_a?(Bool) && @value == other.@value
    end

    def to_json : ::String
      to_s
    end

    def to_json(builder : JSON::Builder)
      builder.bool(@value)
    end

    def iter_init : Iterator
      raise "Cannot iterate over Bool"
    end

    def truthy? : ::Bool
      @value
    end
  end

  class Function < Variant
    @proc : Proc(::Array(Variant), Variant?)? = nil
    property name : ::String?
    property parent_class : ::String?
    @binded_args : ::Array(Variant)

    BIND_METHOD = TMBSH.method("bind") do
      binded = args.to_a[1..]
      this.bind(binded)
    end

    @@methods = {
      "is_a?"  => IS_A_METHOD,
      "eq?"    => EQ_METHOD,
      "str"    => STR_METHOD,
      "bind"   => BIND_METHOD,

      "orelse" => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"func", "function"}

    def initialize
      @binded_args = [] of Variant
    end

    def initialize(proc : Proc(::Array(Variant), Variant?)?, binded_args : ::Array(Variant))
      @proc = proc
      @binded_args = binded_args
    end

    def initialize(proc : Proc(::Array(Variant), Variant?)?)
      @proc = proc
      @binded_args = [] of Variant
    end

    def initialize(@parent_class : ::String, @name : ::String, proc : Proc(::Array(Variant), Variant?)?)
      @proc = proc
      @binded_args = [] of Variant
    end

    def hash : UInt64
      @proc.hash
    end

    def [](key : Variant) : Variant
      raise "Cannot do access on Function"
    end

    def []?(key : Variant) : Variant
      raise "Cannot do access on Function"
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot ::Set on Function"
    end

    def to_s : ::String
      if parent_class = @parent_class
        "<Method name: #{@name} on class: #{parent_class}>"
      else
        if name = @name
          "<Function name: #{@name}>"
        else
          "<Anonymus Function id: #{object_id}>"
        end
      end
    end

    def to_f64 : Float64
      raise "Cannot convert Function to Float"
    end

    def to_i64 : Int64
      raise "Cannot convert Function to Int"
    end

    def to_a : ::Array(Variant)
      raise "Cannot convert Function to Array"
    end

    def dup : Function
      self.class.new(@proc, @binded_args.dup)
    end

    def clone : Function
      self.class.new(@proc, @binded_args.clone)
    end

    def call(args : ::Array(Variant)) : Variant
      begin
      @proc.try &.call(@binded_args.empty? ? args : @binded_args + args) || TMBSH::NULL
      rescue e : Exception
        raise e.class.new(e.message.to_s + " (When calling #{to_s})")
      end
    end

    def ==(other : Variant)
      other.is_a?(Function) && @proc == other.@proc && @binded_args == other.@binded_args
    end

    def to_json : ::String
      raise "Cannot convert function to JSON"
    end

    def to_json(builder : JSON::Builder)
      raise "Cannot convert function to JSON"
    end

    def iter_init : Iterator
      raise "Cannot iterate over Function"
    end

    def truthy? : ::Bool
      true
    end

    def bind!(args : ::Array(Variant)) : Nil
      @binded_args.concat(args)
    end

    def bind(args : ::Array(Variant)) : Function
      fn = dup
      fn.bind!(args)
      fn
    end
  end

  class File < Variant
    @file : ::File
    @path : ::String

    WRITE_METHOD = TMBSH.method("write") do
      args[1..].each do |arg|
        @file.write(arg)
      end
      this
    end

    @@methods = {

      "str"    => STR_METHOD,

      "is_a?"  => IS_A_METHOD,
      "eq?"    => EQ_METHOD,
      "orelse" => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"file", "descriptor"}

    def initialize(filename : ::String | Path, mode : ::String = "r")
      @path = filename.to_s
      @file = ::File.open(filename, mode)
    end

    def hash : UInt64
      raise "Do not use File as keys"
    end

    def [](key : Variant) : Variant
      raise "Cannot do access on File"
    end

    def []?(key : Variant) : Variant
      raise "Cannot do access on File"
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot set key on File"
    end

    def to_s : ::String
      @path
    end

    def to_f64 : Float64
      raise "Cannot convert File to Float"
    end
    def to_i64 : Int64
      raise "Cannot convert File to Int"
    end

    def to_a : ::Array(Variant)
      raise "Cannot convert File to Array"
    end

    def dup : File
      raise "Cannot dup File"
    end

    def clone : File
      raise "Cannot clone File"
    end

    def call(args : ::Array(Variant)) : Variant
      raise "Cannot call File"
    end

    def ==(other : Variant)
      other.is_a?(File) && @path == other.@path
    end

    def to_json : ::String
      raise "Cannot convert File to JSON"
    end

    def to_json(builder : JSON::Builder)
      raise "Cannot convert File to JSON"
    end

    def iter_init : Iterator
      raise "WIP"
    end

    def truthy? : ::Bool
      true
    end

    def write(var : Variant)
      str = var.to_s
      @file.print(str)
    end
  end

  class ExitStatus < Variant
    @value : Int32

    FLOAT_METHOD = TMBSH.method("float") do
      Float.new(this.@value)
    end
    INT_METHOD = TMBSH.method("int") do
      Float.new(this.@value)
    end

    @@methods = {
      "float"    => FLOAT_METHOD,
      "int"    => INT_METHOD,
      "str"    => STR_METHOD,

      "is_a?"  => IS_A_METHOD,
      "eq?"    => EQ_METHOD,
      "orelse" => ORELSE_METHOD,
      "truthy?" => TRUTHY_METHOD,
      "dup"   => DUP_METHOD,
      "clone" => CLONE_METHOD,
    } of ::String => Function

    @@type_aliases = ::Set{"exit_status", "status"}

    def initialize(status : Int32)
      @value = status
    end

    def to_s : ::String
      @value.to_s
    end

    def to_f64 : Float64
      @value.to_f64
    end

    def to_i64 : Int64
      @value.to_i64
    end

    def to_a : ::Array(Variant)
      raise "Cannot convert Status to Array"
    end

    def dup : ExitStatus
      self
    end

    def clone : ExitStatus
      self
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      raise "Cannot do access on Status"
    end

    def []?(key : Variant) : Variant
      raise "Cannot do access on Status"
    end

    def []=(key : Variant, value : Variant)
      raise "Cannot ::Set on Status"
    end

    def call(args : ::Array(Variant)) : Variant
      raise "Cannot call Status"
    end

    def ==(other : Variant)
      return @value == other.@value if other.is_a?(ExitStatus)
      begin
        other_status = other.to_i64
        @value == other_status
      rescue
        false
      end
    end

    def to_json : ::String
      @value.to_json
    end

    def to_json(builder : JSON::Builder)
      @value.to_json(builder)
    end

    def iter_init : Iterator
      raise "Cannot iterate over status"
    end

    def truthy? : ::Bool
      @value == 0
    end
  end
end
