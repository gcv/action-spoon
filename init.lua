--- === Backup Spoon ===
---
--- Orchestrates automatic backup of local data using command-line utilities
--- such as Restic, Kopia, and Borg.
---
--- Download: https://github.com/gcv/backup-spoon/releases/download/0.0.0/Backup.spoon.zip

local obj = {}
obj.__index = obj

--- Metadata
obj.name = "Backup"
obj.version = "0.0.0"
obj.author = "gcv"
obj.homepage = "https://github.com/gcv/backup.spoon"
obj.license = "CC0"

--- Internal function used to find code location.
local function scriptPath()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end
obj.spoonPath = scriptPath()

--- Objects:
local Utils = dofile(obj.spoonPath .. "/utils.lua")
local BackupSet = dofile(obj.spoonPath .. "/backup-set.lua")

--- Internal state:
obj.confFile = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/BackupSpoon.lua"
obj.conf = {}
obj.state = {}
obj.sets = {}
obj.active = false
obj.watcher = nil

--- Resources:
obj.menuIconNormal = hs.image.imageFromPath(obj.spoonPath .. "/resources/menu-icon-normal.png")
obj.menuIconError = hs.image.imageFromPath(obj.spoonPath .. "/resources/menu-icon-error.png")
obj.menuIconInactive = hs.image.imageFromPath(obj.spoonPath .. "/resources/menu-icon-inactive.png")
obj.notifyIconNormal = hs.image.imageFromPath(obj.spoonPath .. "/resources/notify-icon-normal.png")
obj.notifyIconError = hs.image.imageFromPath(obj.spoonPath .. "/resources/notify-icon-error.png")

