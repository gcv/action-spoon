local obj = { name = "BackupSet" }
obj.__index = obj

function obj.new(id, intervals, env, backups)
   local self = {
      id = id,
      intervals = intervals,
      env = env,
      backups = backups,
      lastBackup = nil,
      lastPrune = nil,
      status = nil,
      startedBackup = nil,
      startedPrune = nil,
      timerBackup = nil,
      timerPrune = nil,
      task = nil
   }
   setmetatable(self, obj)
   return self
end

function obj:start()
   if self.app.conf.debug then print("BackupSpoon:", "starting timers for set '" .. self.id .. "'") end
   self:startBackup()
   self:startPrune()
end

function obj:startBackup()
   self.timerBackup = hs.timer.new(
      self.intervals.backup,
      function()
         self:goBackup()
      end,
      true -- continueOnError
   )
   self.startedBackup = os.time()
   self.status = nil
   self.timerBackup:start()
end

function obj:startPrune()
   self.timerPrune = hs.timer.new(
      self.intervals.prune,
      function()
         self:goPrune()
      end,
      true -- continueOnError
   )
   self.startedPrune = os.time()
   self.status = nil
   self.timerPrune:start()
end

function obj:pause()
end

function obj:unpause()
end

function obj:stop()
end

function obj:goBackup()
   if self.app.conf.debug then print("BackupSpoon:", "backup trigger for set '" .. self.id .. "'") end
   
end

function obj:goPrune()
   if self.app.conf.debug then print("BackupSpoon:", "prune trigger for set '" .. self.id .. "'") end

end

function obj:display()
   local res = {}
   local fmt = "%Y-%m-%d (%a) %X" -- equivalent to "%H:%M:%S"
   local setTitle = ""
   -- status
   if "ok" == self.status then
      setTitle = setTitle .. "✓"
   elseif "error" == self.status then
      setTitle = setTitle .. "!"
   elseif "running" == self.status then
      setTitle = setTitle .. "⟳"
   elseif "stopped" == self.status then
      setTitle = setTitle .. "×"
   else
      setTitle = setTitle .. "•"
   end
   -- path
   setTitle = setTitle .. " " .. self.id .. ": " ..
      -- join visible titles of all backups in the set
      table.concat(self.app.Utils.map(
                      function (b)
                         return b.id
                      end,
                      self.backups),
                   ", ")
   res[#res+1] = {
      title = setTitle,
      disabled = ("running" == self.status),
      fn = function()
         self:goBackup()
      end
   }
   -- additional information
   if self.timerBackup then
      res[#res+1] = {
         title = "   - next backup: " .. os.date(fmt, math.floor(os.time() + self.timerBackup:nextTrigger())),
         disabled = true
      }
   end
   if self.lastBackup then
      res[#res+1] = {
         title = "   - last backup: " .. os.date(fmt, self.lastBackup),
         disabled = true
      }
   end
   if self.timerPrune then
      res[#res+1] = {
         title = "   - next prune: " .. os.date(fmt, math.floor(os.time() + self.timerPrune:nextTrigger())),
         disabled = true
      }
   end
   if self.lastPrune then
      res[#res+1] = {
         title = "   - last prune: " .. os.date(fmt, self.lastPrune),
         disabled = true
      }
   end
   -- done
   return res;
end

function obj:updateStatus(newStatus)
end

return obj
