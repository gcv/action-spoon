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
      task = nil,
   }
   setmetatable(self, obj)
   return self
end

function obj:start()
   if self.app.conf.debug then print("BackupSpoon:", "starting timers for set '" .. self.id .. "'") end
   self:startBackup()
   self:startPrune()
end

function obj:stop()
   if "stopped" == self.status then
      -- do nothing
      return
   end
   -- if a task is running, we must interrupt it
   if "running" == self.status and self.task and self.task:isRunning() then
      self.task:interrupt()
   end
   -- stop the timers
   if self.timerBackup then
      if self.app.conf.debug then print("BackupSpoon:", "stopping backup timer for set '" .. self.id .. "'") end
      self.timerBackup:stop()
   end
   if self.timerPrune then
      if self.app.conf.debug then print("BackupSpoon:", "stopping prune timer for set '" .. self.id .. "'") end
      self.timerPrune:stop()
   end
   self:updateStatus("stopped")
end

function obj:startBackup()
   if "disabled" == self.intervals.backup then
      if self.app.conf.debug then print("BackupSpoon:", "backup for set id '" .. self.id .. "' disabled in configuration") end
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
      if self.app.conf.debug then print("BackupSpoon:", "prune for set id '" .. self.id .. "' disabled in configuration") end
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

function obj:goBackup()
   if "disabled" == self.intervals.backup then
      self.app:stateFileWrite()
      return
   end

   if self.app.conf.debug then print("BackupSpoon:", "backup trigger for set '" .. self.id .. "'") end

   -- avoid backup up while prune runs! try again in 5min
   if "running" == self.status then
      if self.app.conf.debug then print("BackupSpoon:", "backup delayed while another task is (still?) running for set '" .. self.id .. "'") end
      self.timerBackup:setNextTrigger(self.intervals.poll)
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
      if self.app.conf.debug then print("BackupSpoon:", "prune delayed while another task is (still?) running for set '" .. self.id .. "'") end
      self.timerPrune:setNextTrigger(self.intervals.poll)
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
      self:updateStatus("ok")
      self.task = nil
      self.app:stateFileWrite()
   elseif "function" == type(entry.command) then
      -- simple: call the command, recurse
      entry.command()
      self:updateStatus("running")
      self:helper(backupIdx + 1, runType)
   elseif "table" == type(entry.command) then
      local splits
      if "prune" == runType then
         splits = hs.fnutils.copy(entry.prune)
      else
         splits = hs.fnutils.copy(entry.command)
      end
      local cmd = self.app.Utils.findExecutable(table.remove(splits, 1))
      self.task = hs.task.new(
         cmd,
         function(code, stdout, stderr)
            if 0 == code then
               if self.app.conf.debug then print("BackupSpoon:", "task successful: " .. self.id .. ", " .. entry.id .. ", " .. runType) end
               -- recurse to the next entry
               self:helper(backupIdx + 1, runType)
            else
               -- task failed or interrupted
               if "interrupt" == self.task:terminationReason() then
                  if self.app.conf.debug then print("BackupSpoon:", "task interrupted, code: " .. code .. ", stderr:" .. stderr) end
                  if self.status ~= "stopped" then
                     self:updateStatus("interrupted")
                  end
               else
                  -- always print errors to console, regardless of debug flag
                  print("BackupSpoon:", "task failed, code: " .. code .. ", stderr:" .. stderr)
                  self.app:notify("error", "Task failed: " .. self.id .. ", " .. entry.id)
                  self:updateStatus("error")
               end
               -- do not recurse to the next entry, retry the whole run later
               if "stopped" ~= self.status then
                  if "prune" == runType then
                     self.timerPrune:setNextTrigger(self.intervals.poll)
                  else
                     self.timerBackup:setNextTrigger(self.intervals.poll)
                  end
               end
            end
         end,
         splits -- rest of the args
      )
      local taskEnv = self.app.Utils.merge(self.task:environment(), self.env)
      self:updateStatus("running")
      self.task:start()
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
      -- nil or "interrupted"
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
      disabled = ("running" == self.status or "stopped" == self.status),
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
