local mod = get_mod("EmperorsPunishment")
local ffi = Mods.lua.ffi

local native = {}

local DLL_PATH = "../mods/EmperorsPunishment/bin/ep_native.dll"
local RETRY_DELAY = 10
local WS_CONNECTED = 2
local KEY_HINT = mod:localize("msg_key_hint")
local ERROR_POLL_INTERVAL = 1
local ERROR_REPEAT_DELAY = 30
local HTTP_IDLE = 0
local HTTP_DONE = 2
local OP_MODES = { ["0"] = "s", ["1"] = "v", ["2"] = "b" }

local state = mod:persistent_table("native")

if not pcall(ffi.typeof, "EmperorsPunishment_CDEF") then
    ffi.cdef([[
        typedef struct { int unused; } EmperorsPunishment_CDEF;

        int  EP_Connect(const char* url);
        void EP_Disconnect(void);
        int  EP_Status(void);
        int  EP_Send(const char* text);
        int  EP_LastError(char* buffer, int buffer_size);
        int  EP_HttpGet(const char* url, const char* headers);
        int  EP_HttpState(void);
        int  EP_HttpResult(char* buffer, int buffer_size, int* status);
    ]])
end

if not pcall(ffi.typeof, "EmperorsPunishment_CDEF_POST") then
    ffi.cdef([[
        typedef struct { int unused; } EmperorsPunishment_CDEF_POST;

        int  EP_HttpPost(const char* url, const char* headers, const char* body);
    ]])
end

local buffer_size = 65536
local buffer = ffi.new("char[?]", buffer_size)
local status_out = ffi.new("int[1]")

local next_error_poll = 0
local last_error = nil
local last_error_t = 0
local last_logged = nil
local last_skip_t = 0

local function load_dll()
    if state.dll then
        return state.dll
    end
    local ok, dll = pcall(ffi.load, DLL_PATH)
    if not ok then
        if not state.load_error_shown then
            state.load_error_shown = true
            mod:echo(mod:localize("msg_dll_load_failed", tostring(dll)))
        end
        return nil
    end
    state.dll = dll
    return dll
end

