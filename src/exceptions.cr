module TMBSH
  abstract class Exception < ::Exception
  end

  class MethodDoesNotExist < Exception
  end
  class ArgumentError < Exception
  end
  class TypeError < Exception
  end
end
