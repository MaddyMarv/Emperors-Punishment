local mod = get_mod("EmperorsPunishment")
local native = mod.native

local openshock = {}

local DEFAULT_SERVER = "https://api.openshock.app"
local RETRY_DELAY = 10
local MESSAGE_REPEAT_DELAY = 30
local HTTP_IDLE = 0
local HTTP_DONE = 2
local MIN_DURATION_MS = 300
local MAX_DURATION_MS = 65535
local OP_TYPES = { ["0"] = "Shock", ["1"] = "Vibrate", ["2"] = "Sound" }
local OP_PERMISSIONS = { Shock = "shock", Vibrate = "vibrate", Sound = "sound" }

local state = mod:persistent_table("openshock")

local last_message = nil
local last_message_t = 0
local last_logged = nil

local function echo_limited(message)
    local t = mod:clock()
    if message ~= last_message or t >= last_message_t + MESSAGE_REPEAT_DELAY or t < last_message_t then
        last_message = message
        last_message_t = t
        mod:echo(message)
    end
end

local function log_once(message)
    if message ~= last_logged then
        last_logged = message
        mod:info("%s", message)
    end
end

local function fail(message, check)
    state.step = nil
    state.retry_at = mod:clock() + RETRY_DELAY
    mod:echo(message)
    if check then
        mod:echo(check)
    end
end

local function describe(status, body)
    if status < 0 then
        return mod:localize("msg_network_error", tostring(-status))
    end
    local ok, data = pcall(cjson.decode, body)
    if ok and type(data) == "table" and type(data.title) == "string" and data.title ~= "" then
        return "HTTP " .. tostring(status) .. ": " .. data.title
    end
    return "HTTP " .. tostring(status)
end

local function headers()
    return "OpenShockToken: " .. state.token .. "\r\nContent-Type: application/json\r\n"
end

local function add_shockers(shockers, devices)
    for i = 1, #devices do
        local device_shockers = type(devices[i].shockers) == "table" and devices[i].shockers or {}
        for j = 1, #device_shockers do
            local shocker = device_shockers[j]
            if shocker.isPaused ~= true then
                local limits = type(shocker.limits) == "table" and shocker.limits or nil
                shockers[#shockers + 1] = {
                    id = shocker.id,
                    name = type(shocker.name) == "string" and string.lower(string.match(shocker.name, "^%s*(.-)%s*$")) or "",
                    permissions = type(shocker.permissions) == "table" and shocker.permissions or nil,
                    max_intensity = limits and type(limits.intensity) == "number" and limits.intensity or nil,
                    max_duration = limits and type(limits.duration) == "number" and limits.duration or nil,
                }
            end
        end
    end
end

local function on_devices(dll, status, body)
    if status ~= 200 then
        log_once(body)
    end
    if status == 401 then
        return fail(mod:localize("msg_openshock_token_rejected"), mod:localize("msg_check_openshock_token"))
    end
    if status < 0 then
        return fail(mod:localize("msg_openshock_unreachable", state.server, describe(status, body)))
    end
    if status ~= 200 then
        return fail(mod:localize("msg_openshock_shockers_failed", describe(status, body)))
    end
    local ok, reply = pcall(cjson.decode, body)
    if not ok or type(reply) ~= "table" or type(reply.data) ~= "table" then
        return fail(mod:localize("msg_openshock_wrong_server", state.server), mod:localize("msg_check_openshock_server"))
    end

    local shockers = {}
    add_shockers(shockers, reply.data)
    state.found = shockers
    state.step = "shared"
    dll.EP_HttpGet(state.server .. "/1/shockers/shared", headers())
end

