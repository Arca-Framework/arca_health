-- Health state (metadata + statebag), respawns, EMS actions, check-in and commands.

local cfg = HealthConfig
local deathAt = {}      -- [src] = os.time() they died
local lastAlert = {}    -- [src] = os.time() of their last EMS call
local checkingIn = {}   -- [src] = true while paid and being treated at the desk

local function notify(src, msg, kind)
    if src == 0 then return print(msg) end
    TriggerClientEvent('arca_core:notify', src, msg, kind or 'inform')
end

local function getPlayer(src) return exports.arca_core:GetPlayer(src) end

local function stateOf(src)
    return Player(src).state.healthState or 'alive'
end

local function isEMS(src)
    local player = getPlayer(src)
    local job = player and player.PlayerData.job
    if not job or not job.onduty then return false end
    local min = cfg.EMSJobs[job.name]
    return min ~= nil and job.grade.level >= min
end

local function emsOnDuty()
    local list = {}
    for _, src in ipairs(exports.arca_core:GetPlayers()) do
        if isEMS(src) then list[#list + 1] = src end
    end
    return list
end

local function near(a, b, dist)
    local pa, pb = GetPlayerPed(tostring(a)), GetPlayerPed(tostring(b))
    if pa == 0 or pb == 0 then return false end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= dist
end

---Uses one of `item` if set; true when there's nothing to use or it was used
local function useItem(src, item)
    if not item then return true end
    if GetResourceState('arca_inventory') ~= 'started' then return true end
    if exports.arca_inventory:RemoveItem(src, item, 1) then return true end
    notify(src, ('You need a %s'):format(item), 'error')
    return false
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local function applyState(src, state, cause)
    local player = getPlayer(src)
    Player(src).state:set('healthState', state, true)
    if state == 'dead' then deathAt[src] = deathAt[src] or os.time() else deathAt[src] = nil end
    if not player then return end
    player.SetMetaData('isdead', state == 'dead')
    player.SetMetaData('inlaststand', state == 'laststand')
    player.SetMetaData('deathcause', state ~= 'alive' and cause or nil)
    TriggerEvent('arca_health:server:stateChanged', src, state, cause)
end

RegisterNetEvent('arca_health:server:setState', function(state, cause)
    local src = source
    if state ~= 'alive' and state ~= 'laststand' and state ~= 'dead' then return end
    local current = stateOf(src)
    -- the client may only go further down by itself; getting up goes through revive/respawn
    if state == 'alive' and current ~= 'alive' and not Player(src).state.healthReviving then
        -- admin / other-resource revives fire arca_core:client:revived on the client; accept those
        -- only if arca_core already cleared the metadata (arca_admin does)
        local player = getPlayer(src)
        local meta = player and player.PlayerData.metadata or {}
        if meta.isdead or meta.inlaststand then return end
    end
    Player(src).state:set('healthReviving', nil, false)
    applyState(src, state, type(cause) == 'string' and cause:sub(1, 60) or nil)
end)

---Revive a player from the server (EMS, admin, scripts)
local function revive(target)
    Player(target).state:set('healthReviving', true, false)
    applyState(target, 'alive')
    TriggerClientEvent('arca_health:client:revive', target)
end

local function heal(target)
    TriggerClientEvent('arca_health:client:treat', target)
    local player = getPlayer(target)
    if player then player.SetMetaData('injuries', nil) end
end

---------------------------------------------------------------------
-- Injuries (saved so they survive a relog)
---------------------------------------------------------------------
local PARTS = { head = true, torso = true, larm = true, rarm = true, lleg = true, rleg = true }

RegisterNetEvent('arca_health:server:syncInjuries', function(data)
    local src = source
    local player = getPlayer(src)
    if not player or type(data) ~= 'table' then return end
    local parts = {}
    for part, sev in pairs(type(data.parts) == 'table' and data.parts or {}) do
        sev = math.floor(tonumber(sev) or 0)
        if PARTS[part] and sev > 0 then parts[part] = math.min(4, sev) end
    end
    local bleeding = math.max(0, math.min(4, math.floor(tonumber(data.bleeding) or 0)))
    player.SetMetaData('injuries', (next(parts) or bleeding > 0) and { parts = parts, bleeding = bleeding } or nil)
end)

Arca.Callback.Register('arca_health:getInjuries', function(src, target)
    target = tonumber(target)
    if not target or not isEMS(src) or not near(src, target, cfg.Revive.Distance + 2.0) then return nil end
    local player = getPlayer(target)
    local meta = player and player.PlayerData.metadata or {}
    local injuries = type(meta.injuries) == 'table' and meta.injuries or {}
    return { state = stateOf(target), cause = meta.deathcause, parts = injuries.parts or {}, bleeding = injuries.bleeding or 0 }
end)

---------------------------------------------------------------------
-- Respawn at a hospital
---------------------------------------------------------------------
RegisterNetEvent('arca_health:server:respawn', function()
    local src = source
    if stateOf(src) ~= 'dead' or not deathAt[src] then return end
    -- 2s of slack for timer drift between client and server
    if os.time() - deathAt[src] < cfg.DeathTime - 2 then return end

    local player = getPlayer(src)
    if player and cfg.Respawn.Fee > 0 then
        player.RemoveMoney('bank', cfg.Respawn.Fee, 'hospital bill')
        notify(src, ('Hospital bill: $%d'):format(cfg.Respawn.Fee), 'inform')
    end
    if cfg.Respawn.ClearInventory and GetResourceState('arca_inventory') == 'started' then
        exports.arca_inventory:ClearInventory(src)
    end

    -- nearest hospital
    local pos = GetEntityCoords(GetPlayerPed(tostring(src)))
    local best, bestDist
    for _, h in ipairs(cfg.Respawn.Hospitals) do
        local d = #(pos - vector3(h.coords.x, h.coords.y, h.coords.z))
        if not bestDist or d < bestDist then best, bestDist = h, d end
    end

    Player(src).state:set('healthReviving', true, false)
    applyState(src, 'alive')
    if player then player.SetMetaData('injuries', nil) end
    TriggerClientEvent('arca_health:client:respawn', src, best.coords)
end)

---------------------------------------------------------------------
-- EMS actions on other players
---------------------------------------------------------------------
RegisterNetEvent('arca_health:server:revive', function(target)
    local src = source
    target = tonumber(target)
    if not target or target == src then return end
    if not isEMS(src) then return end
    if not near(src, target, cfg.Revive.Distance + 2.0) then return notify(src, 'Too far away', 'error') end
    if stateOf(target) == 'alive' then return end
    if not useItem(src, cfg.Revive.Item) then return end
    revive(target)
    notify(src, 'Patient revived', 'success')
end)

RegisterNetEvent('arca_health:server:treat', function(target)
    local src = source
    target = tonumber(target)
    if not target or target == src or not isEMS(src) then return end
    if not near(src, target, cfg.Revive.Distance + 2.0) then return notify(src, 'Too far away', 'error') end
    if not useItem(src, cfg.Treat.Item) then return end
    heal(target)
    notify(src, 'Wounds treated', 'success')
end)

RegisterNetEvent('arca_health:server:callEMS', function()
    local src = source
    if stateOf(src) == 'alive' then return end
    local now = os.time()
    if lastAlert[src] and now - lastAlert[src] < cfg.CallEMSCooldown then return end
    lastAlert[src] = now

    local coords = GetEntityCoords(GetPlayerPed(tostring(src)))
    local player = getPlayer(src)
    local name = player and ('%s %s'):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname) or GetPlayerName(tostring(src))
    for _, ems in ipairs(emsOnDuty()) do
        TriggerClientEvent('arca_health:client:alert', ems, coords, name)
    end
    -- for dispatch / MDT scripts
    TriggerEvent('arca_health:server:emsCalled', src, coords)
end)

