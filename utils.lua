local obj = { name = "Utils" }
obj.__index = obj

function obj.findExecutable(name)
   local candidate = hs.fs.displayName(name)
   if candidate then
      return hs.fs.pathToAbsolute(name)
   end
   local path = hs.fnutils.concat(obj.app.conf.path, {"/usr/bin", "/bin"})
   for idx, entry in ipairs(obj.app.conf.path) do
      candidate = hs.fs.displayName(entry .. "/" .. name)
      if candidate then
         return hs.fs.pathToAbsolute(entry .. "/" .. name)
      end
   end
end

function obj.split(str, sep)
   if sep == nil then
      sep = "%s"
   end
   local t = {}
   for str in string.gmatch(str, "([^" .. sep .. "]+)") do
      table.insert(t, str)
   end
   return t
end

function obj.trim(str)
   return (str:gsub("^%s*(.-)%s*$", "%1"))
end

function obj.len(tbl)
   local l = 0
   for k, v in pairs(tbl) do
      l = l + 1
   end
   return l
end

function obj.readEnvs(desc)
   local envs = {}
   for idx, env in ipairs(desc) do
      if env.value then
         envs[env.var] = env.value
      elseif env.command and "table" == type(env.command) then
         -- command breakdown
         local splits = hs.fnutils.copy(env.command)
         local cmd = obj.findExecutable(table.remove(splits, 1))
         if cmd then
            realCmd = cmd .. " \"" .. table.concat(splits, "\" \"") .. "\""
            local resOutput, resStatus, resType, resRc = hs.execute(realCmd)
            if resStatus then
               envs[env.var] = obj.trim(resOutput)
            else
               self:notify("error", "Failed command " .. realCmd)
            end
         else
            self:notify("error", "Misconfigured command for " .. env.var)
         end
      else
         self:notify("error", "Misconfigured root environment for " .. env.var)
      end
   end
   return envs
end

return obj