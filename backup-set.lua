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
      timerBackup = nil,
      timerPrune = nil,
      currentTask = nil,
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
   if "disabled" == self.intervals.backup then
      return
   end
   local nextBackup = (self.lastBackup or os.time()) + self.intervals.backup - os.time()
   -- if nextBackup is in the past (i.e., < 0), then set it to run a minute from now
   if nextBackup <= 0 then
      nextBackup = 60
   end
   self.timerBackup = hs.timer.new(
      nextBackup,
      function()
         self:goBackup()
      end,
      true -- continueOnError
   )
   self.status = nil
   self.timerBackup:start()
end

function obj:startPrune()
   if "disabled" == self.intervals.prune then
      return
   end
   local nextPrune = (self.lastPrune or os.time()) + self.intervals.prune - os.time()
   -- if nextPrune is in the past (i.e., < 0), then set it to run a minute from now
   if nextPrune <= 0 then
      nextPrune = 60
   end
   self.timerPrune = hs.timer.new(
      nextPrune,
      function()
         self:goPrune()
      end,
      true -- continueOnError
   )
   self.status = nil
   self.timerPrune:start()
end

function obj:pause()
   -- FIXME
end

function obj:unpause()
   -- FIXME
   -- force timer reset?
end

function obj:stop()
   -- FIXME
end

function obj:goBackup()
   if "disabled" == self.intervals.backup then
      self.app:stateFileWrite()
      return
   end

   if self.app.conf.debug then print("BackupSpoon:", "backup trigger for set '" .. self.id .. "'") end

   -- avoid backup up while prune runs! try again in 5min
   if "running" == self.status then
      if self.app.conf.debug then print("BackupSpoon:", "backup delayed while prune running for set '" .. self.id .. "'") end
      self.timerBackup:setNextTrigger(300)
      return
   end

   self:helper(1, "backup")
end

function obj:goPrune()
   if "disabled" == self.intervals.prune then
      self.app:stateFileWrite()
      return
   end

   if self.app.conf.debug then print("BackupSpoon:", "prune trigger for set '" .. self.id .. "'") end

   -- avoid pruning while backup runs! try again in 5min
   if "running" == self.status then
      if self.app.conf.debug then print("BackupSpoon:", "prune delayed while backup running for set '" .. self.id .. "'") end
      self.timerPrune:setNextTrigger(300)
      return
   end

   self:helper(1, "prune")
end

function obj:helper(backupIdx, runType)
   local entry = self.backups[backupIdx]
   if not entry then
      -- base case: after last run, so finished successfully
      if "prune" == runType then
         self.lastPrune = os.time()
         self.timerPrune:setNextTrigger(self.intervals.prune)
      else
         self.lastBackup = os.time()
         self.timerBackup:setNextTrigger(self.intervals.backup)
      end
      if "stopped" == savedStatus then
         self:updateStatus("stopped")
      else
         self:updateStatus("ok")
      end
      self.app:stateFileWrite()
   elseif "function" == type(entry.command) then
      -- simple: call the command, recurse
      entry.command()
      self:helper(backupIdx + 1, runType)
   elseif "table" == type(entry.command) then
      self.currentTask = hs.task.new(
         entry.command, -- FIXME: Does this need path resolution?
         function(code, stdout, stderr)
            if 0 == code then
               if self.app.conf.debug then print("BackupSpoon:", "task successful: " .. self.id .. ", " .. entry.id) end
               -- recurse to the next entry
               self:helper(backupIdx + 1, runType)
            else
               -- task failed or interrupted; its status needs to be updated
               -- externally
               if self.app.conf.debug then print("BackupSpoon:", "task did not succeed, status: " .. status) end
               -- do not recurse to the next entry, retry the whole run later
               if "prune" == runType then
                  self.timerPrune:setNextTrigger(300)
               else
                  self.timerBackup:setNextTrigger(300)
               end
            end
         end
      )
   end
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
   if self.lastBackup then
      res[#res+1] = {
         title = "   - last backup: " .. os.date(fmt, self.lastBackup),
         disabled = true
      }
   end
   if self.lastPrune then
      res[#res+1] = {
         title = "   - last prune: " .. os.date(fmt, self.lastPrune),
         disabled = true
      }
   end
   if self.timerBackup then
      res[#res+1] = {
         title = "   - next backup: " .. os.date(fmt, math.floor(os.time() + self.timerBackup:nextTrigger())),
         disabled = true
      }
   end
   if self.timerPrune then
      res[#res+1] = {
         title = "   - next prune: " .. os.date(fmt, math.floor(os.time() + self.timerPrune:nextTrigger())),
         disabled = true
      }
   end
   -- done
   return res;
end

function obj:updateStatus(newStatus)
   self.status = newStatus
   self.app:updateMenuIcon()
end

return obj