local function url_encode(text)
    return (string.gsub(text, "[^%w%-_%.~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function fail(message)
    state.step = nil
    state.retry_at = mod:clock() + RETRY_DELAY
    mod:echo(message)
end

local function describe(status)
    if status < 0 then
        return mod:localize("msg_network_error", tostring(-status))
    end
    return "HTTP " .. tostring(status)
end

local function begin_discovery(dll)
    state.step = "account"
    dll.EP_HttpGet("https://api.pishock.com/Account", "X-PiShock-Api-Key: " .. state.apikey .. "\r\n")
end

local function read_result(dll)
    local length = dll.EP_HttpResult(buffer, buffer_size, status_out)
    if length < 0 then
        buffer_size = -length
        buffer = ffi.new("char[?]", buffer_size)
        length = dll.EP_HttpResult(buffer, buffer_size, status_out)
    end
    return status_out[0], ffi.string(buffer, length)
end

local function publish(dll, command)
    local allowed = nil
    for name in string.gmatch(command.shocker_names, "[^,]+") do
        name = string.lower(string.match(name, "^%s*(.-)%s*$"))
        if name ~= "" then
            allowed = allowed or {}
            allowed[name] = true
        end
    end

    local commands = {}
    local clients = state.clients
    for i = 1, #clients do
        local client = clients[i]
        local shockers = client.shockers
        for j = 1, #shockers do
            local shocker = shockers[j]
            if not allowed or allowed[shocker.name] or allowed[tostring(shocker.id)] then
                commands[#commands + 1] = {
                    Target = client.target,
                    Body = {
                        id = shocker.id,
                        m = OP_MODES[command.op] or "v",
                        i = math.clamp(math.floor(command.intensity + 0.5), 1, 100),
                        d = math.clamp(math.floor(command.duration + 0.5), 1, 15) * 1000,
                        r = true,
                        l = {
                            u = state.user_id,
                            ty = "api",
                            w = false,
                            h = false,
                            o = "Darktide",
                        },
                    },
                }
            end
        end
    end

    if #commands == 0 then
        if #clients == 0 then
            mod:echo(mod:localize("msg_pishock_no_shockers"))
        else
            mod:echo(mod:localize("msg_no_target_match", command.shocker_names))
        end
        return false
    end

    return dll.EP_Send(cjson.encode({ Operation = "PUBLISH", PublishCommands = commands })) ~= 0
end

local function on_account(dll, status, body)
    if status == 401 then
        state.key_rejected = true
        fail(mod:localize("msg_pishock_key_rejected"))
        mod:echo(mod:localize("msg_check_pishock_apikey"))
        mod:echo(KEY_HINT)
        return
    end
    local ok, data = pcall(cjson.decode, body)
    local user_id = ok and type(data) == "table" and (data.UserId or data.UserID or data.userId or data.id)
    if status ~= 200 then
        return fail(mod:localize("msg_pishock_account_failed", describe(status)))
    end
    if not user_id then
        return fail(mod:localize("msg_pishock_no_user_id"))
    end

    state.user_id = user_id
    state.step = "devices"
    dll.EP_HttpGet("https://ps.pishock.com/PiShock/GetUserDevices?UserId=" .. url_encode(tostring(user_id))
        .. "&Token=" .. url_encode(state.apikey) .. "&api=true", "")
end

local function on_devices(dll, status, body)
    local ok, devices = pcall(cjson.decode, body)
    if status ~= 200 then
        return fail(mod:localize("msg_pishock_devices_failed", describe(status)))
    end
    if not ok or type(devices) ~= "table" then
        return fail(mod:localize("msg_pishock_devices_unreadable"))
    end

    local clients = {}
    for i = 1, #devices do
        local device = devices[i]
        local shockers = {}
        local device_shockers = type(device.shockers) == "table" and device.shockers or {}
        for j = 1, #device_shockers do
            local shocker = device_shockers[j]
            if shocker.isPaused ~= true then
                shockers[#shockers + 1] = {
                    id = shocker.shockerId,
                    name = type(shocker.name) == "string" and string.lower(string.match(shocker.name, "^%s*(.-)%s*$")) or "",
                }
            end
        end
        if #shockers > 0 then
            clients[#clients + 1] = { target = "c" .. tostring(device.clientId) .. "-ops", shockers = shockers }
        end
    end

    state.clients = clients
    state.step = nil

    if state.announce then
        state.announce = false
        local names = {}
        for i = 1, #clients do
            local shockers = clients[i].shockers
            for j = 1, #shockers do
                names[#names + 1] = shockers[j].name
            end
        end
        mod:echo(#names > 0 and mod:localize("msg_found_shockers", tostring(#names), "PiShock", table.concat(names, ", ")) or mod:localize("msg_found_none", "PiShock"))
    end
end

function native.refresh()
    if not state.key then
        return false
    end
    state.clients = nil
    state.retry_at = nil
    state.announce = true
    state.step = "restart"
    return true
end

native.load = load_dll
native.read_result = read_result

function native.configure(username, apikey)
    if username == "" or apikey == "" then
        state.key = nil
        state.clients = nil
        native.disconnect()
        return false
    end

    local dll = load_dll()
    if not dll then
        return false
    end

    local key = username .. "\n" .. apikey
    if state.key ~= key then
        state.key = key
        state.apikey = apikey
        state.ws_url = "wss://broker.pishock.com/v2?Username=" .. url_encode(username) .. "&ApiKey=" .. url_encode(apikey)
        state.clients = nil
        state.user_id = nil
        state.retry_at = nil
        state.key_rejected = false
        last_error = nil
        state.step = "restart"
    elseif not state.clients and not state.step then
        if state.retry_at and mod:clock() < state.retry_at then
            return false
        end
        state.step = "restart"
    end

    dll.EP_Connect(state.ws_url)
    return true
end

function native.disconnect()
    if state.dll then
        state.dll.EP_Disconnect()
    end
end

function native.send(username, apikey, op, intensity, duration, shocker_names, is_test)
    if not native.configure(username, apikey) then
        return false
    end

    if not state.clients or state.dll.EP_Status() ~= WS_CONNECTED then
        local t = mod:clock()
        if state.step and not is_test and (t >= last_skip_t + ERROR_REPEAT_DELAY or t < last_skip_t) then
            last_skip_t = t
            mod:echo(mod:localize("msg_still_connecting", "PiShock"))
        end
        return false, state.step and "connecting"
    end

    return publish(state.dll, {
        op = op,
        intensity = intensity,
        duration = duration,
        shocker_names = shocker_names,
    })
end

function native.update()
    local dll = state.dll
    if not dll then
        return
    end

    local step = state.step
    if step then
        local http_state = dll.EP_HttpState()
        if step == "restart" then
            if http_state == HTTP_DONE then
                read_result(dll)
            elseif http_state == HTTP_IDLE then
                begin_discovery(dll)
            end
        elseif http_state == HTTP_DONE then
            local status, body = read_result(dll)
            if step == "account" then
                on_account(dll, status, body)
            else
                on_devices(dll, status, body)
            end
        end
    end

    local t = mod:clock()
    if t >= next_error_poll or t < next_error_poll - ERROR_POLL_INTERVAL then
        next_error_poll = t + ERROR_POLL_INTERVAL
        local length = dll.EP_LastError(buffer, buffer_size)
        if length > 0 then
            local message = ffi.string(buffer, length)
            if message ~= last_logged then
                last_logged = message
                mod:info("%s", message)
            end

            local ok, data = pcall(cjson.decode, message)
            local hidden = false
            local show_hint = false
            if ok and type(data) == "table" and type(data.Message) == "string" then
                if data.ErrorCode == "AUTH_ERROR" then
                    hidden = state.key_rejected
                    message = mod:localize("msg_pishock_login_rejected")
                    show_hint = true
                else
                    message = data.Message
                end
            end
            if not hidden and (message ~= last_error or t >= last_error_t + ERROR_REPEAT_DELAY or t < last_error_t) then
                last_error = message
                last_error_t = t
                mod:echo(message)
                if show_hint then
                    mod:echo(mod:localize("msg_check_pishock_login"))
                    mod:echo(KEY_HINT)
                end
            end
        end
    end
end

return native
