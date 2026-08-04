require "./parser"
require "./nodes"
module TMBSH
  class Parser

    private def unexpected_math_token
      raise UnexpectedToken.new("Unexpected token when parsing math expression: #{@lexer.math_token}")
    end

    # private macro add_operation(op)
    #   unexpected_math_token if await_value
    #   if operation != {{op}}
    #   math_expr.add_part(parts, operation)
    #   operation = MathExpressionNode::Operation::{{op}}
    #   end
    #   await_value = true
    # end

    def parse_math_expression : Interpreter::MathExpressionNode
      # next_char
      math_expr = Interpreter::MathExpressionNode.new
      adding = true
      parts = [] of Int64 | Float64 | Interpreter::MathExpressionNode | Interpreter::VariableRef
      operation = Interpreter::MathExpressionNode::Operation::None
      expect_value = true
      loop do
        token = @lexer.next_math_token
        case token.kind
          when .number?
            # math_expr.add_part(token.raw_value.as(Int64 | Float64))
          when .variable?
            # math_expr.dd_part(Interpreter::VariableRef.new(token.raw_value.as(::String)))
            unexpected_math_token unless expect_value
            parts << Interpreter::VariableRef.new(token.raw_value.as(::String))
          when .plus?
            unexpected_math_token if expect_value
            unless operation == Interpreter::MathExpressionNode::Operation::Add
            operation = Interpreter::MathExpressionNode::Operation::Add
            # math_expr.add_part(parts, )
            end
          # when .plus?
          #   math_expr.add_part(:Add)
          # when .minus?
          #   math_expr.add_part(:Sub)
          # when .star?
          #   math_expr.add_part(:Mul)
          # when .slash?
          #   math_expr.add_part(:Div)
          when .parenthesis_open?
            # math_expr.add_part(parse_math_expression)
          when .parenthesis_close?
            break
        end
      # math_expr
      end
      # parts = [] of Int64 | Float64 | MathExpressionNode
      # await_value = true
      # operation = MathExpressionNode::Operation::None
      # loop do
      # token = @lexer.next_math_token
      #   case token.kind
      #     when .number?
      #       unexpected_math_token unless await_value
      #       numbers << token.raw_value.as(Int64 | Float64 | MathExpressionNode)
      #       await_value = false
      #     when .plus?
      #       add_operation(Plus)
      #   end
      # end
      math_expr
    end
  end
end
