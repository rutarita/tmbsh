require "./interpreter"
require "./readline"

module TMBSH
  macro tl_function(&block)
# top level function duhh
    Function.new(->(context : Interpreter::Context, args : ::Array(Variant)) : Variant? {
      {{ block.body }}
    })
  end

  PRINT_FUNCTION = TMBSH.tl_function do
    args.each do |arg|
      print arg.to_s, ' '
    end
    puts
  end

  class EnumerateIterator < TMBSH::Iterator
    @idx : Int64
    @iter : Iterator
    property idx
    property iter

    def initialize(context : Interpreter::Context, iterable : Variant, offset : Int64 = 0)
      @idx = offset
      @iter = iterable.iter_init(context)
    end

    def initialize(iterator : Iterator, offset : Int64 = 0)
      @idx = offset
      @iter = iterator
    end

    def iter_next(context : Interpreter::Context) : Variant?
      if val = @iter.iter_next(context)
        arr = Array.new([Int.new(@idx), val] of Variant)
        @idx += 1
        arr
      end
    end

    def clone : self
      self.class.new(@iter.dup, @idx)
    end

    def dup : self
      self.class.new(@iter.dup, @idx)
    end
  end

  class ZipIterator < TMBSH::Iterator
    @iterators : ::Array(TMBSH::Iterator) = [] of TMBSH::Iterator
    property iterators

    def initialize(context : Interpreter::Context, iterables : ::Array(Variant))
      iterables.each do |var|
        @iterators << var.iter_init(context)
      end
    end

    def initialize(iterators : ::Array(Iterator))
      @iterators = iterators
    end

    @depleted : ::Bool = false

    def iter_next(context : Interpreter::Context) : Variant?
      unless @depleted
        res = [] of Variant
        @iterators.each do |iterator|
          if var = iterator.iter_next(context)
            res << var
          else
            @depleted = true
            return
          end
        end
        Array.new(res)
      end
    end

    def clone : self
      self.class.new(@iterators)
    end

    def dup : self
      self.class.new(@iterators)
    end
  end

  ENUMERATE_FUNCTION = TMBSH.tl_function do
    raise "Expected at one argument and optional offset argument" if args.empty? || args.size > 2
    offset = args[1]?
    if offset
      offset = offset.to_i64
    else
      offset = 0_i64
    end
    EnumerateIterator.new(context, args[0], offset)
  end

  ZIP_FUNCTION = TMBSH.tl_function do
    ZipIterator.new(context, args.to_a)
  end

  DIR_FUNCTION = TMBSH.tl_function do
    raise "Expected one argument to inspect" unless args.size == 1
    var = args[0]
    methods = var.get_method_list
    Array.new(methods.map do |item|
      String.new(item).as(Variant)
    end)
  end

  READLINE_FUNCTION = TMBSH.tl_function do
    raise "readline only requires one optional arguments" if args.size > 1
    prompt = args[0]? ? args[0].to_s : ""
    str = ReadLine.readline(prompt)
    String.new(str) if str
  end

  RAND_FUNCTION = TMBSH.tl_function do
    num = case args.size
      when 0 then rand(Int64::MIN..Int64::MAX)
      when 1 then rand(args[0].to_i64)
      when 2 then rand(args[0].to_i64..args[1].to_i64)
      else raise "Expected 2 arguments at most"
      end
    Float.new(num.to_f64)
  end

  RANDI_FUNCTION = TMBSH.tl_function do
      num = case args.size
      when 0 then rand(Int64::MIN..Int64::MAX)
      when 1 then rand(args[0].to_i64)
      when 2 then rand(args[0].to_i64..args[1].to_i64)
      else raise "Expected 2 arguments at most"
      end
    Int.new(num.to_f64)
  end

  RANDIE_FUNCTION = TMBSH.tl_function do
    num = case args.size
      when 0 then rand(Int64::MIN..Int64::MAX)
      when 1 then rand(args[0].to_i64)
      when 2 then rand(args[0].to_i64...args[1].to_i64)
      else raise "Expected 2 arguments at most"
      end
    Int.new(num.to_f64)
  end

  MAX_FUNCTION = TMBSH.tl_function do
    return NULL if args.size == 0
    best = args[0]
    best_val = best.to_f64
    # best_val = -Float64::INFINITY
    args.each(within: 1..) do |num|
      val = num.to_f64
      if val > best_val
      best = num
      best_val = val
      end
    end
    best || raise "Unexpected error"
  end

  MIN_FUNCTION = TMBSH.tl_function do
    return NULL if args.size == 0
    best = args[0]
    best_val = best.to_f64
    args.each(within: 1..) do |num|
      val = num.to_f64
      if val < best_val
      best = num
      best_val = val
      end
    end
    best || raise "Unexpected error"
  end

  TIME_FUNCTION = TMBSH.tl_function do
    Float.new(Time.utc.to_unix_f)
  end

  TYPE_OF_FUNCTION = TMBSH.tl_function do
    raise "Expected one argument to typeof" unless args.size == 1
    var = args[0]
    class_name = var.class.to_s
    typename = class_name.lchop("TMBSH::")
    String.new(typename)
  end

  VARS_FUNCTION = TMBSH.tl_function do
    map = {} of Variant => Variant
    context.current_variable_stack.@vars.last.each do |k,v|
      map[String.new(k)] = v
    end
    # context.variable_stack.@vars.last.each do |k,v|
    #   map[String.new(k)] = v
    # end
    Dictionary.new(map)
  end

  TOP_LEVEL_VALUES = {
    "true"      => TRUE,
    "false"     => FALSE,
    "null"      => NULL,
    "print"     => PRINT_FUNCTION,
    "enumerate" => ENUMERATE_FUNCTION,
    "zip"       => ZIP_FUNCTION,
    "dir"       => DIR_FUNCTION,
    "readline"  => READLINE_FUNCTION,
    "rand"      => RAND_FUNCTION,
    "randi"     => RANDI_FUNCTION,
    "randie"     => RANDIE_FUNCTION,
    "max"       => MAX_FUNCTION,
    "min"       => MIN_FUNCTION,
    "time"      => TIME_FUNCTION,
    "typeof"    => TYPE_OF_FUNCTION,
    "vars"      => VARS_FUNCTION,
  } of ::String => Variant
end