---------------------------------------------------------------------
-- Hospital check-in desk
---------------------------------------------------------------------
local function atDesk(src)
    local pos = GetEntityCoords(GetPlayerPed(tostring(src)))
    for _, loc in ipairs(cfg.CheckIn.Locations) do
        if #(pos - vector3(loc.x, loc.y, loc.z)) < 4.0 then return true end
    end
end

Arca.Callback.Register('arca_health:checkIn', function(src)
    if not cfg.CheckIn.Enabled or not atDesk(src) then return false end
    if #emsOnDuty() > cfg.CheckIn.MaxEMSOnDuty then
        notify(src, 'EMS are on duty, ask them for help', 'error')
        return false
    end
    local player = getPlayer(src)
    if not player then return false end
    if cfg.CheckIn.Fee > 0 and not player.RemoveMoney('bank', cfg.CheckIn.Fee, 'hospital check-in') then
        notify(src, ('You need $%d in the bank'):format(cfg.CheckIn.Fee), 'error')
        return false
    end
    checkingIn[src] = true
    return true
end)

RegisterNetEvent('arca_health:server:checkInDone', function()
    local src = source
    if not checkingIn[src] or not atDesk(src) then return end
    checkingIn[src] = nil
    heal(src)
end)

---------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------
local function targetArg(src, arg)
    local id = tonumber(arg) or src
    if id == 0 or not GetPlayerName(tostring(id)) then
        notify(src, 'Player is not online', 'error')
        return nil
    end
    return id
end

exports.arca_core:AddCommand('revive', 'Revive a player: /revive [id]', 'admin', function(src, args)
    local id = targetArg(src, args[1])
    if not id then return end
    revive(id)
    notify(src, 'Revived', 'success')
end)

exports.arca_core:AddCommand('heal', 'Heal a player: /heal [id]', 'admin', function(src, args)
    local id = targetArg(src, args[1])
    if not id then return end
    heal(id)
    notify(src, 'Healed', 'success')
end)

---------------------------------------------------------------------
-- Exports
---------------------------------------------------------------------
exports('Revive', revive)
exports('Heal', heal)
exports('GetState', stateOf)
exports('IsDead', function(src) return stateOf(src) == 'dead' end)
exports('IsDown', function(src) return stateOf(src) ~= 'alive' end)
exports('Kill', function(src) TriggerClientEvent('arca_health:client:kill', src) end)

-- statebag back after a resource restart / on login
AddEventHandler('arca_core:server:playerLoaded', function(player)
    local meta = player.PlayerData.metadata
    local state = meta.isdead and 'dead' or meta.inlaststand and 'laststand' or 'alive'
    Player(player.PlayerData.source).state:set('healthState', state, true)
    if state == 'dead' then deathAt[player.PlayerData.source] = os.time() end
end)

AddEventHandler('playerDropped', function()
    local src = source
    deathAt[src], lastAlert[src], checkingIn[src] = nil, nil, nil
end)
