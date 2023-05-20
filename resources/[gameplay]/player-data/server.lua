--- identifiers, die wir ignorieren (z.B. IP), da sie ein geringes Vertrauen und hohe Varianz haben
local identifierBlocklist = {
    ip = true
}

--- Überprüft, ob der Identifier blockiert ist.
---@param identifier string Der zu überprüfende Identifier.
---@return boolean Gibt true zurück, wenn der Identifier blockiert ist, andernfalls false.
local function isIdentifierBlocked(identifier)
    local idType, _ = string.find(identifier, ":")
    return identifierBlocklist[idType] or false
end

-- Spielerdaten in Lua-Tabellen speichern
local players = {}
local playersById = {}

--- Inkrementiert die ID-Sequenz und gibt die nächste verfügbare ID zurück.
---@return number Die nächste verfügbare ID.
local function incrementId()
    local nextId = GetResourceKvpInt('nextId') + 1
    SetResourceKvpInt('nextId', nextId)
    return nextId
end

--- Ruft die Spieler-ID anhand des Identifiers ab.
---@param identifier string Der Identifier, für den die Spieler-ID abgerufen werden soll.
---@return number|nil Die Spieler-ID oder nil, wenn keine Spieler-ID für den angegebenen Identifier gefunden wurde.
local function getPlayerIdFromIdentifier(identifier)
    local str = GetResourceKvpString(('identifier:%s'):format(identifier))
    if not str then
        return nil
    end
    return msgpack.unpack(str).id
end

--- Speichert die Spieler-ID für den angegebenen Identifier.
---@param identifier string Der zu speichernde Identifier.
---@param id number Die zugehörige Spieler-ID.
local function setPlayerIdFromIdentifier(identifier, id)
    local str = ('identifier:%s'):format(identifier)
    SetResourceKvp(str, msgpack.pack({ id = id }))
    SetResourceKvp(('player:%s:identifier:%s'):format(id, identifier), 'true')
end

--- Speichert neue Identifier für diese Spieler-ID.
---@param playerIdx number Der Spielerindex.
---@param newId number Die zugehörige Spieler-ID.
local function storeIdentifiers(playerIdx, newId)
    for _, identifier in pairs(GetPlayerIdentifiers(playerIdx)) do
        if not isIdentifierBlocked(identifier) then
            setPlayerIdFromIdentifier(identifier, newId)
        end
    end
end

--- Registriert einen neuen Spieler und gibt die zugewiesene Spieler-ID zurück.
---@param playerIdx number Der Spielerindex.
---@return number Die zugewiesene Spieler-ID.
local function registerPlayer(playerIdx)
    local newId = incrementId()
    storeIdentifiers(playerIdx, newId)
    return newId
end

--- Initialisiert die Spielerdaten für den angegebenen Spielerindex.
---@param playerIdx number Der Spielerindex.
local function setupPlayer(playerIdx)
    local defaultId = 0xFFFFFFFFFF
    local lowestId = defaultId

    for _, identifier in pairs(GetPlayerIdentifiers(playerIdx)) do
        if not isIdentifierBlocked(identifier) then
            local dbId = getPlayerIdFromIdentifier(identifier)
            if dbId and dbId < lowestId then
                lowestId = dbId
            end
        end
    end

    local playerId

    if lowestId == defaultId then
        playerId = registerPlayer(playerIdx)
    else
        storeIdentifiers(playerIdx, lowestId)
        playerId = lowestId
    end

    if Player then
        Player(playerIdx).state['cfx.re/playerData@id'] = playerId
    end

    players[playerIdx] = {
        dbId = playerId
    }
    playersById[tostring(playerId)] = playerIdx
end

AddEventHandler('playerConnecting', function()
    local playerIdx = tostring(source)
    setupPlayer(playerIdx)
end)

RegisterNetEvent('playerJoining')
AddEventHandler('playerJoining', function(oldIdx)
    local oldPlayer = players[tostring(oldIdx)]
    if oldPlayer then
        players[tostring(source)] = oldPlayer
        players[tostring(oldIdx)] = nil
    else
        setupPlayer(tostring(source))
    end
end)

AddEventHandler('playerDropped', function()
    local player = players[tostring(source)]
    if player then
        playersById[tostring(player.dbId)] = nil
    end
    players[tostring(source)] = nil
end)

for _, player in pairs(GetPlayers()) do
    setupPlayer(player)
end

RegisterCommand('playerData', function(source, args)
    if not args[1] then
        print('Verwendung:')
        print('\tplayerData getId <dbId>: gibt Identifier für ID zurück')
        print('\tplayerData getIdentifier <identifier>: gibt ID für Identifier zurück')
        return
    end

    if args[1] == 'getId' then
        local prefix = ('player:%s:identifier:'):format(args[2])
        local handle = StartFindKvp(prefix)
        local key

        repeat
            key = FindKvp(handle)

            if key then
                print('Ergebnis:', key:sub(#prefix + 1))
            end
        until not key

        EndFindKvp(handle)
    elseif args[1] == 'getIdentifier' then
        print('Ergebnis:', getPlayerIdFromIdentifier(args[2]))
    end
end, true)

local function getExportEventName(resource, name)
    return string.format('__cfx_export_%s_%s', resource, name)
end

function AddExport(name, fn)
    if not Citizen.Traits or not Citizen.Traits.ProvidesExports then
        AddEventHandler(getExportEventName('cfx.re/playerData.v1alpha1', name), function(setCB)
            setCB(fn)
        end)
    end

    exports(name, fn)
end

AddExport('getPlayerIdFromIdentifier', getPlayerIdFromIdentifier)

AddExport('getPlayerId', function(playerIdx)
    local player = players[tostring(playerIdx)]
    if not player then
        return nil
    end
    return player.dbId
end)

AddExport('getPlayerById', function(playerId)
    return playersById[tostring(playerId)]
end)
