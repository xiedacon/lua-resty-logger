# lua-utility

[![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/xiedacon/lua-resty-logger/blob/master/LICENSE)

## Requirements

* cjson
* lua-utility
* lua-fs-module

## Usage

```lua
local Logger = require "resty.logger"
local logger = Logger("test")

logger:info("This is a info")
-- cat ngx.config.prefix()/logs/info.log
logger:warn("This is a warn")
-- cat ngx.config.prefix()/logs/warn.log
logger:error("This is a error")
-- cat ngx.config.prefix()/logs/error.log
```

### 自定义日志输出文件

```lua
local Logger = require "resty.logger"
Logger:set_globle_opts({
  log_file = function(scope, level)
    -- scope: test
    -- level: debug|info|warn|error
    return ngx.config.prefix() .. "logs/example." .. level .. ".log"
  end
})

local logger = Logger("test")

logger:info("This is a info")
-- cat ngx.config.prefix()/logs/example.info.log
logger:warn("This is a warn")
-- cat ngx.config.prefix()/logs/example.warn.log
logger:error("This is a error")
-- cat ngx.config.prefix()/logs/example.error.log
```

### 自定义日志输出级别

默认日志级别如下：

```lua
local LEVELS = {
  error = 0,
  warn = 1,
  info = 2,
  debug = 3
}
```

每一个 Logger 实例的日志级别都是相互独立的

```lua
local Logger = require "resty.logger"

local logger = Logger("test1")
logger:set_opts({
  output_level = 4,
  levels = {
    error = 0,
    info = 2,
    debug = 3,
    trace = 4
  }
})

logger:trace("This is a trace")
-- cat ngx.config.prefix()/logs/trace.log
logger:warn("This is a warn")
-- Error

local logger = Logger("test2")

logger:trace("This is a trace")
-- Error
logger:warn("This is a warn")
-- cat ngx.config.prefix()/logs/warn.log
```

默认的输出级别为 ``info``，可通过 ``LOGGER_OUTPUT_LEVEL`` 环境变量或 ``Logger:set_globle_opts()`` 进行修改。同样的，输出级别也是每个 Logger 实例相互独立的

```lua
-- export LOGGER_OUTPUT_LEVEL="debug"
local Logger = require "resty.logger"

Logger:set_globle_opts({
  log_file = function(scope, level)
    return ngx.config.prefix() .. "logs/" .. scope .. "." .. level .. ".log"
  end
})

local logger1 = Logger("test1")
logger1:debug("This is a debug")
-- cat ngx.config.prefix()/logs/test1.debug.log

Logger:set_globle_opts({
  oputput_level = 2
})

local logger2 = Logger("test2")

logger1:debug("This is a debug")
-- cat ngx.config.prefix()/logs/test1.debug.log
logger2:debug("This is a debug")
-- cat ngx.config.prefix()/logs/test2.debug.log: No such file or directory
```

### 自定义日志格式

lua-resty-logger 的默认日志格式如下：

```
2018-10-12 00:00:00 [info] {"scope":"test","data":{},"level":"info","message":"test"}
2018-10-12 00:00:00 [error] {"scope":"test","data":{},"level":"error","error":"test"}
```

可通过 ``Logger:set_globle_opts()`` 自定义日志格式

```lua
local Logger = require "resty.logger"

-- {
--   scope = "test",
--   level = "info",
--   message = "This is a info",
--   error = nil,
--   data = {}
-- }
Logger:set_globle_opts({
  formatter = function(log)
    local log_str, err = cjson.encode(log)
    if err then return false, err end

    return table.concat({
      ngx.localtime(),
      "(" .. log.level .. ")",
      log_str
    }, " ")
  end
})

local logger = Logger("test")

logger:info("This is a info")
-- 2018-10-12 00:00:00 (info) {"scope":"test","data":{},"level":"info","message":"This is a info"}
```

## API

### Logger([opts])

* ``opts.levels`` ``<table>`` 日志级别
* ``opts.output_level`` ``<number>`` 输出级别
* ``opts.formatter`` ``<function>`` 日志处理器

### logger:set_opts(opts)

Same as ``Logger([opts])``

### logger:set_globle_opts(opts)

* ``opts.flush_interval`` ``<number>`` 刷新间隔
* ``opts.log_file`` ``<function>`` 输出文件
* ``opts.levels`` ``table`` 全局日志级别
* ``opts.output_level`` ``number`` 全局数据级别
* ``opts.formatter`` ``function`` 全局日志处理器

### logger:flush()

强制将日志输出到硬盘

### logger:log(params)

* ``params.level`` ``<string>`` 当前这条日志的级别
* ``params.message`` ``<string>`` 日志描述
* ``params.error`` ``<string>`` 错误描述
* ``params.meta`` ``<table>`` 附加信息

### others

创建 Logger 实例时，会将全局 opts 和当前实例的 opts 合并，并创建对应 level 的方法

logger:level([msg], meta)

* ``msg`` ``<string>`` 日志描述
* ``meta`` ``<table>`` 附加信息

默认会创建以下方法

* ``logger:debug(msg, meta)``
* ``logger:info(msg, meta)``
* ``logger:warn(msg, meta)``
* ``logger:error(msg, meta)``

## License

[MIT License](https://github.com/xiedacon/lua-resty-logger/blob/master/LICENSE)

Copyright (c) 2018 xiedacon