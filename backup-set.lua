local obj = { name = "BackupSet" }
obj.__index = obj

function obj.new(displayPath, interval)
   local self = {
      displayPath = displayPath,
      interval = interval,
      lastBackup = nil,
      status = nil,
      started = nil,
      timer = nil,
      task = nil
   }
   setmetatable(self, obj)
   return self
end

function obj:start()
end

function obj:pause()
end

function obj:unpause()
end

function obj:stop()
end

function obj:go()
end

function obj:display()
end

function obj:updateStatus(newStatus)
end

return obj
