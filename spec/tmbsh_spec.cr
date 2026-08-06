require "./spec_helper"

describe TMBSH do
  # TODO: Write tests
    it "runs examples" do
      interpreter = TMBSH::Interpreter.new
      path = Path["examples/static"]
      Dir.children(path).each do |file|
        target = path / file
        puts "Executing #{target}..."
        interpreter.execute_file(target, raise_on_error: true)
        puts
        interpreter.reset
      end
  end
end
