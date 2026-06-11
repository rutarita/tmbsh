require "./spec_helper"

describe TMBSH do
  # TODO: Write tests
    it "runs examples" do
      interpreter = TMBSH::Interpreter.new
      path = Path["../examples/static"]
      failed_files = [] of {Path, Exception}
      Dir.children(path).each do |file|
        target = path / file
        puts "Executing #{target}..."
        interpreter.execute_file(target)
        puts
        interpreter.reset
      end
      # failed_files.empty?.should be_true
  end
end
