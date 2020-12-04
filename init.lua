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
obj.env = {}
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
   BackupSet.app = self
   -- process conf file: sensible defaults
   if not self.conf.state_file then
      self.conf.state_file = "~/.config/BackupSpoon-state.lua"
   end
   if not self.conf.path then
      self.conf.path = { "/bin", "/usr/bin", "/usr/local/bin" }
   end
   if not self.conf.exclude_wifi_networks then
      self.conf.exclude_wifi_networks = {}
   end
   if not self.conf.interval_backup then
      self.conf.interval_backup = "1 hour"
   end
   if not self.conf.interval_prune then
      self.conf.interval_prune = "1 month"
   end
   if not self.conf.debug then
      self.conf.debug = false
   end
   -- process root environment variables
   self.env = Utils.readEnvs(self.conf.environment)
   -- -- process conf file: for each backup set, create a new BackupSet object
   -- for idx, set in ipairs(self.conf.sets) do
   --    -- local path = "string" == type(repo) and repo or repo.path
   --    -- local interval = ("table" == type(repo) and repo.interval) and repo.interval or self.conf.interval
   --    if "table" == type(repo) and repo.excludes then
   --       if "table" == type(repo.excludes) then
   --          -- join excludes using the bell character \a, since it's unlikely to
   --          -- be used in file names, and both Lua and bash can handle it
   --          excludes = table.concat(repo.excludes, "\a")
   --       else
   --          excludes = repo.excludes
   --       end
   --    end
   --    self.syncs[#self.syncs+1] = Sync.new(path, interval, excludes)
   -- end
   -- if 0 == #self.sets then
   --    self:notify("error", "No backup sets defined. Check configuration.")
   -- end
   -- set up menu icon
   self.menu = hs.menubar.new()
   self:updateMenuIcon()
   --self.menu:setMenu(self.makeMenuTable)
   -- -- activate system watcher
   -- self.watcher = hs.caffeinate.watcher.new(
   --    function(evt)
   --       self:systemWatchFn(evt)
   --    end
   -- )
   -- -- go
   -- self:start()
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
   -- for idx, set in ipairs(obj.sets) do
   --    set:start()
   -- end
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
   -- for idx, set in ipairs(obj.sets) do
   --    set:stop()
   -- end
   -- obj.active = false
   obj:updateMenuIcon()
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

return obj
