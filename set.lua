local obj = { name = "Set" }
obj.__index = obj

function obj.new(id, intervals, env, actions)
   local self = {
      id = id,
      intervals = intervals,
      env = env,
      actions = actions,
      lastAction1 = nil,
      lastAction2 = nil,
      status = nil,
      timerAction1 = nil,
      timerAction2 = nil,
      task = nil,
   }
   setmetatable(self, obj)
   return self
end

function obj:start()
   if self.app.conf.debug then print("ActionSpoon:", "starting timers for set '" .. self.id .. "'") end
   self:startAction1()
   self:startAction2()
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
   if self.timerAction1 then
      if self.app.conf.debug then print("ActionSpoon:", "stopping action1 timer for set '" .. self.id .. "'") end
      self.timerAction1:stop()
   end
   if self.timerAction2 then
      if self.app.conf.debug then print("ActionSpoon:", "stopping action2 timer for set '" .. self.id .. "'") end
      self.timerAction2:stop()
   end
   self:updateStatus("stopped")
end

function obj:startAction1()
   if "disabled" == self.intervals.action1 then
      if self.app.conf.debug then print("ActionSpoon:", "action1 for set id '" .. self.id .. "' disabled in configuration") end
      return
   end
   local nextAction1 = (self.lastAction1 or os.time()) + self.intervals.action1 - os.time()
   -- if nextAction1 is in the past (i.e., < 0), then set it to run a minute from now
   if nextAction1 <= 0 then
      nextAction1 = 60
   end
   self.timerAction1 = hs.timer.new(
      nextAction1,
      function()
         self:goAction1()
      end,
      true -- continueOnError
   )
   self.status = nil
   self.timerAction1:start()
end

function obj:startAction2()
   if "disabled" == self.intervals.action2 then
      if self.app.conf.debug then print("ActionSpoon:", "action2 for set id '" .. self.id .. "' disabled in configuration") end
      return
   end
   local nextAction2 = (self.lastAction2 or os.time()) + self.intervals.action2 - os.time()
   -- if nextAction2 is in the past (i.e., < 0), then set it to run a minute from now
   if nextAction2 <= 0 then
      nextAction2 = 60
   end
   self.timerAction2 = hs.timer.new(
      nextAction2,
      function()
         self:goAction2()
      end,
      true -- continueOnError
   )
   self.status = nil
   self.timerAction2:start()
end

function obj:goAction1()
   if "disabled" == self.intervals.action1 then
      self.app:stateFileWrite()
      return
   end

   if self.app.conf.debug then print("ActionSpoon:", "action1 trigger for set '" .. self.id .. "'") end

   -- avoid simultaneous runs! try again in <poll> min
   if "running" == self.status then
      if self.app.conf.debug then print("ActionSpoon:", "action1 delayed while another task is (still?) running for set '" .. self.id .. "'") end
      self.timerAction1:setNextTrigger(self.intervals.poll)
      return
   end

   self:helper(1, "action1")
end

function obj:goAction2()
   if "disabled" == self.intervals.action2 then
      self.app:stateFileWrite()
      return
   end

   if self.app.conf.debug then print("ActionSpoon:", "action2 trigger for set '" .. self.id .. "'") end

   -- avoid simultaneous runs! try again in <poll> min
   if "running" == self.status then
      if self.app.conf.debug then print("ActionSpoon:", "action2 delayed while another task is (still?) running for set '" .. self.id .. "'") end
      self.timerAction2:setNextTrigger(self.intervals.poll)
      return
   end

   self:helper(1, "action2")
end

function obj:helper(actionIdx, runType)
   local entry = self.actions[actionIdx]
   if not entry then
      -- base case: after last run, so finished successfully
      if "action2" == runType then
         self.lastAction2 = os.time()
         self.timerAction2:setNextTrigger(self.intervals.action2)
      else
         self.lastAction1 = os.time()
         self.timerAction1:setNextTrigger(self.intervals.action1)
      end
      self:updateStatus("ok")
      self.task = nil
      self.app:stateFileWrite()
   elseif "function" == type(entry[runType]) then
      -- simple: call the command, recurse
      entry[runType]()
      self:updateStatus("running")
      self:helper(actionIdx + 1, runType)
   elseif "table" == type(entry[runType]) then
      local splits = hs.fnutils.copy(entry[runType])
      local cmd = self.app.Utils.findExecutable(table.remove(splits, 1))
      self.task = hs.task.new(
         cmd,
         function(code, stdout, stderr)
            if 0 == code then
               if self.app.conf.debug then print("ActionSpoon:", "task successful: " .. self.id .. ", " .. entry.id .. ", " .. runType) end
               -- recurse to the next entry
               self:helper(actionIdx + 1, runType)
            else
               -- task failed or interrupted
               if "interrupt" == self.task:terminationReason() then
                  if self.app.conf.debug then print("ActionSpoon:", "task interrupted, code: " .. code .. ", stderr:" .. stderr) end
                  if self.status ~= "stopped" then
                     self:updateStatus("interrupted")
                  end
               else
                  -- always print errors to console, regardless of debug flag
                  print("ActionSpoon:", "task failed, code: " .. code .. ", stderr:" .. stderr)
                  self.app:notify("error", "Task failed: " .. self.id .. ", " .. entry.id)
                  self:updateStatus("error")
               end
               -- do not recurse to the next entry, retry the whole run later
               if "stopped" ~= self.status then
                  if "action2" == runType then
                     self.timerAction2:setNextTrigger(self.intervals.poll)
                  else
                     self.timerAction1:setNextTrigger(self.intervals.poll)
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
      -- join visible titles of all actions in the set
      table.concat(self.app.Utils.map(
                      function (b)
                         return b.id
                      end,
                      self.actions),
                   ", ")
   res[#res+1] = {
      title = setTitle,
      disabled = ("running" == self.status or "stopped" == self.status),
      fn = function()
         self:goAction1()
      end
   }
   -- additional information
   if self.lastAction1 then
      res[#res+1] = {
         title = "   - last action1: " .. os.date(fmt, self.lastAction1),
         disabled = true
      }
   end
   if self.lastAction2 then
      res[#res+1] = {
         title = "   - last action2: " .. os.date(fmt, self.lastAction2),
         disabled = true
      }
   end
   if self.timerAction1 then
      res[#res+1] = {
         title = "   - next action1: " .. os.date(fmt, math.floor(os.time() + self.timerAction1:nextTrigger())),
         disabled = true
      }
   end
   if self.timerAction2 then
      res[#res+1] = {
         title = "   - next action2: " .. os.date(fmt, math.floor(os.time() + self.timerAction2:nextTrigger())),
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
