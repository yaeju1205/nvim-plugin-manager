--- @diagnostic disable
local fn = vim.fn
local opt = vim.opt
local env = vim.env
local schedule = vim.schedule
local system = vim.system
local log = vim.log
local notify = vim.notify
local tbl_extend = vim.tbl_extend
--- @diagnostic enable

--- @class PluginManager
--- @field plugins_directory string
local plugin_manager = {}
plugin_manager.plugins_directory = fn.expand(fn.stdpath("data") .. "/nvim-plugins")
plugin_manager.username = env.USER or env.LOGNAME or env.USERNAME or "unknown"
plugin_manager.git_host = "github.com"
plugin_manager.git_prefix = "https://" .. plugin_manager.git_host .. "/"

--- @type table<string, PluginManager.PluginSpec>
local plugin_specs = {}

--- @class PluginManager.PluginSpec
--- @field origin? string
--- @field name string
--- @field drive string
--- @field version? string
--- @field branch? string
--- @field requires? { origin: string, options?: PluginManager.InstallOptions }[] 

--- @class PluginManager.InstallOptions
--- @field name? string
--- @field version? string
--- @field branch? string
--- @field requires? { origin: string, options?: PluginManager.InstallOptions }[] 

--- @param origin string
--- @return string
local function get_git_normal_origin(origin)
    local host = origin:match("//([^/]+)") or origin:match("@([^:]+)")
    if not host then
        origin = plugin_manager.git_prefix .. origin
    end
    return origin
end

--- @param origin string
--- @return string, string, string
local function get_git_origin_info(origin)
    local host = origin:match("//([^/]+)") or origin:match("@([^:]+)")
    if not host then
        host = plugin_manager.git_host
        origin = plugin_manager.git_prefix .. origin
    end

    origin = origin:gsub("^%w+://", ""):gsub("^git@", "")
    origin = origin:gsub(":", "/")
    origin = origin:gsub("%.git$", "")

    local slash_parts = {}
    for part in origin:gmatch("[^/]+") do
        table.insert(slash_parts, part)
    end
    local count = #slash_parts
    local owner = slash_parts[count - 1]
    local repo = slash_parts[count]
    return host, owner, repo
end

--- @param host string
--- @param owner string
--- @param name string
local function get_origin_drive(host, owner, name)
    return fn.expand(plugin_manager.plugins_directory .. "/" .. host .. "/" .. owner .. "/" .. name)
end

--- @param origin string
--- @param options PluginManager.InstallOptions
--- @return string[], PluginManager.PluginSpec
local function get_git_origin_install_command_and_info(origin, options)
    local host, owner, name = get_git_origin_info(origin)
    local drive = get_origin_drive(host, owner, name)
    local command = { "git", "clone", "--filter=blob:none", "--depth=1" }
    if options.version then
        command[5] = "--branch"
        command[6] = options.version
        command[7] = "--single-branch"
        command[8] = get_git_normal_origin(origin)
        command[9] = drive
    elseif options.branch then
        command[5] = "--branch"
        command[6] = options.branch
        command[7] = get_git_normal_origin(origin)
        command[8] = drive
    else
        command[5] = get_git_normal_origin(origin)
        command[6] = drive
    end
    return command, tbl_extend("force", {
        name = name,
        drive = drive,
        origin = origin
    }, options)
end

--- @param spec PluginManager.PluginSpec
function plugin_manager.load(spec)
    if spec.requires then
        for _, include in ipairs(spec.requires) do
            plugin_manager.install_sync(include.origin, include.options)
        end
    end
    plugin_specs[spec.name] = spec
    opt.rtp:append(spec.drive)
end

--- @param origin string
--- @param options? PluginManager.InstallOptions
--- @return fun (callback: fun(spec: PluginManager.PluginSpec))
function plugin_manager.install(origin, options)
    local command, spec = get_git_origin_install_command_and_info(origin, options or {})
    if fn.isdirectory(spec.drive) == 1 then
        return function(callback)
            schedule(function()
                plugin_manager.load(spec)
                callback(spec)
            end)
        end
    end
    return function(callback)
        if system then
            system(command, { text = true }, function(obj)
                schedule(function()
                    if obj.code ~= 0 then
                        local err_msg = (obj.stderr ~= "" and obj.stderr) or "Unknown error"
                        return notify("Install git clone error: " .. obj.code .. "):\n" .. err_msg, log.levels.ERROR)
                    end
                    plugin_manager.load(spec)
                    callback(spec)
                end)
            end)
        else
            schedule(function()
                local output = fn.system(table.concat(command, " "))
                ---@diagnostic disable-next-line
                if vim.v.shell_error ~= 0 then
                    return notify("Faild install\n" .. output, log.levels.ERROR)
                end
                plugin_manager.load(spec)
                callback(spec)
            end)
        end
    end
