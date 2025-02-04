module(..., package.seeall)

-- 消息队列
local msg_queue = {}

--- 将 table 转换成 URL 编码字符串
-- @param params (table) 需要转换的 table
-- @return (string) 转换后的 URL 编码字符串
local function urlencodeTab(params)
    local msg = {}
    for k, v in pairs(params) do
        if type(v) ~= "string" then
            v = tostring(v)
        end
        table.insert(msg, string.urlEncode(k) .. "=" .. string.urlEncode(v))
        table.insert(msg, "&")
    end
    table.remove(msg)
    return table.concat(msg)
end

local notify = {
    -- 发送到 custom_post
    ["custom_post"] = function(msg)
        if config.CUSTOM_POST_URL == nil or config.CUSTOM_POST_URL == "" then
            log.error("util_notify", "未配置 `config.CUSTOM_POST_URL`")
            return
        end
        if type(config.CUSTOM_POST_BODY_TABLE) ~= "table" then
            log.error("util_notify", "未配置 `config.CUSTOM_POST_BODY_TABLE`")
            return
        end

        local header = { ["content-type"] = config.CUSTOM_POST_CONTENT_TYPE }

        local body = json.decode(json.encode(config.CUSTOM_POST_BODY_TABLE))
        -- 遍历并替换其中的变量
        local function traverse_and_replace(t)
            for k, v in pairs(t) do
                if type(v) == "table" then
                    traverse_and_replace(v)
                elseif type(v) == "string" then
                    t[k] = string.gsub(v, "{msg}", msg)
                end
            end
        end
        traverse_and_replace(body)

        -- 根据 content-type 进行编码, 默认为 application/x-www-form-urlencoded
        if string.find(config.CUSTOM_POST_CONTENT_TYPE, "json") then
            body = json.encode(body)
        else
            body = urlencodeTab(body)
        end

        log.info("util_notify", "POST", config.CUSTOM_POST_URL, config.CUSTOM_POST_CONTENT_TYPE, body)
        return util_http.fetch(nil, "POST", config.CUSTOM_POST_URL, header, body)
    end,
    -- 发送到 telegram
    ["telegram"] = function(msg)
        if config.TELEGRAM_API == nil or config.TELEGRAM_API == "" then
            log.error("util_notify", "未配置 `config.TELEGRAM_API`")
            return
        end
        if config.TELEGRAM_CHAT_ID == nil or config.TELEGRAM_CHAT_ID == "" then
            log.error("util_notify", "未配置 `config.TELEGRAM_CHAT_ID`")
            return
        end

        local header = { ["content-type"] = "application/json" }
        local body = { ["chat_id"] = config.TELEGRAM_CHAT_ID, ["disable_web_page_preview"] = true, ["text"] = msg }
        local json_data = json.encode(body)

        log.info("util_notify", "POST", config.TELEGRAM_API)
        return util_http.fetch(nil, "POST", config.TELEGRAM_API, header, json_data)
    end,
    -- 发送到 gotify
    ["gotify"] = function(msg)
        if config.GOTIFY_API == nil or config.GOTIFY_API == "" then
            log.error("util_notify", "未配置 `config.GOTIFY_API`")
            return
        end
        if config.GOTIFY_TOKEN == nil or config.GOTIFY_TOKEN == "" then
            log.error("util_notify", "未配置 `config.GOTIFY_TOKEN`")
            return
        end

        local url = config.GOTIFY_API .. "/message?token=" .. config.GOTIFY_TOKEN
        local header = { ["Content-Type"] = "application/json; charset=utf-8" }
        local body = { title = config.GOTIFY_TITLE, message = msg, priority = config.GOTIFY_PRIORITY }
        local json_data = json.encode(body)

        log.info("util_notify", "POST", config.GOTIFY_API)
        return util_http.fetch(nil, "POST", url, header, json_data)
    end,
    -- 发送到 pushdeer
    ["pushdeer"] = function(msg)
        if config.PUSHDEER_API == nil or config.PUSHDEER_API == "" then
            log.error("util_notify", "未配置 `config.PUSHDEER_API`")
            return
        end
        if config.PUSHDEER_KEY == nil or config.PUSHDEER_KEY == "" then
            log.error("util_notify", "未配置 `config.PUSHDEER_KEY`")
            return
        end

        local header = { ["Content-Type"] = "application/x-www-form-urlencoded" }
        local body = { pushkey = config.PUSHDEER_KEY or "", type = "text", text = msg }

        log.info("util_notify", "POST", config.PUSHDEER_API)
        return util_http.fetch(nil, "POST", config.PUSHDEER_API, header, urlencodeTab(body))
    end,
    -- 发送到 bark
    ["bark"] = function(msg)
        if config.BARK_API == nil or config.BARK_API == "" then
            log.error("util_notify", "未配置 `config.BARK_API`")
            return
        end
        if config.BARK_KEY == nil or config.BARK_KEY == "" then
            log.error("util_notify", "未配置 `config.BARK_KEY`")
            return
        end

        local header = { ["Content-Type"] = "application/x-www-form-urlencoded" }
        local body = { body = msg }
        local url = config.BARK_API .. "/" .. config.BARK_KEY

        log.info("util_notify", "POST", url)
        return util_http.fetch(nil, "POST", url, header, urlencodeTab(body))
    end,
    -- 发送到 dingtalk
    ["dingtalk"] = function(msg)
        if config.DINGTALK_WEBHOOK == nil or config.DINGTALK_WEBHOOK == "" then
            log.error("util_notify", "未配置 `config.DINGTALK_WEBHOOK`")
            return
        end

        local url = config.DINGTALK_WEBHOOK
        -- 如果配置了 config.DINGTALK_SECRET 则需要签名(加签), 没配置则为自定义关键词
        if (config.DINGTALK_SECRET and config.DINGTALK_SECRET ~= "") then
            -- 时间异常则等待同步
            if os.time() < 1714500000 then
                ntp.timeSync()
                sys.waitUntil("NTP_SUCCEED", 1000 * 10)
            end
            local timestamp = tostring(os.time()) .. "000"
            local origin_str = timestamp .. "\n" .. config.DINGTALK_SECRET
            local sign = crypto.hmac_sha256(origin_str, config.DINGTALK_SECRET):fromHex()
            sign = crypto.base64_encode(sign, #sign):urlEncode()
            url = url .. "&timestamp=" .. timestamp .. "&sign=" .. sign
        end

        local header = { ["Content-Type"] = "application/json; charset=utf-8" }
        local body = { msgtype = "text", text = { content = msg } }

        log.info("util_notify", "POST", url)
        local res_code, res_headers, res_body = util_http.fetch(nil, "POST", url, header, json.encode(body))

        -- 处理响应
        -- https://open.dingtalk.com/document/orgapp/custom-robots-send-group-messages
        if res_code == 200 and res_body and res_body ~= "" then
            local res_data = json.decode(res_body)
            local res_errcode = res_data.errcode or 0
            local res_errmsg = res_data.errmsg or ""
            -- 系统繁忙 / 发送速度太快而限流
            if res_errcode == -1 or res_errcode == 410100 then
                return 500, res_headers, res_body
            end
            -- timestamp 无效
            if res_errcode == 310000 and (string.find(res_errmsg, "timestamp") or string.find(res_errmsg, "过期")) then
                ntp.timeSync()
                return 500, res_headers, res_body
            end
        end
        return res_code, res_headers, res_body
    end,
    -- 发送到 feishu
    ["feishu"] = function(msg)
        if config.FEISHU_WEBHOOK == nil or config.FEISHU_WEBHOOK == "" then
            log.error("util_notify", "未配置 `config.FEISHU_WEBHOOK`")
            return
        end

        local header = { ["Content-Type"] = "application/json; charset=utf-8" }
        local body = { msg_type = "text", content = { text = msg } }
        local json_data = json.encode(body)

        log.info("util_notify", "POST", config.FEISHU_WEBHOOK)
        return util_http.fetch(nil, "POST", config.FEISHU_WEBHOOK, header, json_data)
    end,
    -- 发送到 wecom
    ["wecom"] = function(msg)
        if config.WECOM_WEBHOOK == nil or config.WECOM_WEBHOOK == "" then
            log.error("util_notify", "未配置 `config.WECOM_WEBHOOK`")
            return
        end

        local header = { ["Content-Type"] = "application/json; charset=utf-8" }
        local body = { msgtype = "text", text = { content = msg } }
        local json_data = json.encode(body)

        log.info("util_notify", "POST", config.WECOM_WEBHOOK)
        return util_http.fetch(nil, "POST", config.WECOM_WEBHOOK, header, json_data)
    end,
    -- 发送到 pushover
    ["pushover"] = function(msg)
        if config.PUSHOVER_API_TOKEN == nil or config.PUSHOVER_API_TOKEN == "" then
            log.error("util_notify", "未配置 `config.PUSHOVER_API_TOKEN`")
            return
        end
        if config.PUSHOVER_USER_KEY == nil or config.PUSHOVER_USER_KEY == "" then
            log.error("util_notify", "未配置 `config.PUSHOVER_USER_KEY`")
            return
        end

        local header = { ["Content-Type"] = "application/json; charset=utf-8" }
        local body = { token = config.PUSHOVER_API_TOKEN, user = config.PUSHOVER_USER_KEY, message = msg }

        local json_data = json.encode(body)

        local url = "https://api.pushover.net/1/messages.json"

        log.info("util_notify", "POST", url)
        return util_http.fetch(nil, "POST", url, header, json_data)
    end,
    -- 发送到 inotify
    ["inotify"] = function(msg)
        if config.INOTIFY_API == nil or config.INOTIFY_API == "" then
            log.error("util_notify", "未配置 `config.INOTIFY_API`")
            return
        end
        -- LuatOS-Air 不支持 endsWith, 所以注释掉
        -- if not config.INOTIFY_API:endsWith(".send") then
        --     log.error("util_notify", "`config.INOTIFY_API` 必须以 `.send` 结尾")
        --     return
        -- end

        local url = config.INOTIFY_API .. "/" .. string.urlEncode(msg)

        log.info("util_notify", "GET", url)
        return util_http.fetch(nil, "GET", url)
    end,
    -- 发送到 next-smtp-proxy
    ["next-smtp-proxy"] = function(msg)
        if config.NEXT_SMTP_PROXY_API == nil or config.NEXT_SMTP_PROXY_API == "" then
            log.error("util_notify", "未配置 `config.NEXT_SMTP_PROXY_API`")
            return
        end
        if config.NEXT_SMTP_PROXY_USER == nil or config.NEXT_SMTP_PROXY_USER == "" then
            log.error("util_notify", "未配置 `config.NEXT_SMTP_PROXY_USER`")
            return
        end
        if config.NEXT_SMTP_PROXY_PASSWORD == nil or config.NEXT_SMTP_PROXY_PASSWORD == "" then
            log.error("util_notify", "未配置 `config.NEXT_SMTP_PROXY_PASSWORD`")
            return
        end
        if config.NEXT_SMTP_PROXY_HOST == nil or config.NEXT_SMTP_PROXY_HOST == "" then
            log.error("util_notify", "未配置 `config.NEXT_SMTP_PROXY_HOST`")
            return
        end
        if config.NEXT_SMTP_PROXY_PORT == nil or config.NEXT_SMTP_PROXY_PORT == "" then
            log.error("util_notify", "未配置 `config.NEXT_SMTP_PROXY_PORT`")
            return
        end
        if config.NEXT_SMTP_PROXY_TO_EMAIL == nil or config.NEXT_SMTP_PROXY_TO_EMAIL == "" then
            log.error("util_notify", "未配置 `config.NEXT_SMTP_PROXY_TO_EMAIL`")
            return
        end

        local header = { ["Content-Type"] = "application/x-www-form-urlencoded" }
        local body = {
            user = config.NEXT_SMTP_PROXY_USER,
            password = config.NEXT_SMTP_PROXY_PASSWORD,
            host = config.NEXT_SMTP_PROXY_HOST,
            port = config.NEXT_SMTP_PROXY_PORT,
            form_name = config.NEXT_SMTP_PROXY_FORM_NAME,
            to_email = config.NEXT_SMTP_PROXY_TO_EMAIL,
            subject = config.NEXT_SMTP_PROXY_SUBJECT,
            text = msg,
        }

        log.info("util_notify", "POST", config.NEXT_SMTP_PROXY_API)
        return util_http.fetch(nil, "POST", config.NEXT_SMTP_PROXY_API, header, urlencodeTab(body))
    end,
    -- 发送到 serverchan
    ["serverchan"] = function(msg)
        if config.SERVERCHAN_API == nil or config.SERVERCHAN_API == "" then
            log.error("util_notify", "未配置 `config.SERVERCHAN_API`")
            return
        end

        if config.SERVERCHAN_TITLE == nil or config.SERVERCHAN_TITLE == "" then
            log.error("util_notify", "未配置 `config.SERVERCHAN_TITLE`")
            return
        end

        local header = { ["Content-Type"] = "application/x-www-form-urlencoded" }
        local body = { title = config.SERVERCHAN_TITLE, desp = msg }

        log.info("util_notify", "POST", config.SERVERCHAN_API)
        return util_http.fetch(nil, "POST", config.SERVERCHAN_API, header, urlencodeTab(body))
    end,
}

--- 构建设备信息字符串, 用于追加到通知消息中
-- @return (string) 设备信息
function BuildDeviceInfo()
    local msg = "\n"

    -- 本机号码
    local number = util_mobile.getNumber()
    if #number >= 18 then
        msg = msg .. "\nICCID: " .. number
    else
        msg = msg .. "\n本机号码: " .. number
    end

    -- IMEI
    -- local imei = misc.getImei()
    -- if imei ~= "" then
    --     msg = msg .. "\nIMEI: " .. imei
    -- end

    -- 开机时长
    -- rtos.tick() 系统启动后的计数个数 单位为5ms 0-5d638865→-5d638865-0
    local ms = rtos.tick() * 5
    local seconds = math.floor(ms / 1000)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)
    seconds = seconds % 60
    minutes = minutes % 60
    local boot_time = string.format("%02d:%02d:%02d", hours, minutes, seconds)
    if ms >= 0 then
        msg = msg .. "\n开机时长: " .. boot_time
    end

    -- 运营商
    local oper = util_mobile.getOper(true)
    if oper ~= "" then
        msg = msg .. "\n运营商: " .. oper
    end

    -- 信号
    local rsrp = net.getRsrp() - 140
    if rsrp ~= 0 then
        msg = msg .. "\n信号: " .. rsrp .. "dBm"
    end

    -- 频段
    local band = net.getBand()
    if band ~= "" then
        msg = msg .. "\n频段: B" .. band
    end

    -- 温度
    local temperature = util_temperature.get()
    if temperature ~= "-99" then
        msg = msg .. "\n温度: " .. temperature .. "℃"
    end

    -- 型号
    -- local model_type = misc.getModelType()
    -- if model_type ~= "" then
    --     msg = msg .. "\n型号: " .. model_type
    -- end

    -- 系统版本
    -- local os_version = misc.getVersion()
    -- if os_version ~= "" then
    --     msg = msg .. "\n版本: " .. os_version
    -- end

    -- 电压
    local vbat = misc.getVbatt()
    vbat = string.format("%.3f", vbat / 1000)
    msg = msg .. "\n电压: " .. vbat .. "V"

    return msg
