-- whitelist c2s events
---@type table<string, number>
local serverEventsWhitelist = {
    hostingSession = 1,
    hostedSession = 1
}

--- Registriert ein Event, das vom Client zum Server gesendet werden kann.
---@param eventName string Der Name des zu registrierenden Events.
RegisterServerEvent(eventName)

-- event handler for pre-session 'acquire'
---@type number|nil
local currentHosting
---@type table<number, function>
local hostReleaseCallbacks = {}

-- TODO: add a timeout for the hosting lock to be held
-- TODO: add checks for 'fraudulent' conflict cases of hosting attempts (typically whenever the host can not be reached)
AddEventHandler('hostingSession', function()
    -- if the lock is currently held, tell the client to await further instruction
    if currentHosting then
        TriggerClientEvent('sessionHostResult', source, 'wait')

        -- register a callback for when the lock is freed
        table.insert(hostReleaseCallbacks, function()
            TriggerClientEvent('sessionHostResult', source, 'free')
        end)

        return
    end

    -- if the current host was last contacted less than a second ago
    if GetHostId() then
        if GetPlayerLastMsg(GetHostId()) < 1000 then
            TriggerClientEvent('sessionHostResult', source, 'conflict')
            return
        end
    end

    hostReleaseCallbacks = {}

    currentHosting = source

    TriggerClientEvent('sessionHostResult', source, 'go')

    -- set a timeout of 5 seconds
    SetTimeout(5000, function()
        if not currentHosting then
            return
        end

        currentHosting = nil

        for _, cb in ipairs(hostReleaseCallbacks) do
            cb()
        end
    end)
end)

AddEventHandler('hostedSession', function()
    -- check if the client is the original locker
    if currentHosting ~= source then
        -- TODO: drop client as they're clearly lying
        print(currentHosting, '~=', source)
        return
    end

    -- free the host lock (call callbacks and remove the lock value)
    for _, cb in ipairs(hostReleaseCallbacks) do
        cb()
    end

    currentHosting = nil
end)

-- TODO: Add timeout for the host lock to be released automatically
SetTimeout(60000, function()
    if currentHosting then
        -- Release the host lock if it's still held after 1 minute
        for _, cb in ipairs(hostReleaseCallbacks) do
            cb()
        end

        currentHosting = nil
    end
end)

EnableEnhancedHostSupport(true)
