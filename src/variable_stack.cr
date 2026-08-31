require "./datatypes"

class TMBSH::Interpreter::VariableStack
  # @vars : ::Array(::Hash(StringName, Variant))
  @vars : ::Array(::Hash(StringName, Variant))
  getter vars
  # @global : ::Hash(StringName, Variant) = {} of StringName => Variant
  @global : ::Hash(StringName, Variant) = {} of StringName => Variant
  # @constants : ::Hash(StringName, Variant) = TOP_LEVEL_VALUES
  @constants : ::Hash(StringName, Variant) = TOP_LEVEL_VALUES
  @strict : ::Bool = false
  property strict

  UNDERSCORE_STRING_NAME = StringName.new("_")

  # @scope_cache : ::Hash(StringName, Int32) = {} of StringName => Int32

  def initialize
    @vars = [@global]
  end

  def enter_scope : Nil
    @vars << {} of StringName => Variant
  end

  def exit_scope : Nil
    if @vars.size > 1
      @vars.pop
      # @vars.pop.each_key do |key|
      #   @scope_cache.delete(key)
      # end
    else
      raise "Cannot exit global scope"
    end
  end

  def current_scope
    @vars.size - 1
  end

  def local_scope
    @vars[-1]
  end

  def find_scope(of_var : StringName) : ::Hash(StringName, Variant)?
    # if scope = @scope_cache[of_var]?
    #   return scope
    # end
    @vars.reverse_each do |scope|
      if scope[of_var]?
        # @scope_cache[of_var] = i
        return scope
      end
    end
  end

  def set_constant(name : StringName, value : Variant)
    @constants[name] = value
  end

  def shadow_variable(name : StringName, value : Variant) : Nil
    return if name == UNDERSCORE_STRING_NAME
    # @scope_cache[name] = current_scope
    @vars.last[name] = value
  end

  def [](name : StringName) : Variant
    if val = @constants[name]?
      return val
    end
    if str = ENV[name.to_s]?
      return String.new(str)
    end
    if scope = find_scope(name)
      scope[name]
    else
      @strict ? raise "Variable #{name} not found" : return TMBSH::NULL
      # TMBSH::NULL
    end
  end

  private def set_env(name : StringName, value : Variant) : Nil
    # return if val.is_a?(Null)
    if value.is_a?(Array)
      ENV[name.to_s] = value.join(":")
    elsif value.is_a?(Null)
      ENV.delete(name.to_s)
    else
      ENV[name.to_s] = value.to_s
    end
  end

  def []=(name : StringName, value : Variant) : Nil
    return if name == UNDERSCORE_STRING_NAME
    if ENV[name.to_s]?
      set_env(name, value)
      return
    end
    scope = find_scope(name) || @vars.last
    if !@strict && value == TMBSH::NULL
      scope.delete(name)
    else
      scope[name] = value
    end
  end

  def export(name : StringName)
    val = self[name]
    set_env(name, val)
  end

  def make_variable_global(name : StringName)
    if scope = find_scope
      if val = scope.delete(name)
        @global[name] = val
      end
    end
  end

  protected def global=(val)
    @global = val
  end

  protected def vars=(val)
    @vars = val
  end

  def dup : self
    stack = self.class.new
    stack.global = @global.dup
    stack.vars = @vars.dup
    stack
  end
end