--- Backup:init()
--- Method
--- Initialize Backup.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj:init()
   -- read conf file
   local confFn, err = loadfile(self.confFile, "t", self.conf)
   if confFn then
      confFn()
   else
      print("BackupSpoon:", err)
      obj:notify("error", "Failed to load. Missing configuration file?")
      return
   end
   -- bail out if disabled; omission equivalent to "enabled = true"
   if nil ~= self.conf.enabled and (not self.conf.enabled) then
      return
   end
   -- version check
   -- FIXME:
   --self:versionCheck()
   -- configure helper object prototypes
   Utils.app = self
   self.Utils = Utils
   BackupSet.app = self
   -- process conf file: sensible defaults
   if not self.conf.state_file then
      self.conf.state_file = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/BackupSpoon-state.lua"
   else
      -- FIXME: Resolve ~ in whatever is given here.
   end
   if not self.conf.path then
      self.conf.path = { "/bin", "/usr/bin", "/usr/local/bin" }
   end
   if not self.conf.exclude_wifi_networks then
      self.conf.exclude_wifi_networks = {}
   end
   if not self.conf.intervals then
      self.conf.intervals = {
         backup = 60 * 60,          -- 1 hour
         prune = 60 * 60 * 24 * 30, -- 30 days
      }
   end
   if not self.conf.intervals.backup then
      self.conf.intervals.backup = 60 * 60           -- 1 hour
   end
   if not self.conf.intervals.prune then
      self.conf.intervals.prune = 60 * 60 * 24 * 30  -- 30 days
   end
   if not self.conf.debug then
      self.conf.debug = false
   end
   -- process root environment variables
   self.conf.env = Utils.readEnvs(self.conf.environment)
   -- process conf file: for each backup set, create a new BackupSet object
   for idx, set in ipairs(self.conf.sets) do
      local id = set.id
      local intervals = set.intervals or self.conf.intervals
      intervals.backup = intervals.backup or self.conf.intervals.backup
      intervals.prune = intervals.prune or self.conf.intervals.prune
      local env = Utils.merge(self.conf.env, Utils.readEnvs(set.environment))
      local backups = set.backups
      self.sets[#self.sets+1] = BackupSet.new(id, intervals, env, backups)
   end
   if 0 == #self.sets then
      self:notify("error", "No backup sets defined. Check configuration.")
   end
   -- process state file
   self:stateFileRead()
   -- set up menu icon
   self.menu = hs.menubar.new()
   self:updateMenuIcon()
   self.menu:setMenu(self.makeMenuTable)
   -- activate system watcher
   -- self.watcher = hs.caffeinate.watcher.new(
   --    function(evt)
   --       self:systemWatchFn(evt)
   --    end
   -- )
   -- go
   self:start()
   return self
end

--- Backup:start()
--- Method
--- Start Backup.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj:start()
   obj.active = true
   for idx, set in ipairs(obj.sets) do
      set:start()
   end
   -- obj.watcher:start()
   obj:updateMenuIcon()
end

--- Backup:stop()
--- Method
--- Stop Backup.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj:stop()
   -- obj.watcher:stop()
   for idx, set in ipairs(obj.sets) do
      set:stop()
   end
   obj.active = false
   obj:updateMenuIcon()
end

function obj:makeMenuTable()
   local res = {}
   res[#res+1] = { title = "-" }
   for idx, set in ipairs(obj.sets) do
      local displayItems = set:display()
      for _, displayItem in ipairs(displayItems) do
         res[#res+1] = displayItem
      end
   end
   res[#res+1] = { title = "-" }
   res[#res+1] = {
      title = "Debug...",
      fn = function()
         print("State:", hs.inspect(obj.state))
         print("Sets:", hs.inspect(obj.sets))
      end
   }
   if obj.active then
      res[#res+1] = {
         title = "Disable",
         fn = function()
            obj.stop()
         end
      }
   else
      res[#res+1] = {
         title = "Enable",
         fn = function()
            obj.start()
         end
      }
   end
   return res
end

function obj:updateMenuIcon()
   if not obj.active then
      if obj.menu:icon() ~= obj.menuIconInactive then
         obj.menu:setIcon(obj.menuIconInactive, false)
      end
      return
   end
   for idx, set in ipairs(obj.sets) do
      if "error" == set.status then
         if obj.menu:icon() ~= obj.menuIconError then
            obj.menu:setIcon(obj.menuIconError, false)
         end
         return
      end
   end
   if obj.menu:icon() ~= obj.menuIconNormal then
      obj.menu:setIcon(obj.menuIconNormal, true)
   end
end

function obj:notify(kind, text)
   local msg = hs.notify.new(
      nil,
      {
         title = "Backup Spoon",
         informativeText = text,
         withdrawAfter = 0,
         setIdImage = ("error" == kind) and obj.notifyIconError or obj.notifyIconNormal
      }
   )
   msg:send()
end

function obj:stateFileRead()
   local stateFileFn, err = loadfile(obj.conf.state_file, "t", obj.state)
   if stateFileFn then
      stateFileFn()
   else
      -- state file missing, this is fine
   end
   -- reconcile the state file with the configuration
   for idxSet, set in ipairs(obj.sets) do
      if obj.state[set.id] then
         if obj.state[set.id].lastBackup then
            set.lastBackup = obj.state[set.id].lastBackup
         end
         if obj.state[set.id].lastPrune then
            set.lastPrune = obj.state[set.id].lastPrune
         end
      end
   end
end

function obj:stateFileWrite()
   local outStr = ""
   local fmt = "%Y-%m-%d (%a) %X" -- equivalent to "%H:%M:%S"
   for idxSet, set in ipairs(obj.sets) do
      -- if last* is missing, set it to now to get the ball rolling
      local lastBackup = set.lastBackup or os.time()
      local lastPrune = set.lastPrune or os.time()
      outStr = outStr .. set.id .. " = {\n"
      outStr = outStr .. "   lastBackup = " .. lastBackup .. ", -- " .. os.date(fmt, lastBackup) .. "\n"
      outStr = outStr .. "   lastPrune  = " .. lastPrune  .. "  -- " .. os.date(fmt, lastPrune) .. "\n"
      outStr = outStr .. "}\n"
   end
   local fh = io.open(obj.conf.state_file, "w")
   fh:write(outStr)
   fh:close()
end

return obj
