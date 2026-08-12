require "json"
require "./exceptions"
require "./context"

module TMBSH
  macro require_arguments(func_name, amount, is_method = false)
    {% if amount.is_a? NumberLiteral %}
    raise ArgumentError.new("{{ is_method ? "method".id : "function".id }} {{func_name.id}} requires {{amount}} argument{{"s".id unless amount == 1}}") unless args.size == {{amount + (is_method ? 1 : 0)}}
    {% elsif amount.is_a? RangeLiteral && amount.begin.is_a?(NilLiteral) && amount.end.is_a?(NumberLiteral) %}
    raise ArgumentError.new("{{ is_method ? "method".id : "function".id }} {{func_name.id}} requires 0..{{".".id if amount.excludes_end?}}{{amount.end}} arguments") if \
    args.size {{amount.excludes_end? ? ">=".id : ">".id}} {{amount.end + (is_method ? 1 : 0)}}
    {% elsif amount.is_a? RangeLiteral && amount.begin.is_a?(NumberLiteral) && amount.end.is_a?(NumberLiteral)%}
    raise ArgumentError.new("{{ is_method ? "method".id : "function".id }} {{func_name.id}} requires {{amount.begin}}..{{".".id if amount.excludes_end?}}{{amount.end}} arguments") if \
    args.size < {{amount.begin + (is_method ? 1 : 0)}} || args.size {{amount.excludes_end? ? ">=".id : ">".id}} {{amount.end + (is_method ? 1 : 0)}}
    {% elsif amount.is_a? RangeLiteral && amount.begin.is_a?(NumberLiteral) && amount.end.is_a?(NilLiteral)%}
    {% unless amount.begin == (is_method ? 1 : 0)%}
    raise ArgumentError.new("{{ is_method ? "method".id : "function".id }} {{func_name.id}} requires at least {{amount.begin}} argument{{"s".id unless amount.end == 1}}") if \
    args.size < {{amount.begin + (is_method ? 1 : 0)}}
    {% end %}
    {% end %}
  end

  macro abstract_method(name, arg_amount, &body)
    Function.new(self.to_s.lchop("TMBSH::"), {{name}}, ->(context : Interpreter::Context, args : ::Array(Variant)) : Variant? {
    TMBSH.require_arguments({{name}}, {{arg_amount}}, true)
    this = args[0]
    {{body.body}}
    })
  end

  macro method(name, arg_amount, &body)
    Function.new(self.to_s.lchop("TMBSH::"), {{name}}, ->(context : Interpreter::Context, args : ::Array(Variant)) : Variant? {
    TMBSH.require_arguments({{name}}, {{arg_amount}}, true)
    this = args[0] # .as(self)
    raise "Wrong self" unless this.is_a?(self)
    {{body.body}}
    })
  end

  macro generate_methods(methods)
    {
      {% for k, v in methods %}
        {{k}} => {{v}},
      {% end %}
      "truthy?" => TRUTHY_METHOD,
      "is_a?"   => IS_A_METHOD,
      "eq"      => EQ_METHOD,
      "neq"     => NEQ_METHOD,
      "or_else"  => ORELSE_METHOD,
      "if"      => IF_METHOD,
      "if_else"  => IF_ELSE_METHOD,
      "dup"     => DUP_METHOD,
      "clone"   => CLONE_METHOD,
      "str"     => STR_METHOD,
      "iter"    => ITER_METHOD,
      "to_json" => TO_JSON_METHOD,
    } of ::String => Function
  end



  protected def self.variant_from_json(json : JSON::Any) : Variant
    raw = json.raw
    case raw
    in ::String  then String.new(raw)
    in ::Int64   then Int.new(raw)
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
      {% elsif val.is_a?(::Array) %}
        Array.new(val.map { |item| variant(val)})
      {% end %}
    end

  abstract class Variant
    @@methods : Hash(::String, Function) = {} of ::String => Function
    @@unstable_methods : ::Set(::String) = ::Set(::String).new # means methods that can vary in result even if the value is consistent
    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    ITER_METHOD = TMBSH.abstract_method("iter", 0) do
      this.iter_init(context)
    end

    CLONE_METHOD = TMBSH.abstract_method("clone", 0) do
      this.clone
    end

    DUP_METHOD = TMBSH.abstract_method("dup", 0) do
      this.dup
    end

    IS_A_METHOD = TMBSH.abstract_method("is_a", 1) do
      this.variant_type?(args[1]?.to_s) ? TRUE : FALSE
    end

    EQ_METHOD = TMBSH.abstract_method("eq", 1) do
      this == (args[1] || NULL) ? TRUE : FALSE
    end

    NEQ_METHOD = TMBSH.abstract_method("neq", 1) do
      this == (args[1] || NULL) ? FALSE : TRUE
    end

    STR_METHOD = TMBSH.abstract_method("str", 0) do
      String.new(this.to_s)
    end

    TO_JSON_METHOD = TMBSH.abstract_method("to_json", 0) do
      String.new(this.to_json)
    end

    ORELSE_METHOD = TMBSH.abstract_method("or_else", 1) do
      if this.is_a?(Null)
        args[1]
      else
        this
      end
    end

    IF_METHOD = TMBSH.abstract_method("if", 1) do
      if args[1].truthy?
        this
      else
        NULL
      end
    end

    IF_ELSE_METHOD = TMBSH.abstract_method("ifelse", 2) do
      if args[1].truthy?
        this
      else
        args[2]
      end
    end

    TRUTHY_METHOD = TMBSH.abstract_method("truthy?", 0) do
      this.truthy? ? TRUE : FALSE
    end

    abstract def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
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
    def to_json_object_key
      to_s
    end
    abstract def hash : UInt64
    abstract def clone
    abstract def dup
    abstract def [](key : Variant) : Variant
    abstract def []?(key : Variant) : Variant
    abstract def []=(key : Variant, value : Variant)

    abstract def ==(other : Variant)

    abstract def iter_init(context : Interpreter::Context) : Iterator

    abstract def truthy? : ::Bool

    # {% if flag?(:method_hash_caching) %}
    def get_method(method_hash : UInt64) : Function?
      @@methods_hash_cache[method_hash]?
    end

    # {% end %}

    def get_method(name : ::String)
      if method = @@methods[name]?
        # {% if flag?(:method_hash_caching) %}
        @@methods_hash_cache[name.hash] = method
        # {% end %}
        method
      else
        raise MethodDoesNotExist.new("Method #{name} doesn't exist on #{self.class}")
      end
    end

    def get_attribute(name : ::String) : Variant
      raise TypeError.new("#{self.class} is attributeless")
    end

    def set_attribute(name : ::String, val : Variant) : Variant
      raise TypeError.new("#{self.class} is attributeless")
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

      def iter_next(context : Interpreter::Context) : Variant?
        val = @iterator.iter_next(context)
        return unless val
        @func.call(context, [val] of Variant)
      end
    end

    class SelectIterator < Iterator
      include IteratorBoilerplate

      def iter_next(context : Interpreter::Context) : Variant?
        while true
          val = @iterator.iter_next(context)
          return unless val
          if @func.call(context, [val] of Variant).truthy?
            return val
          end
        end
      end
    end

    class RejectIterator < Iterator
      include IteratorBoilerplate

      def iter_next(context : Interpreter::Context) : Variant?
        while true
          val = @iterator.iter_next(context)
          return unless val
          unless @func.call(context, [val] of Variant).truthy?
            return val
          end
        end
      end
    end

    NEXT_METHOD = TMBSH.method("next", 0) do
      this.iter_next(context) || NULL
    end
    TO_A_METHOD = TMBSH.method("to_a", 0) do
      this.to_sharr(context)
    end
    {% for itertype in ["map", "select", "reject"] %}
      {{itertype.id.upcase}}_METHOD = TMBSH.method({{itertype}}, 1) do
        func = args[1]
        raise ArgumentError.new("Expected first argument to be a Function") unless func.is_a?(Function)
        this.{{itertype.id}}(context, func)
      end
    {% end %}

    FOLD_METHOD = TMBSH.method("fold", 2) do
      into = args[1]
      func = args[2]
      raise ArgumentError.new("Expected second argument to be a Function") unless func.is_a?(Function)
      this.fold(context, into, func)
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "next"   => NEXT_METHOD,
      "to_a"   => TO_A_METHOD,
      "map"    => MAP_METHOD,
      "select" => SELECT_METHOD,
      "reject" => REJECT_METHOD,
      "fold"   => FOLD_METHOD,
    })

    @@type_aliases = ::Set{"iter", "iterator"}

    abstract def iter_next(context : Interpreter::Context) : Variant?

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      iter_next(context) || NULL
    end

    def to_f64 : Float64
      raise TypeError.new("Cannot convert iterator to Float")
    end

    def to_i64 : Int64
      raise TypeError.new("Cannot convert iterator to Int")
    end

    def to_s : ::String
      "<#{self.class.to_s.lchop("TMBSH::")} iterator>"
    end

    def to_a : ::Array(Variant)
      raise "Internal error, iterator collecting functions must have context passed to them"
    end

    def to_a(context : Interpreter::Context) : ::Array(Variant)
      arr = [] of Variant
      while val = iter_next(context)
        arr << val
      end
      arr
    end

    def to_sharr(context : Interpreter::Context) : Array
      Array.new(to_a(context))
    end

    def to_json : ::String
      raise TypeError.new("Cannot convert Iterator to JSON")
    end

    def to_json(builder : JSON::Builder)
      raise TypeError.new("Cannot convert Iterator to JSON")
    end

    def hash : UInt64
      raise TypeError.new("Do not use Iterator as key")
    end

    def [](key : Variant) : Variant
      raise TypeError.new("Cannot do key access on Iterator (Try converting it to array first)")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot do key access on Iterator (Try converting it to array first)")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot do key assignment on Iterator")
    end

    def iter_init(context : Interpreter::Context) : Iterator
      self
    end

    def each(context : Interpreter::Context, & : Variant ->)
      while val = iter_next(context)
        yield val
      end
    end

    def ==(other : Variant) : ::Bool
      same?(other)
    end

    def truthy? : ::Bool
      true
    end

    {% for itertype in ["map", "select", "reject"] %}
      def {{itertype.id}}(context : Interpreter::Context, func : Function)
        {{itertype.id.titleize}}Iterator.new(self, func)
      end
    {% end %}

    def fold(context : Interpreter::Context, into : Variant, func : Function)
      each(context) do |i|
        func.call(context, [into, i] of Variant)
      end
      into
    end
  end

  macro num_type_def(name, num_type, conversion)
  class {{name}} < Variant
    class NumberIterator < Iterator
      @current : {{num_type}} = {{num_type}}.zero
      @target : {{num_type}}
      property current
      property target

      def initialize(val : {{num_type}})
        @target = val
      end

      def iter_next(context : Interpreter::Context) : Variant?
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

    ADD_METHOD = TMBSH.method("add", 0..) do
      num = this.@value
      args.each(within: 1..) do |arg|
        num += arg.{{conversion}}
      end
      {{name}}.new(num)
    end

    SUB_METHOD = TMBSH.method("sub", 0..) do
      num = this.@value
      args.each(within: 1..) do |arg|
        num -= arg.{{conversion}}
      end
      {{name}}.new(num)
    end

    MUL_METHOD = TMBSH.method("mul", 0..) do
      num = this.@value
      args.each(within: 1..) do |arg|
        num *= arg.{{conversion}}
      end
      {{name}}.new(num)
    end

    DIV_METHOD = TMBSH.method("div", 0..) do
      num = this.@value
      args.each(within: 1..) do |arg|
        num /= arg.{{conversion}}
      end
      {{name}}.new(num)
    end

    AND_METHOD = TMBSH.method("and", 0..) do
      res = this.@value.to_i64
      args.each(within: 1..) do |arg|
        res &= arg.to_i
      end
      Int.new(res)
    end
    OR_METHOD = TMBSH.method("or", 0..) do
      res = this.@value.to_i64
      args.each(within: 1..) do |arg|
        res |= arg.to_i
      end
      Int.new(res)
    end

    XOR_METHOD = TMBSH.method("xor", 0..) do
      res = this.@value.to_i64
      args.each(within: 1..) do |arg|
        res ^= arg.to_i
      end
      Int.new(res)
    end

    FDIV_METHOD = TMBSH.method("fdiv", 0..) do
      num = this.@value
      args.each(within: 1..) do |arg|
        num //= arg.{{conversion}}
      end
      {{name}}.new(num)
    end
    POW_METHOD = TMBSH.method("pow", 0..) do
      num = this.@value
      args.each(within: 1..) do |arg|
        num **= arg.{{conversion}}
      end
      {{name}}.new(num)
    end
    # IS_A_METHOD = TMBSH.method("is_a") do
    #   this.variant_type?(args[1]?.to_s) ? TRUE : FALSE
    # end
    FLOAT_METHOD = TMBSH.method("float", 0) do
      Float.new(this.to_f64)
    end
    INT_METHOD = TMBSH.method("int", 0) do
      Int.new(this.to_i64)
    end
    TO_METHOD = TMBSH.method("to", 0..1) do
      if dest = args[1]?
        this.to(dest, args[2]?)
      end
    end

    TOE_METHOD = TMBSH.method("toe", 0..1) do
      if dest = args[1]?
        this.toe(dest, args[2]?)
      end
    end

    GT_METHOD = TMBSH.method("gt", 1) do
      this.@value > args[1].{{conversion}} ? TRUE : FALSE
    end

    LT_METHOD = TMBSH.method("lt", 1) do
      this.@value < args[1].{{conversion}} ? TRUE : FALSE
    end

    GTE_METHOD = TMBSH.method("gte", 1) do
      this.@value >= args[1].{{conversion}} ? TRUE : FALSE
    end

    LTE_METHOD = TMBSH.method("lte", 1) do
      this.@value <= args[1].{{conversion}} ? TRUE : FALSE
    end

    RANGE_METHOD = TMBSH.method("range", 0..1) do
      Range.new(this.@value.to_i64, args[1]?.try &.to_i64, false)
    end

    ERANGE_METHOD = TMBSH.method("erange", 0..1) do
      Range.new(this.@value.to_i64, args[1]?.try &.to_i64, true)
    end

    HUMANIZE_METHOD = TMBSH.method("humanize", 0) do
      String.new(this.@value.humanize)
    end

    {% for i in ["round", "ceil", "floor", "abs", "abs2"] %}
      {{i.id.upcase}}_METHOD = TMBSH.method("{{i.id}}", 0) do
        {{name}}.new(this.@value.{{i.id}})
      end
    {% end %}

    SIGNIFICANT_METHOD = TMBSH.method("significant", 1..2) do
      digits = args[1].to_i64
      base = args[2]? ? args[2].to_i64 : 10
      {{name}}.new(this.@value.significant(digits, base))
    end

    STR_METHOD = TMBSH.method("str", 0..1) do
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
    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