end

--- 发送通知
-- @param msg (string) 通知内容
-- @param channel (string) 通知渠道
-- @return (boolean) 是否发送成功/不需要重发
function send(msg, channel)
    log.info("util_notify.send", "发送通知", channel)

    -- 判断消息内容 msg
    if type(msg) ~= "string" then
        log.error("util_notify.send", "发送通知失败", "参数类型错误", type(msg))
        return true
    end
    if msg == "" then
        log.error("util_notify.send", "发送通知失败", "消息为空")
        return true
    end

    -- 判断通知渠道 channel
    if channel and notify[channel] == nil then
        log.error("util_notify.send", "发送通知失败", "未知通知渠道", channel)
        return true
    end

    -- 通知内容追加设备信息
    if config.NOTIFY_APPEND_MORE_INFO then
        msg = msg .. BuildDeviceInfo()
    end

    -- 发送通知
    local code, headers, body = notify[channel](msg)
    if code == nil or code == -99 then
        log.info("util_notify.send", "发送通知失败, 无需重发", "code:", code, "body:", body)
        return true
    end
    if code >= 200 and code < 500 and code ~= 408 and code ~= 409 and code ~= 425 and code ~= 429 then
        log.info("util_notify.send", "发送通知成功", "code:", code, "body:", body)
        return true
    end
    log.error("util_notify.send", "发送通知失败, 等待重发", "code:", code, "body:", body)
    return false