local function announce()
    if not state.announce then
        return
    end
    state.announce = false
    local names = {}
    local shockers = state.shockers
    for i = 1, #shockers do
        names[i] = shockers[i].name
    end
    mod:echo(#names > 0 and mod:localize("msg_found_shockers", tostring(#names), "OpenShock", table.concat(names, ", ")) or mod:localize("msg_found_none", "OpenShock"))
end

local function on_shared(status, body)
    local shockers = state.found
    state.found = nil
    state.step = nil
    state.shockers = shockers

    local ok, reply = pcall(cjson.decode, body)
    if status ~= 200 or not ok or type(reply) ~= "table" or type(reply.data) ~= "table" then
        log_once(body)
        mod:echo(mod:localize("msg_openshock_shared_failed", describe(status, body)))
        announce()
        return
    end

    local owners = reply.data
    for i = 1, #owners do
        if type(owners[i].devices) == "table" then
            add_shockers(shockers, owners[i].devices)
        end
    end
    announce()
end

local function on_control(status, body)
    if status == 200 then
        return
    end
    log_once(body)
    if status == 401 then
        state.shockers = nil
        return fail(mod:localize("msg_openshock_token_rejected"), mod:localize("msg_check_openshock_token"))
    end
    if status == 404 or status == 412 then
        state.shockers = nil
        state.step = "restart"
    end
    echo_limited(mod:localize("msg_openshock_command_refused", describe(status, body)))
end

function openshock.reset()
    state.token = nil
    state.server = nil
    state.found = nil
    state.shockers = nil
    state.step = nil
    state.retry_at = nil
    state.posting = false
end

function openshock.refresh()
    if not state.token then
        return false
    end
    state.shockers = nil
    state.found = nil
    state.retry_at = nil
    state.posting = false
    state.announce = true
    state.step = "restart"
    return true
end

function openshock.configure(token, server)
    if server == "" then
        server = DEFAULT_SERVER
    end

    if token == "" then
        openshock.reset()
        return false
    end

    if not native.load() then
        return false
    end

    if state.token ~= token or state.server ~= server then
        openshock.reset()
        state.token = token
        state.server = server
        last_message = nil
        state.step = "restart"
    elseif not state.shockers and not state.step then
        if state.retry_at and mod:clock() < state.retry_at then
            return false
        end
        state.step = "restart"
    end

    return true
end

function openshock.send(token, server, op, intensity, duration, shocker_names, is_test)
    if not openshock.configure(token, server) then
        return false
    end

    if not state.shockers then
        if state.step and not is_test then
            echo_limited(mod:localize("msg_still_connecting", "OpenShock"))
        end
        return false, state.step and "connecting"
    end

    if state.posting then
        return false
    end

    local allowed = nil
    for name in string.gmatch(shocker_names, "[^,]+") do
        name = string.lower(string.match(name, "^%s*(.-)%s*$"))
        if name ~= "" then
            allowed = allowed or {}
            allowed[name] = true
        end
    end

    local op_type = OP_TYPES[op] or "Vibrate"
    local permission = OP_PERMISSIONS[op_type]
    local send_intensity = math.clamp(math.floor(intensity + 0.5), 0, 100)
    local send_duration = math.clamp(math.floor(duration * 1000 + 0.5), MIN_DURATION_MS, MAX_DURATION_MS)
    local shocks = {}
    local denied = 0
    local shockers = state.shockers
    for i = 1, #shockers do
        local shocker = shockers[i]
        if not allowed or allowed[shocker.name] or allowed[string.lower(tostring(shocker.id))] then
            if shocker.permissions and shocker.permissions[permission] ~= true then
                denied = denied + 1
            else
                shocks[#shocks + 1] = {
                    id = shocker.id,
                    type = op_type,
                    intensity = math.min(send_intensity, shocker.max_intensity or 100),
                    duration = math.max(MIN_DURATION_MS, math.min(send_duration, shocker.max_duration or MAX_DURATION_MS)),
                }
            end
        end
    end

    if #shocks == 0 then
        if #shockers == 0 then
            mod:echo(mod:localize("msg_openshock_no_shockers"))
        elseif denied > 0 then
            echo_limited(mod:localize("msg_openshock_not_allowed", string.lower(op_type)))
        else
            mod:echo(mod:localize("msg_no_target_match", shocker_names))
        end
        return false
    end

    local body = cjson.encode({ shocks = shocks, customName = "Darktide" })
    if native.load().EP_HttpPost(state.server .. "/2/shockers/control", headers(), body) == 0 then
        return false
    end
    state.posting = true
    return true
end

function openshock.update()
    local dll = state.token and native.load()
    if not dll then
        return
    end

    local step = state.step
    if not step and not state.posting then
        return
    end

    local http_state = dll.EP_HttpState()
    if step == "restart" then
        state.posting = false
        if http_state == HTTP_DONE then
            native.read_result(dll)
        elseif http_state == HTTP_IDLE then
            state.step = "devices"
            dll.EP_HttpGet(state.server .. "/1/shockers/own", headers())
        end
    elseif http_state == HTTP_DONE then
        local status, body = native.read_result(dll)
        if step == "devices" then
            on_devices(dll, status, body)
        elseif step == "shared" then
            on_shared(status, body)
        else
            state.posting = false
            on_control(status, body)
        end
    end
end

return openshock
