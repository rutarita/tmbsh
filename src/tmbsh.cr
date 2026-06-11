require "./shell.cr"
require "./interpreter.cr"

shell = TMBSH::Shell.new
shell.mainloop
