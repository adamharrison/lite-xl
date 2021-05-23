local process = {}

process.__gc = function(self)
  self:terminate()
end
process.__index = function(self, key) 
  return rawget(process, key) or rawget(self, key)
end
process.signal = function(self, signal) 
  return system.psignal(self.pid, signal)
end
process.write = function(self, buffer)
  return system.pwrite(self.output, buffer)
end
process.read = function(self, length)
  return system.pread(self.input)
end
process.terminate = function(self) 
  self:signal("TERM")
  system.pclose(self.input, self.output)
end
process.kill = function(self) 
  self:signal("KILL")
  system.pclose(self.input, self.output)
end

process.popen = function(cmd, ...)
  local proc = {}
  setmetatable(proc, process)
  proc.pid, proc.input, proc.output = system.popen(cmd, ...)
  return proc
end

return process