end

--- 添加到消息队列
-- @param msg 消息内容
-- @param channels 通知渠道
function add(msg, channels)
    if type(msg) == "table" then
        msg = table.concat(msg, "\n")
    end

    channels = channels or config.NOTIFY_TYPE

    if type(channels) ~= "table" then
        channels = { channels }
    end

    for _, channel in ipairs(channels) do
        table.insert(msg_queue, { channel = channel, msg = msg, retry = 0 })
    end
    sys.publish("NEW_MSG")
    log.info("util_notify.add", "添加到消息队列, 当前队列长度:", #msg_queue)
end

--- 轮询消息队列
--- 发送成功则从消息队列中删除
--- 发送失败则等待下次轮询
local function poll()
    local item, result
    while true do
        -- 消息队列非空, 且网络已注册
        if next(msg_queue) ~= nil and net.getState() == "REGISTERED" then
            log.info("util_notify.poll", "轮询消息队列中, 当前队列长度:", #msg_queue)

            item = msg_queue[1]
            table.remove(msg_queue, 1)

            if item.retry > (config.NOTIFY_RETRY_MAX or 100) then
                log.error("util_notify.poll", "超过最大重发次数", "msg:", item.msg)
            else
                result = send(item.msg, item.channel)
                item.retry = item.retry + 1

                if result then
                    -- 发送成功提示音
                    util_audio.play(3, "FILE", "/lua/audio_http_success.mp3")
                else
                    -- 发送失败, 移到队尾
                    table.insert(msg_queue, item)
                    sys.wait(5000)
                end
            end
            sys.wait(50)
        else
            sys.waitUntil("NEW_MSG", 1000 * 10)
        end
    end
end

sys.taskInit(poll)
