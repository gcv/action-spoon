local obj = { name = "BackupSet" }
obj.__index = obj

function obj.new(id, interval_backup, interval_prune, env, backups)
   local self = {
      id = id,
      interval_backup = interval_backup,
      interval_prune = interval_prune,
      env = env,
      backups = backups,
      lastRun = nil,
      status = nil,
      started = nil,
      timer = nil,
      task = nil
   }
   setmetatable(self, obj)
   return self
end

function obj:start()
   if self.app.conf.debug then print("BackupSpoon:", "starting periodic backup for set '" .. self.id .. "'") end

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
   local fmt = "%X" -- equivalent to "%H:%M:%S"
   local resTitle = ""
   -- status
   if "ok" == self.status then
      resTitle = resTitle .. "✓"
   elseif "error" == self.status then
      resTitle = resTitle .. "!"
   elseif "running" == self.status then
      resTitle = resTitle .. "⟳"
   elseif "stopped" == self.status then
      resTitle = resTitle .. "×"
   else
      resTitle = resTitle .. "•"
   end
   -- path
   resTitle = resTitle .. " " .. self.id
   -- last and next backup
   nextStr = ""
   if self.timer then
      nextStr = "; next: " .. os.date(fmt, math.floor(os.time() + self.timer:nextTrigger()))
   end
   if self.lastSync then
      resTitle = resTitle .. " (last: " .. os.date(fmt, self.lastSync) .. nextStr .. ")"
   elseif self.started then
      resTitle = resTitle .. nextStr
   end
   -- done
   return {
      title = resTitle,
      disabled = ("running" == self.status),
      fn = function()
         self:go()
      end
   }
end

function obj:updateStatus(newStatus)
end

return obj