@@methods = TMBSH.generate_methods({
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
    })

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
      raise TypeError.new("Cannot do access on {{name}}")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot do access on {{name}}")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot ::Set on {{name}}")
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call {{name}}")
    end

    def ==(other : Variant)
      other.is_a?({{name}}) && @value == other.@value
    end

    def to_json : ::String
      @value.to_json
    end

    def to_json(builder : JSON::Builder)
      @value.to_json(builder)
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

    def iter_init(context : Interpreter::Context) : Iterator
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

      def iter_next(context : Interpreter::Context) : Variant?
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

    TO_A_METHOD = TMBSH.method("to_a", 0) do
      this.to_sharr
    end

    BEGIN_METHOD = TMBSH.method("begin", 0) do
      val = this.@value.begin
      if val
        Float.new(val.to_f64)
      else
        NULL
      end
    end

    END_METHOD = TMBSH.method("end", 0) do
      val = this.@value.end
      if val
        Float.new(val.to_f64)
      else
        NULL
      end
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "begin" => BEGIN_METHOD,
      "end"   => END_METHOD,
      "to_a"  => TO_A_METHOD,
    })

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
      raise TypeError.new("Cannot do access on Range")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot do access on Range")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot ::Set on Range")
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call Range")
    end

    def ==(other : Variant)
      other.is_a?(Range) && @value == other.@value
    end

    def to_json : ::String
      raise TypeError.new("Cannot convert Range to json")
    end

    def to_json(builder : JSON::Builder)
      raise TypeError.new("Cannot convert Range to json")
    end

    def iter_init(context : Interpreter::Context) : Iterator
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

      def iter_next(context : Interpreter::Context) : Variant?
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
    SIZE_METHOD = TMBSH.method("size", 0) do
      Int.new(this.@value.size)
    end
    APPEND_METHOD = TMBSH.method("append", 1..) do
      args.each(within: 1..) do |item|
        this << item
      end
      this
    end

    POP_METHOD = TMBSH.method("pop", 0) do
      this.@value.pop?
    end

    EMPTY_METHOD = TMBSH.method("empty?", 0) do
      this.@value.empty? ? TRUE : FALSE
    end

    INDEX_METHOD = TMBSH.method("index", 1..2) do
      obj = args[1]
      if offset = args[2]?
        offset = offset.to_i
        this.@value.index(obj, offset)
      else
        this.@value.index(obj)
      end
    end

    DELETE_METHOD = TMBSH.method("delete", 1..) do
      args.each(within: 1..) do |item|
        this.delete item
      end
      this
    end
    CONCAT_METHOD = TMBSH.method("concat", 1..) do
      copy = this.dup
      args.each(within: 1..) do |item|
        arr = item.to_a
        copy.@value.concat(arr)
      end
      copy
    end
    REVERSE_METHOD = TMBSH.method("reverse", 0) do
      Array.new(this.@value.reverse)
    end
    CLEAR_METHOD = TMBSH.method("clear", 0) do
      this.@value.clear
      this
    end

    {% for i in ["sum", "sort", "sort_num"] %}
    {{i.id.upcase}}_METHOD = TMBSH.method("{{i.id}}", 0) do
      this.{{i.id}}
    end
    {% end %}

    SHIFT_METHOD = TMBSH.method("shift", 0) do
      this.@value.shift
    end
    UNSHIFT_METHOD = TMBSH.method("unshift", 1..) do
      args.each(within: 1..) do |arg|
        this.@value.unshift arg
      end
      this
    end

    FETCH_METHOD = TMBSH.method("fetch", 1..2) do
      key = args[1]
      if alt = args[2]?
        this[key]? || alt
      else
        this[key]?
      end
    end

    {% for name in ["map", "select", "reject"] %}
        {{name.id.upcase}}_METHOD = TMBSH.method("{{name.id}}", 1) do
          fn = args[1]
          raise ArgumentError.new("First argument to {{name.id}} must be a function") unless fn.is_a?(Function)
          this.{{name.id}}(context, fn)
        end
        {{name.id.upcase}}_IN_PLACE_METHOD = TMBSH.method("{{name.id}}_in_place", 1) do
          fn = args[1]
          raise ArgumentError.new("First argument to {{name.id}} must be a function") unless fn.is_a?(Function)
          this.{{name.id}}!(context, fn)
        end
      {% end %}
    REDUCE_METHOD = TMBSH.method("reduce", 1..2) do
      if args.size == 3
        initial_value = args[1]
        fn = args[2]
        raise ArgumentError.new("Expected argument 2 to be a Function") unless fn.is_a?(Function)
        this.reduce(context, args[1], fn)
      elsif args.size == 2
        fn = args[1]
        raise ArgumentError.new("Expected argument 1 to be a Function") unless fn.is_a?(Function)
        this.reduce(context, fn)
      end
    end

    FIND_METHOD = TMBSH.method("find", 1..2) do
      if args.size == 3
        if_none = args[2]
        fn = args[1]
        raise ArgumentError.new("Expected argument 2 to be a Function") unless fn.is_a?(Function)
        this.find(context, fn, if_none)
      elsif args.size == 2
        fn = args[1]
        raise ArgumentError.new("Expected argument 1 to be a Function") unless fn.is_a?(Function)
        this.find(context, fn)
      end
    end
    RESIZE_METHOD = TMBSH.method("resize", 1) do
      num = args[1]
      new_size = num.to_i
      this.resize(new_size)
      this
    end

    JOIN_METHOD = TMBSH.method("join", 0..1) do
      sep = args[1]?.try &.to_s || ""
      String.new(this.join(sep))
    end

    INCLUDES_METHOD = TMBSH.method("includes", 1) do
      this.@value.includes?(args[1]) ? TRUE : FALSE
    end

    PARTITION_METHOD = TMBSH.method("partition", 1) do
      fn = args[1]
      raise ArgumentError.new("Expected first argument to be a Function") unless fn.is_a?(Function)
      this.partition(context, fn)
    end

    DECODE_METHOD = TMBSH.method("decode", 0) do
      this.decode
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "size"      => SIZE_METHOD,
      "append"    => APPEND_METHOD,
      "fetch"     => FETCH_METHOD,
      "pop"       => POP_METHOD,
      "ap"        => APPEND_METHOD,
      "delete"    => DELETE_METHOD,
      "del"       => DELETE_METHOD,
      "concat"    => CONCAT_METHOD,
      "join"      => JOIN_METHOD,
      "reverse"   => REVERSE_METHOD,
      "clear"     => CLEAR_METHOD,
      "sum"       => SUM_METHOD,
      "map"       => MAP_METHOD,
      "map!"      => MAP_IN_PLACE_METHOD,
      "select"    => SELECT_METHOD,
      "select!"   => SELECT_IN_PLACE_METHOD,
      "reject"    => REJECT_METHOD,
      "reject!"   => REJECT_IN_PLACE_METHOD,
      "partition" => PARTITION_METHOD,
      "reduce"    => REDUCE_METHOD,
      "find"      => FIND_METHOD,
      "shift"     => SHIFT_METHOD,
      "unshift"   => UNSHIFT_METHOD,
      "resize"    => RESIZE_METHOD,
      "includes?" => INCLUDES_METHOD,
      "has"       => INCLUDES_METHOD,
      "has?"      => INCLUDES_METHOD,
      "empty?"    => EMPTY_METHOD,

      "decode" => DECODE_METHOD,

      "sort"     => SORT_METHOD,
      "sort_num" => SORT_NUM_METHOD,
    })

    @@type_aliases = ::Set{"arr", "array", "list"}

    def initialize
      @value = [] of Variant
    end

    def initialize(arr : ::Array(Variant))
      @value = arr
    end

    delegate size, to: @value

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

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call Array")
    end

    def ==(other : Variant)
      other.is_a?(Array) && @value == other.@value
    end

    def <<(val : Variant)
      @value << val
    end

    def to_json : ::String
      @value.to_json
    end

    def to_json(builder : JSON::Builder)
      @value.to_json(builder)
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
      res = @value.reduce(0.0) { |acc, item| acc + item.to_f64 }
      Float.new(res)
    end

    def sort! : self
      # to_s operations can be expensive like on arrays so we can precalculate them
      pairs = @value.map { |item| {item, item.to_s} }
      pairs.sort! { |left, right| left[1] <=> right[1] }
      sorted_arr = pairs.map { |v, _| v }
      @value = sorted_arr
      self
    end

    def sort : self
      dup.sort!
    end

    def sort_num : Array
      pairs = @value.map { |item| {item, item.to_f64} }
      pairs.sort! { |left, right| left[1] <=> right[1] }
      sorted_arr = pairs.map { |v, _| v }
      Array.new(sorted_arr)
    end

    def iter_init(context : Interpreter::Context) : Iterator
      ArrayIterator.new(@value)
    end

    def truthy? : ::Bool
      # !@value.empty?
      true
    end

    def map!(context : Interpreter::Context, fn : Function)
      @value.map! do |var|
        fn.call(context, [var] of Variant)
      end
      self
    end

    def map(context : Interpreter::Context, fn : Function)
      dup.map!(context, fn)
    end

    def select!(context : Interpreter::Context, fn : Function)
      @value.select! do |var|
        fn.call(context, [var] of Variant).truthy?
      end
      self
    end

    def select(context, fn : Function)
      dup.select!(context, fn)
    end

    def reject!(context : Interpreter::Context, fn : Function)
      @value.reject! do |var|
        fn.call(context, [var] of Variant).truthy?
      end
      self
    end

    def reject(context : Interpreter::Context, fn : Function)
      dup.reject!(context, fn)
    end

    def reduce(context : Interpreter::Context, fn : Function)
      initial_value = @value[0]
      @value[1..].reduce(initial_value) do |acc, i|
        fn.call(context, [acc, i] of Variant)
      end
    end

    def reduce(context : Interpreter::Context, initial_value : Variant, fn : Function)
      @value.reduce(initial_value) do |acc, i|
        fn.call(context, [acc, i] of Variant)
      end
    end

    def find(context : Interpreter::Context, fn : Function, if_none : Variant = NULL)
      @value.find(if_none) do |item|
        fn.call(context, [item] of Variant).truthy?
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
      str_arr.join(sep)
    end

    def partition(context : Interpreter::Context, func : Function) : Array
      a, b = @value.partition do |val|
        func.call(context, [val] of Variant).truthy?
      end
      a = Array.new(a)
      b = Array.new(b)
      Array.new([a, b] of Variant)
    end

    def decode : String
      arr = @value.map { |v| v.to_u8 }
      slice = Bytes.new(arr.size) do |i|
        arr[i]
      end
      String.new(::String.new(slice))
    end
  end

  class Set < Variant
    @value : ::Set(Variant)

    ADD_METHOD = TMBSH.method("add", 1..) do
      args.each(within: 1..) do |item|
        this << item
      end
      this
    end

    {% for i in ["subset_of", "superset_of"] %}
      {{i.id.upcase}}_METHOD = TMBSH.method("{{i.id.upcase}}", 1) do
        other = args[1]
        raise ArgumentError.new("Expected the argument to be of type Set") unless other.is_a?(Set)
        this.{{i.id}}?(other) ? TRUE : FALSE
      end

      PROPER_{{i.id.upcase}}_METHOD = TMBSH.method("proper_{{i.id.upcase}}", 1) do
        other = args[1]
        raise ArgumentError.new("Expected the argument to be of type Set") unless other.is_a?(Set)
        this.proper_{{i.id}}?(other) ? TRUE : FALSE
      end
    {% end %}
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

    AND_METHOD = TMBSH.method("and", 1) do
      other = args[1]
      raise ArgumentError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this & other
    end
    OR_METHOD = TMBSH.method("or", 1) do
      other = args[1]
      raise ArgumentError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this | other
    end
    XOR_METHOD = TMBSH.method("xor", 1) do
      other = args[1]
      raise ArgumentError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this ^ other
    end
    UNION_METHOD = TMBSH.method("union", 1) do
      other = args[1]
      raise ArgumentError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this + other
    end
    DIFFERENCE_METHOD = TMBSH.method("difference", 1) do
      other = args[1]
      raise ArgumentError.new("Expected the argument to be a Set") unless other.is_a?(Set)
      this - other
    end

    TO_A_METHOD = TMBSH.method("to_a", 0) do
      this.to_sharr
    end

    INCLUDES_METHOD = TMBSH.method("includes", 1) do
      this.includes?(args[1])
    end

    CLEAR_METHOD = TMBSH.method("clear", 0) do
      this.clear
      this
    end

    DELETE_METHOD = TMBSH.method("delete", 1..) do
      args.each(within: 1..) do |item|
        this.delete item
      end
      this
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "add"                 => ADD_METHOD,
      "delete"              => DELETE_METHOD,
      "del"                 => DELETE_METHOD,
      "includes?"           => INCLUDES_METHOD,
      "has?"                => INCLUDES_METHOD,
      "has"                 => INCLUDES_METHOD,
      "union"               => UNION_METHOD,
      "diff"                => DIFFERENCE_METHOD,
      "difference"          => DIFFERENCE_METHOD,
      "and"                 => AND_METHOD,
      "or"                  => OR_METHOD,
      "xor"                 => XOR_METHOD,
      "subset_of?"          => SUBSET_OF_METHOD,
      "proper_subset_of?"   => PROPER_SUBSET_OF_METHOD,
      "superset_of?"        => SUPERSET_OF_METHOD,
      "proper_superset_of?" => PROPER_SUPERSET_OF_METHOD,
      "to_a"                => TO_A_METHOD,
      "clear"               => CLEAR_METHOD,
    })

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

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
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

    def iter_init(context : Interpreter::Context) : Iterator
      to_sharr.iter_init(context)
    end

    def truthy? : ::Bool
      # !@value.empty?
      true
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

    {% for i in ["subset_of", "superset_of"] %}
      def {{i.id}}?(other : Set) : ::Bool
        @value.{{i.id}}?(other.@value)
      end

      def proper_{{i.id}}?(other : Set) : ::Bool
        @value.proper_{{i.id}}?(other.@value)
      end
    {% end %}

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

      # @@string_pool : StringPool = StringPool.new

      def initialize(val : ::String)
        # @str = @@string_pool.get(val)
        @str = val
      end

      def iter_next(context : Interpreter::Context) : Variant?
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
        @dir_iter = Dir.new(path).each_child
      end

      def clone : self
        self
      end

      def dup : self
        self
      end

      def iter_next(context : Interpreter::Context) : Variant?
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

      def iter_next(context : Interpreter::Context) : Variant?
        if first = @next_dirs.first?
          path = first.pop
          entries = Dir.children(path)
          dirs, files = entries.partition { |entry| Dir.exists?(path / entry) }
          @next_dirs << dirs.map { |dir| path / dir } unless dirs.empty?
          dirs = Array.new(dirs.map { |e| String.new(e).as(Variant) })
          files = Array.new(files.map { |e| String.new(e).as(Variant) })
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

    SIZE_METHOD = TMBSH.method("size", 0) do
      Int.new(this.@value.size)
    end
    STRIP_METHOD = TMBSH.method("strip", 0..1) do
      if v = args[1]?
        String.new(this.@value.strip(v.to_s))
      else
        String.new(this.@value.strip)
      end
    end
    RSTRIP_METHOD = TMBSH.method("rstrip", 0..1) do
      if v = args[1]?
        String.new(this.@value.rstrip(v.to_s))
      else
        String.new(this.@value.rstrip)
      end
    end
    LSTRIP_METHOD = TMBSH.method("lstrip", 0..1) do
      if v = args[1]?
        String.new(this.@value.lstrip(v.to_s))
      else
        String.new(this.@value.lstrip)
      end
    end
    SPLIT_METHOD = TMBSH.method("split", 0..1) do
      arr = if sep = args[1]?
        this.@value.split(sep.to_s)
      else
        this.@value.split
      end
      Array.new(
        arr.map do |item|
          String.new(item).as(Variant)
        end
      )
    end
    CONCAT_METHOD = TMBSH.method("concat", 1..) do
      res = this
      args.each(within: 1..) do |item|
        res = res.concat(item)
      end
      res
    end

    FROM_JSON_METHOD = TMBSH.method("from_json", 0) do
      this.from_json
    end

    ENTRIES_METHOD = TMBSH.method("entries", 0) do
      this.entries
    end

    ITERDIR_METHOD = TMBSH.method("iterdir", 0) do
      this.iterdir
    end

    REVERSE_METHOD = TMBSH.method("reverse", 0) do
      String.new(this.@value.reverse)
    end

    READ_METHOD = TMBSH.method("read", 0) do
      begin
        contents = ::File.read(this.@value)
        String.new(contents)
      rescue
        NULL
      end
    end

    EXISTS_METHOD = TMBSH.method("exists", 0) do
      ::File.exists?(this.@value) ? TRUE : FALSE
    end

    CHOMP_METHOD = TMBSH.method("chomp", 0..1) do
      if suf = args[1]?
        String.new(this.@value.chomp(suf.to_s))
      else
        String.new(this.@value.chomp)
      end
    end

    LCHOP_METHOD = TMBSH.method("lchop", 0..1) do
      if suf = args[1]?
        String.new(this.@value.lchop(suf.to_s))
      else
        String.new(this.@value.lchop)
      end
    end

    COUNT_METHOD = TMBSH.method("count", 1..) do
      res = 0
      args.each(within: 1..) do |arg|
        target = arg.to_s
        res += this.@value.count(target)
      end
      Float.new(
        res.to_f64
      )
    end

    ENDS_WITH_METHOD = TMBSH.method("ends_with", 1) do
      # res = false
      # args.each(within: 1..) do |arg|
      #   target = arg.to_s
      #   if this.@value.ends_with?(target)
      #     res = true
      #     break
      #   end
      # end
      # res ? TRUE : FALSE
      this.@value.ends_with?(args[1].to_s) ? TRUE : FALSE
    end

    STARTS_WITH_METHOD = TMBSH.method("starts_with", 1) do
      # res = false
      # args.each(within: 1..) do |arg|
      #   target = arg.to_s
      #   if this.@value.starts_with?(target)
      #     res = true
      #     break
      #   end
      # end
      # res ? TRUE : FALSE
      this.@value.starts_with?(args[1].to_s) ? TRUE : FALSE
    end

    INDEX_METHOD = TMBSH.method("index", 1..2) do
      if args.size == 2
        search = args[1].to_s
        idx = this.@value.index(search)
        idx ? Float.new(idx.to_f64) : NULL
      elsif args.size == 3
        search = args[1].to_s
        offset = args[2].to_i
        idx = this.@value.index(search, offset)
        idx ? Float.new(idx.to_f64) : NULL
      end
    end

    {% for i in ["downcase", "upcase", "titleize", "camelcase", "underscore", "capitalize"] %}
      {{i.id.upcase}}_METHOD = TMBSH.method("{{i.id.upcase}}", 0) do
        String.new(this.@value.{{i.id}})
      end
    {% end %}

    PARTITION_METHOD = TMBSH.method("partition", 1) do
      left, sep, right = this.@value.partition(args[1].to_s)
      Array.new(
        [String.new(left), String.new(sep), String.new(right)] of Variant
      )
    end

    RPARTITION_METHOD = TMBSH.method("rpartition", 1) do
      left, sep, right = this.@value.rpartition(args[1].to_s)
      Array.new(
        [String.new(left), String.new(sep), String.new(right)] of Variant
      )
    end

    JOIN_METHOD = TMBSH.method("join", 1..) do
      path = Path[this.@value]
      args.each(within: 1..) do |arg|
        path = path / arg.to_s
      end
      String.new(path.to_s)
    end

    CHARS_METHOD = TMBSH.method("chars", 0) do
      arr = this.@value.chars.map do |char|
        String.new(char.to_s).as(Variant)
      end
      Array.new(arr)
    end

    IS_FILE_METHOD = TMBSH.method("is_file", 0) do
      ::File.file?(this.@value) ? TRUE : FALSE
    end
    IS_DIR_METHOD = TMBSH.method("is_dir", 0) do
      ::Dir.exists?(this.@value) ? TRUE : FALSE
    end

    WALK_METHOD = TMBSH.method("walk", 0) do
      this.walk
    end

    ABSOLUTE_METHOD = TMBSH.method("absolute", 0) do
      this.absolute
    end

    INT_METHOD = TMBSH.method("int", 0..1) do
      base = (args[1]?.try &.to_i64) || 10
      if res = this.@value.to_i64?(base)
        Int.new(res)
      end
    end

    FLOAT_METHOD = TMBSH.method("float", 0) do
      if res = this.@value.to_f64?
        Float.new(res)
      end
    end

    STAT_METHOD = TMBSH.method("stat", 0) do
      this.stat
    end

    ENCODE_METHOD = TMBSH.method("encode", 0) do
      this.encode
    end

    OPEN_METHOD = TMBSH.method("open", 0..1) do
      modes = args[1]?.try &.to_s || "r"
      File.new(this.@value, modes)
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
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
      "float"        => FLOAT_METHOD,
      "int"          => INT_METHOD,
      # filesystem methods
      "dir?"     => IS_DIR_METHOD,
      "file?"    => IS_FILE_METHOD,
      "absolute" => ABSOLUTE_METHOD,
      "abs"      => ABSOLUTE_METHOD,
      "walk"     => WALK_METHOD,
      "stat"     => STAT_METHOD,
      "info"     => STAT_METHOD,
      "read"     => READ_METHOD,
      "open"     => OPEN_METHOD,
      "exists?"  => EXISTS_METHOD,
      "iterdir"  => ITERDIR_METHOD,

      "from_json" => FROM_JSON_METHOD,
    })

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

    # TODO: rework method do support conversion from other bases
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
      raise TypeError.new("Cannot set on String")
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call String")
    end

    def ==(other : Variant)
      other.is_a?(String) && @value == other.@value
    end

    def concat(other : Variant) : String
      other = other.to_shs
      String.new(@value + other.@value)
    end

    def to_json : ::String
      @value.to_json
    end

    def to_json(builder : JSON::Builder)
      @value.to_json(builder)
    end

    def from_json : Variant
      json = JSON.parse(@value)
      TMBSH.variant_from_json(json)
    end

    def entries : Array?
      return unless Dir.exists?(@value)
      Array.new(
        Dir.children(@value).map do |item|
          String.new(item).as(Variant)
        end
      )
    end

    def iter_init(context : Interpreter::Context) : Iterator
      StringIterator.new(@value)
    end

    def truthy? : ::Bool
      # !@value.empty?
      true
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
        String.new("directory?")           => info.directory? ? TRUE : FALSE,
        String.new("file?")                => info.file? ? TRUE : FALSE,
        String.new("symlink?")             => info.symlink? ? TRUE : FALSE,
        String.new("flags")                => Int.new(info.flags.to_i64),
        String.new("group_id")             => String.new(info.group_id),
        String.new("owner_id")             => String.new(info.owner_id),
        String.new("modification_time")    => Int.new(info.modification_time.to_unix),
        String.new("modification_time_ns") => Int.new(info.modification_time.nanosecond),
        String.new("permissions")          => Int.new(info.permissions.to_i64),
        String.new("size")                 => Int.new(info.size),
      } of Variant => Variant
      Dictionary.new(info_hash)
    end

    def encode : Array
      Array.new(@value.to_slice.to_a.map { |v| Int.new(v).as(Variant) })
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

      def iter_next(context : Interpreter::Context) : Variant?
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

    KEYS_METHOD = TMBSH.method("keys", 0) do
      Array.new(this.@value.keys)
    end

    VALUES_METHOD = TMBSH.method("values", 0) do
      Array.new(this.@value.values)
    end

    INVERT_METHOD = TMBSH.method("invert", 0) do
      Dictionary.new(this.@value.dup.invert)
    end

    PAIRS_METHOD = TMBSH.method("pairs", 0..3) do
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

    FETCH_METHOD = TMBSH.method("fetch", 1..2) do
      key = args[1]
      if alt = args[2]?
        this[key]? || alt
      else
        this[key]?
      end
    end

    HAS_KEY_METHOD = TMBSH.method("has_key", 1) do
      this.@value.has_key?(args[1]) ? TRUE : FALSE
    end

    HAS_VALUE_METHOD = TMBSH.method("has_value", 1) do
      this.@value.has_value?(args[1]) ? TRUE : FALSE
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "fetch"      => FETCH_METHOD,
      "keys"       => KEYS_METHOD,
      "values"     => VALUES_METHOD,
      "has_key?"   => HAS_KEY_METHOD,
      "has_value?" => HAS_VALUE_METHOD,
      "invert"     => INVERT_METHOD,
      "pairs"      => PAIRS_METHOD,
    })
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

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call Dictionary")
    end

    def ==(other : Variant)
      other.is_a?(Dictionary) && @value == other.@value
    end

    def to_json : ::String
      @value.to_json
    end

    def to_json(builder : JSON::Builder)
      @value.to_json(builder)
    end

    def iter_init(context : Interpreter::Context) : Iterator
      DictionaryIterator.new(@value)
    end

    def get_attribute(name : ::String) : Variant
      self[String.new(name)]? || NULL
    end

    def set_attribute(name : ::String, val : Variant) : Variant
      self[String.new(name)] = val
    end

    def truthy? : ::Bool
      # !@value.empty?
      true
    end
  end

  NULL = Null.new

  class Null < Variant
    RANGE_METHOD = TMBSH.method("range", 0..1) do
      Range.new(nil, args[1]?.try &.to_i64, false)
    end

    ERANGE_METHOD = TMBSH.method("erange", 0..1) do
      Range.new(nil, args[1]?.try &.to_i64, true)
    end
    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "range"  => RANGE_METHOD,
      "erange" => ERANGE_METHOD,
      "r"      => RANGE_METHOD,
      "er"     => ERANGE_METHOD,
    })

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

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call Null")
    end

    def to_s : ::String
      ""
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
      raise TypeError.new("Cannot access key on Null")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot access key on Null")
    end

    def []=(key : Variant, value : Variant) : Variant
      raise TypeError.new("Cannot access key on Null")
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

    def iter_init(context : Interpreter::Context) : Iterator
      raise TypeError.new("Cannot iterate over Null")
    end

    def truthy? : ::Bool
      false
    end
  end

  FALSE = Bool.new(false)
  TRUE  = Bool.new(true)

  class Bool < Variant
    @value : ::Bool

    OR_METHOD = TMBSH.method("or", 0..1) do
      if this.truthy?
        args[1]? || NULL
      else
        this
      end
    end

    AND_METHOD = TMBSH.method("and", 0..1) do
      if this.truthy?
        this
      else
        args[1]? || NULL
      end
    end

    # STR_METHOD = TMBSH.method("str", 0) do
    #   String.new(this.@value ? "True" : "False")
    # end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "or"  => OR_METHOD,
      "and" => AND_METHOD,
    })

    @@type_aliases = ::Set{"bool", "boolean", "the universal"}

    def initialize(bool : ::Bool)
      @value = bool
    end

    def hash : UInt64
      @value.hash
    end

    def [](key : Variant) : Variant
      raise TypeError.new("Cannot do access on Bool")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot do access on Bool")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot ::Set on Bool")
    end

    def to_s : ::String
      @value ? "true" : "false"
    end

    def to_f64 : Float64
      @value ? 0.0 : 1.0
    end

    def to_i64 : Int64
      @value ? 0_i64 : 0_i64
    end

    def to_a : ::Array(Variant)
      raise TypeError.new("Cannot convert Bool to Array")
    end

    def dup : Bool
      self
    end

    def clone : Bool
      self
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call a Bool")
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

    def iter_init(context : Interpreter::Context) : Iterator
      raise TypeError.new("Cannot iterate over Bool")
    end

    def truthy? : ::Bool
      @value
    end
  end

  class Function < Variant
    @proc : Proc(Interpreter::Context, ::Array(Variant), Variant?)? = nil
    property name : ::String?
    property parent_class : ::String?
    @binded_args : ::Array(Variant)

    BIND_METHOD = TMBSH.method("bind", 1..) do
      binded = args.to_a[1..]
      this.bind(binded)
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "bind"  => BIND_METHOD,
    })
    @@type_aliases = ::Set{"func", "function"}

    def initialize
      @binded_args = [] of Variant
    end

    def initialize(@proc : Proc(Interpreter::Context, ::Array(Variant), Variant?)?, binded_args : ::Array(Variant))
      @binded_args = binded_args
    end

    def initialize(@proc : Proc(Interpreter::Context, ::Array(Variant), Variant?)?)
      @binded_args = [] of Variant
    end

    def initialize(@parent_class : ::String, @name : ::String, @proc : Proc(Interpreter::Context, ::Array(Variant), Variant?)?)
      @binded_args = [] of Variant
    end

    def initialize(@name : ::String, @proc : Proc(Interpreter::Context, ::Array(Variant), Variant?)?)
      @binded_args = [] of Variant
    end

    def hash : UInt64
      @proc.hash
    end

    def [](key : Variant) : Variant
      raise TypeError.new("Cannot do access on Function")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot do access on Function")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot set on Function")
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
      raise TypeError.new("Cannot convert Function to Float")
    end

    def to_i64 : Int64
      raise TypeError.new("Cannot convert Function to Int")
    end

    def to_a : ::Array(Variant)
      raise TypeError.new("Cannot convert Function to Array")
    end

    def dup : Function
      self.class.new(@proc, @binded_args.dup)
    end

    def clone : Function
      self.class.new(@proc, @binded_args.clone)
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      begin
        @proc.try &.call(context, @binded_args.empty? ? args : @binded_args + args) || TMBSH::NULL
      rescue e : Exception
        raise e.class.new(e.message.to_s + " (When calling #{to_s})")
      end
    end

    def ==(other : Variant)
      other.is_a?(Function) && @proc == other.@proc && @binded_args == other.@binded_args
    end

    def to_json : ::String
      raise TypeError.new("Cannot convert function to JSON")
    end

    def to_json(builder : JSON::Builder)
      raise TypeError.new("Cannot convert function to JSON")
    end

    def iter_init(context : Interpreter::Context) : Iterator
      raise TypeError.new("Cannot iterate over Function")
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

    # WRITE_METHOD = TMBSH.method("write") do
    #   args.each(within: 1..) do |arg|
    #     this.@file.print(arg.to_s)
    #   end
    #   this
    # end

    PRINT_METHOD = TMBSH.method("print", 1..) do
      args.each(within: 1..) do |arg|
        this.@file.print(arg.to_s)
      end
      this
    end
    PUTS_METHOD = TMBSH.method("puts", 1..) do
      args.each(within: 1..) do |arg|
        this.@file.puts(arg.to_s)
      end
      this
    end

    READ_METHOD = TMBSH.method("read", 1) do
      raise ArgumentError.new("Expected one Array argument to read") unless args[1].is_a?(Array)
      ary = args[1].as(Array)
      bytes = Bytes.new(ary.size)
      amount = this.@file.read(bytes)
      bytes[0...amount].each_with_index do |b, i|
        ary.@value[i] = Int.new(b)
      end
      ary
    end

    GETS_TO_END_METHOD = TMBSH.method("gets_to_end", 0) do
      String.new(this.@file.gets_to_end)
    end

    GETS_METHOD = TMBSH.method("gets", 0..1) do
      if args.size == 1
        val = this.@file.gets
        val ? String.new(val) : NULL
      elsif args.size == 2
        val = this.@file.gets(args[1].to_s)
        val ? String.new(val) : NULL
      end
    end

    CLOSE_METHOD = TMBSH.method("close", 0) do
      this.@file.close
      NULL
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({

      # "write"  => WRITE_METHOD,
      "print"       => PRINT_METHOD,
      "puts"        => PUTS_METHOD,
      "read"        => READ_METHOD,
      "readline"    => GETS_METHOD,
      "gets"        => GETS_METHOD,
      "gets_to_end" => GETS_TO_END_METHOD,
      "read_fully"  => GETS_TO_END_METHOD,
      "close"       => CLOSE_METHOD,
    })

    @@type_aliases = ::Set{"file", "descriptor"}

    def initialize(filename : ::String | Path, mode : ::String = "r")
      @path = filename.to_s
      @file = ::File.open(filename, mode)
    end

    def hash : UInt64
      @file.hash
    end

    def [](key : Variant) : Variant
      raise TypeError.new("Cannot do access on File")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot do access on File")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot set key on File")
    end

    def to_s : ::String
      @file.fd.to_s
    end

    def to_f64 : Float64
      raise TypeError.new("Cannot convert File to Float")
    end

    def to_i64 : Int64
      @file.fd.to_i64
    end

    def to_a : ::Array(Variant)
      raise TypeError.new("Cannot convert File to Array")
    end

    def dup : File
      raise TypeError.new("Cannot dup File")
    end

    def clone : File
      raise TypeError.new("Cannot clone File")
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call File")
    end

    def ==(other : Variant)
      other.is_a?(File) && @path == other.@path
    end

    def to_json : ::String
      raise TypeError.new("Cannot convert File to JSON")
    end

    def to_json(builder : JSON::Builder)
      raise TypeError.new("Cannot convert File to JSON")
    end

    def iter_init(context : Interpreter::Context) : Iterator
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
    @exit_code : Int32?
    @status : Process::Status?
    property status
    FLOAT_METHOD = TMBSH.method("float", 0) do
      code = this.@exit_code
      code ? Float.new(code) : NULL
    end
    INT_METHOD = TMBSH.method("int", 0) do
      code = this.@exit_code
      code ? Float.new(code) : NULL
    end

    DESCRIPTION_METHOD = TMBSH.method("description", 0) do
      status = this.status
      status ? String.new(status.description) : NULL
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "float" => FLOAT_METHOD,
      "int"   => INT_METHOD,

      "description" => DESCRIPTION_METHOD,
    })

    @@type_aliases = ::Set{"exit_status", "status"}

    def initialize(exit_code : Int32?, status : Process::Status? = nil)
      @exit_code = exit_code
      @status = status
    end

    def to_s : ::String
      @exit_code.to_s
    end

    def to_f64 : Float64
      @exit_code.try &.to_f64 || -1.0
    end

    def to_i64 : Int64
      @exit_code.try &.to_i64 || -1_i64
    end

    def to_a : ::Array(Variant)
      raise TypeError.new("Cannot convert Status to Array")
    end

    def dup : ExitStatus
      self
    end

    def clone : ExitStatus
      self
    end

    def hash : UInt64
      @exit_code.hash
    end

    def [](key : Variant) : Variant
      raise TypeError.new("Cannot do access on Status")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot do access on Status")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot set on Status")
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call Status")
    end

    def ==(other : Variant)
      return @exit_code == other.@exit_code if other.is_a?(ExitStatus)
      begin
        other_status = other.to_i64
        @exit_code == other_status
      rescue
        false
      end
    end

    def to_json : ::String
      @exit_code.to_json
    end

    def to_json(builder : JSON::Builder)
      @exit_code.to_json(builder)
    end

    def iter_init(context : Interpreter::Context) : Iterator
      raise TypeError.new("Cannot iterate over status")
    end

    def truthy? : ::Bool
      @exit_code == 0
    end
  end

  class Promise < Variant
    # @fiber : Fiber
    @channel : Channel(Variant)

    AWAIT_METHOD = TMBSH.method("await", 0..1) do
      if time = args[1]?
        time = if time.is_a?(Int)
                 time.@value.seconds
               elsif time.is_a?(Float)
                 time.@value.seconds
               elsif time.is_a?(String)
                time.to_f64.seconds
               else
                 raise ArgumentError.new("Expected Int or Float as first argument to await")
               end
        this.await(time)
      else
        this.await
      end
    end

    AWAITED_METHOD = TMBSH.method("awaited?", 0) do
      this.@channel.closed? ? TRUE : FALSE
    end

    @@methods_hash_cache : Hash(UInt64, Function) = {} of UInt64 => Function
    @@methods = TMBSH.generate_methods({
      "await"    => AWAIT_METHOD,
      "awaited?" => AWAITED_METHOD,
    })

    @@type_aliases = ::Set{"promise"}

    def initialize(channel : Channel(Variant))
      @channel = channel
    end

    def to_s : ::String
      @channel.to_s
    end

    def to_f64 : Float64
      raise TypeError.new("Cannot convert Promise to Float")
    end

    def to_i64 : Int64
      raise TypeError.new("Cannot convert Promise to Int")
    end

    def to_a : ::Array(Variant)
      raise TypeError.new("Cannot convert Promise to Array")
    end

    def dup : Promise
      self
    end

    def clone : Promise
      self
    end

    def hash : UInt64
      @channel.hash
    end

    def [](key : Variant) : Variant
      raise TypeError.new("Cannot access key on Promise")
    end

    def []?(key : Variant) : Variant
      raise TypeError.new("Cannot access key on Promise")
    end

    def []=(key : Variant, value : Variant)
      raise TypeError.new("Cannot set key on Promise")
    end

    def call(context : Interpreter::Context, args : ::Array(Variant)) : Variant
      raise TypeError.new("Cannot call Status")
    end

    def ==(other : Variant)
      return @channel == other.@channel if other.is_a?(Promise)
    end

    def to_json : ::String
      raise TypeError.new("Cannot convert Promise to JSON")
    end

    def to_json(builder : JSON::Builder)
      raise TypeError.new("Cannot convert Promise to JSON")
    end

    def iter_init(context : Interpreter::Context) : Iterator
      raise TypeError.new("Cannot iterate over Promise")
    end

    def truthy? : ::Bool
      true
    end

    def await : Variant
      return NULL if @channel.closed?
      Fiber.yield
      val = @channel.receive
      @channel.close
      val
    end

    def await(time : Time::Span) : Variant
      return NULL if @channel.closed?
      Fiber.yield
      select
      when val = @channel.receive
        @channel.close
        val
      when timeout(time)
        NULL
      end
    end
  end
end