end

--- @param origin string
--- @param options? PluginManager.InstallOptions
function plugin_manager.install_sync(origin, options)
    local command, spec = get_git_origin_install_command_and_info(origin, options or {})
    if fn.isdirectory(spec.drive) == 1 then
        return plugin_manager.load(spec)
    end
    if system then
        local obj = system(command, { text = true }):wait()
        if obj.code ~= 0 then
            local err_msg = (obj.stderr ~= "" and obj.stderr) or "Unknown error"
            return notify("Install git clone error: " .. obj.code .. "):\n" .. err_msg, log.levels.ERROR)
        end
    else
        local output = fn.system(table.concat(command, " "))
        ---@diagnostic disable-next-line
        if vim.v.shell_error ~= 0 then
            return notify("Faild install\n" .. output, log.levels.ERROR)
        end
    end
    plugin_manager.load(spec)
end

--- @param name string
--- @param drive string
--- @return fun (callback: fun(spec: PluginManager.PluginSpec))
function plugin_manager.install_user_plugin(name, drive)
    --- @type PluginManager.PluginSpec
    local spec
    if fn.isdirectory(drive) == 1 then
        spec = {
            name = name,
            drive = drive,
        }
        plugin_manager.load(spec)
    else
        notify("Unknown user plugin drive: " .. drive, log.levels.WARN)
    end
    return function(callback)
        schedule(function()
            callback(spec)
        end)
    end
end

--- @param name string
--- @param drive string
function plugin_manager.install_user_plugin_sync(name, drive)
    local spec
    if fn.isdirectory(drive) == 1 then
        spec = {
            name = name,
            drive = drive,
        }
        plugin_manager.load(spec)
    else
        notify("Unknown user plugin drive: " .. drive, log.levels.WARN)
    end
end

--- @param plugin string
function plugin_manager.upgrade(plugin)
    local spec = plugin_specs[plugin]
    if not spec then
        return notify("Unknown plugin: " .. plugin, log.levels.WARN)
    end
    if fn.isdirectory(spec.drive) == 1 then
        local command = { "git", "pull", "--ff-only" }
        if system then
            system(command, { cwd = spec.drive, text = true }, function(obj)
                if obj.code ~= 0 then
                    local err_msg = (obj.stderr ~= "" and obj.stderr) or "Unknown error"
                    return notify("Upgrade git pull error: " .. obj.code .. "):\n" .. err_msg, log.levels.ERROR)
                end
            end)
        else
            local old_cwd = fn.getcwd()
            local output
            fn.chdir(spec.drive)
            output = fn.system(table.concat(command, " "))
            fn.chdir(old_cwd)
            ---@diagnostic disable-next-line
            if vim.v.shell_error ~= 0 then
                return notify("Faild upgrade\n" .. output, log.levels.ERROR)
            end
        end
    else
        if not spec.origin then
            return notify("Plugin " .. spec.name .. " not has origin" .. plugin, log.levels.WARN)
        end
        --- @diagnostic  disable-next-line
        plugin_manager.install(spec.origin, spec)
    end
end

--- @param plugin string
function plugin_manager.remove(plugin)
    local spec = plugin_specs[plugin]
    if not spec then
        return notify("Unknown plugin: " .. plugin, log.levels.WARN)
    end
    if fn.isdirectory(spec.drive) == 1 then
        opt.rtp:remove(spec.drive)
    else
        return notify("Plugin " .. spec.name .. " not found" .. plugin, log.levels.WARN)
    end
end

--- @param plugin string
function plugin_manager.delete(plugin)
    local spec = plugin_specs[plugin]
    if not spec then
        return notify("Unknown plugin: " .. plugin, log.levels.WARN)
    end
    plugin_manager.remove(plugin)
    if fn.has("win32") == 1 then
        if system then
            system({ "rmdir", "/s", "/q", spec.drive })
        else
            schedule(function()
                fn.system(string.format('rmdir /s /q "%s"', spec.drive))
            end)
        end
    else
        if system then
            system({ "rm", "-r", spec.drive })
        else
            schedule(function()
                fn.system("rm -r" .. spec.drive)
            end)
        end
    end
end

return plugin_manager

