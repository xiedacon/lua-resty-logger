-- Copyright (c) 2018, xiedacon.

local cjson = require "cjson.safe"
local Object = require "utility.object"
local fs = require "fs"

local ok, table_new = pcall(require, "table.new")
if not ok or type(table_new) ~= "function" then
    table_new = function() return {} end
end

local ok, table_clear = pcall(require, "table.clear")
if not ok or type(table_new) ~= "function" then
    table_clear = function(tab)
        for k, _ in pairs(tab) do
            tab[k] = nil
        end

        return tab
    end
end

local LOGGER_OUTPUT_LEVEL = os.getenv("LOGGER_OUTPUT_LEVEL") or "info"
local LEVELS = {
    error = 0,
    warn = 1,
    info = 2,
    debug = 3
}

local Logger = {
    _VERSION = '0.1',
    _logs = table_new(10000, 0),
    _opts = {
        flush_interval = 10,
        log_file = function(scope, level)
            return ngx.config.prefix() .. "logs/" .. level .. ".log"
        end,
        size = 10000,

        levels = LEVELS,
        output_level = LEVELS[LOGGER_OUTPUT_LEVEL],
        formatter = function(log)
            local log_str, err = cjson.encode(log)
            if err then return false, err end
    
            return table.concat({ ngx.localtime(), "[", log.level, "]", log_str }, " ")
        end
    }
}

setmetatable(Logger, {
    __call = function(self, opts)
        local _opts = self._opts
        local logger = {
            opts = Object.pick(Logger._opts, { "levels", "output_level", "formatter" })
        }
        
        setmetatable(logger, { __index = self })

        if type(opts) == "string" then opts = { scope = opts } end
        if type(opts.scope) ~= "string" then return nil, "opts scope should be string" end

        local ok, err = logger:set_opts(opts)
        if ok then
            return logger
        else
            return nil, err
        end
    end
})

function Logger:set_opts(opts)
    if opts.scope and type(opts.scope) ~= "string" then return false, "opts scope should be string" end
    if opts.levels and type(opts.levels) ~= "table" then return false, "opts levels should be table or nil" end
    if opts.output_level and type(opts.output_level) ~= "number" then return false, "opts output_level should be number or nil" end
    if opts.formatter and type(opts.formatter) ~= "function" then return false, "opts formatter should be function or nil" end

    self.opts = Object.assign(self.opts, opts)

    for level in pairs(self.opts.levels) do
        self[level] = function(_self, msg, meta)
            return _self:log({
                level = level,
                message = msg,
                meta = meta
            })
        end
    end

    return true
end

function Logger:set_globle_opts(opts)
    if opts.levels and type(opts.levels) ~= "table" then return false, "opts levels should be table or nil" end
    if opts.output_level and type(opts.output_level) ~= "number" then return false, "opts output_level should be number or nil" end
    if opts.formatter and type(opts.formatter) ~= "function" then return false, "opts formatter should be function or nil" end

    if opts.flush_interval and type(opts.flush_interval) ~= "number" then return false, "opts flush_interval should be number or nil" end
    if opts.log_file and type(opts.log_file) == "string" then
        local file = opts.log_file
        opts.log_file = function() return file end
    end
    if opts.log_file and type(opts.log_file) ~= "function" then return false, "opts log_file should be function or string or nil" end

    Logger._opts = Object.assign(Logger._opts, opts)

    return true
end

function Logger:flush() 
    local cache_logs = Logger._logs
    local size = Logger._opts.size
    local log_file = Logger._opts.log_file

    local logMap = {}
    for _, log in ipairs(cache_logs) do
        local file = log_file(log.scope, log.level)

        if type(file) == "string" then
            logMap[file] = logMap[file] or table_new(#cache_logs, 0)
            logMap[file][#logMap[file] + 1] = log.content
        end
    end

    if #cache_logs > size then
        table_clear(cache_logs)
        Logger._opts.size = #cache_logs
    else
        cache_logs = table.new(size)
    end

    for file, logs in pairs(logMap) do
        local ok, err = fs.appendToFile(file, table.concat(logs, "\n") .. "\n")
        if not ok then
            local i = #cache_logs + 1
            for _, log in ipairs(logs) do
                cache_logs[i] = log
                i = i + 1
            end

            return false, err
        end
    end

    return true
end

local formatter_params = table_new(0, 5)
function Logger:_log(params)
    if not (params or params.level) then return true end

    local level = params.level
    if type(level) ~= "string" then return false, "params level should be string" end

    local opts = self.opts
    local scope = opts.scope
    local levels = opts.levels
    local output_level = opts.output_level
    if not levels[level] then return false, "unknow level: " .. level end
    if levels[level] > output_level then return true end

    local message = params.message
    local meta = params.meta
    if not meta and type(message) == "table" then
        meta = message
        message = nil
    end
    meta = meta or {}

    local error = params.error
    if level == "error" and not error then
        error = message
        message = nil
    end

    formatter_params.scope = scope
    formatter_params.level = level
    formatter_params.message = message
    formatter_params.error = error
    formatter_params.data = meta
    local content, err = opts.formatter(formatter_params)
    table_clear(formatter_params)

    if not content then return false, "params formatter failed, error: " .. err end

    params.level = level
    params.scope = scope
    params.content = content
    Logger._logs[#Logger._logs + 1] = params

    return true
end

function Logger:log(params)
    local ok, err = self:_log(params)

    if ok then
        return true
    else 
        ngx.log(ngx.ERR, "failed to log, error: " .. err)
        return false, err
    end
end

function flush_to_disk()
    local ok, err = Logger:flush()

    if not ok then
        ngx.log(ngx.ERR, "failed to flush logs to disk, error: " .. err)
    end

    ngx.timer.at(Logger._opts.flush_interval, flush_to_disk)
end

ngx.timer.at(0, flush_to_disk)

return Logger
