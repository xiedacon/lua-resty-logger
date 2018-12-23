-- Copyright (c) 2018, xiedacon.

local cjson = require "cjson.safe"

local Array = require "utility.array"
local Object = require "utility.object"
local fs = require "fs"

local LOGGER_OUTPUT_LEVEL = os.getenv("LOGGER_OUTPUT_LEVEL") or "info"
local LEVELS = {
    error = 0,
    warn = 1,
    info = 2,
    debug = 3
}

local Logger = {
    _VERSION = '0.1',
    _logs = Array(),
    _opts = {
        flush_interval = 10,
        log_file = function(scope, level)
            return ngx.config.prefix() .. "logs/" .. level .. ".log"
        end,

        levels = LEVELS,
        output_level = LEVELS[LOGGER_OUTPUT_LEVEL],
        formatter = function(log)
            local log_str, err = cjson.encode(log)
            if err then return false, err end
    
            return Array.join({
                ngx.localtime(),
                "[" .. log.level .. "]",
                log_str
            }, " ")
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
    local logs = Logger._logs
    Logger._logs = Array()

    local log_file = Logger._opts.log_file
    local logMap = {}
    for _, log in ipairs(logs) do
        local file = log_file(log.scope, log.level)

        logMap[file] = logMap[file] or Array()
        logMap[file]:push(log)
    end

    for file, logs in pairs(logMap) do
        local log_str = logs:map("content"):join("\n") .. "\n"

        local ok, err = fs.appendToFile(file, log_str)
        if not ok then
            Logger._logs = logs:concat(Logger._logs)

            return false, err
        end
    end

    return true
end

function Logger:_log(params)
    if not (params or params.level) then return true end

    local level = params.level
    if type(level) ~= "string" then return false, "params level should be string" end

    local scope = self.opts.scope
    local levels = self.opts.levels
    local output_level = self.opts.output_level
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

    local content, err = self.opts.formatter({
        scope = scope,
        level = level,
        message = message,
        error = error,
        data = meta
    })
    if not content then return false, "params formatter failed, error: " .. err end

    Logger._logs:push({
        level = level,
        scope = scope,
        content = content
    })

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
