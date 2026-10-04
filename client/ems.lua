-- EMS: revive / treat / check injuries on other players, alerts, and the hospital check-in desk.

local cfg = HealthConfig

local function notify(msg, kind) exports.arca_core:Notify(msg, kind or 'inform') end

local function serverIdOf(ped)
    local idx = NetworkGetPlayerIndexFromPed(ped)
    return idx ~= -1 and GetPlayerServerId(idx) or nil
end

---The downed state the server published for another player
local function stateOf(ped)
    local id = serverIdOf(ped)
    return id and Player(id).state.healthState or 'alive'
end

local function isEMS()
    local pd = exports.arca_core:GetPlayerData() or {}
    local job = pd.job
    if not job or not job.onduty then return false end
    local min = cfg.EMSJobs[job.name]
    return min ~= nil and job.grade.level >= min
end

---------------------------------------------------------------------
-- Treating other players
---------------------------------------------------------------------
local busy = false

local function withProgress(label, duration, anim, fn)
    if busy then return end
    busy = true
    local done = exports.arca_core:Progress({
        label = label, duration = duration, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = anim,
    })
    busy = false
    if done then fn() end
end

local function revivePlayer(data)
    local id = serverIdOf(data.entity)
    if not id then return end
    TaskTurnPedToFaceEntity(PlayerPedId(), data.entity, 800)
    withProgress('Reviving', cfg.Revive.Duration, { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 }, function()
        TriggerServerEvent('arca_health:server:revive', id)
    end)
end

local function treatPlayer(data)
    local id = serverIdOf(data.entity)
    if not id then return end
    TaskTurnPedToFaceEntity(PlayerPedId(), data.entity, 800)
    withProgress('Treating wounds', cfg.Treat.Duration, { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 }, function()
        TriggerServerEvent('arca_health:server:treat', id)
    end)
end

local function checkPlayer(data)
    local id = serverIdOf(data.entity)
    if not id then return end
    local info = Arca.Callback.Await('arca_health:getInjuries', id)
    if not info then return notify('Get closer to check them', 'error') end

    local options = {}
    local stateLabel = info.state == 'dead' and 'Unresponsive' or info.state == 'laststand' and 'Conscious, downed' or 'Conscious'
    options[#options + 1] = { title = stateLabel, icon = 'fa-solid fa-heart-pulse', disabled = true,
        description = info.cause and ('Likely cause: %s'):format(info.cause) or nil }
    options[#options + 1] = { title = info.bleeding > 0 and ('Bleeding (level %d)'):format(info.bleeding) or 'Not bleeding',
        icon = 'fa-solid fa-droplet', disabled = true }
    for _, injury in ipairs(HealthDescribe(info)) do
        options[#options + 1] = { title = injury.part, description = injury.label, icon = 'fa-solid fa-user-injured', disabled = true }
    end
    if #options == 2 and info.bleeding == 0 then
        options[#options + 1] = { title = 'No visible injuries', icon = 'fa-solid fa-check', disabled = true }
    end
    Arca.RegisterContext({ id = 'arca_health:check', title = 'Patient', options = options })
    Arca.ShowContext('arca_health:check')
end

-- arca_target can report 'started' before its exports exist (resources start alphabetically),
-- so keep trying for a while instead of checking once
local function whenTargetReady(fn)
    CreateThread(function()
        for _ = 1, 60 do
            if GetResourceState('arca_target') == 'started' and pcall(fn) then return end
            Wait(500)
        end
    end)
end

local function registerTargets()
    exports.arca_target:addGlobalPlayer({
        { name = 'arca_health:revive', label = 'Revive', icon = 'fa-solid fa-heart-pulse', distance = cfg.Revive.Distance,
          canInteract = function(entity) return isEMS() and stateOf(entity) ~= 'alive' end,
          onSelect = revivePlayer },
        { name = 'arca_health:treat', label = 'Treat wounds', icon = 'fa-solid fa-kit-medical', distance = cfg.Revive.Distance,
          canInteract = function(entity) return isEMS() and stateOf(entity) == 'alive' end,
          onSelect = treatPlayer },
        { name = 'arca_health:check', label = 'Check injuries', icon = 'fa-solid fa-stethoscope', distance = cfg.Revive.Distance,
          canInteract = function() return isEMS() end,
          onSelect = checkPlayer },
    })
end

whenTargetReady(registerTargets)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'arca_target' then registerTargets() end
end)

---------------------------------------------------------------------
-- EMS alerts
---------------------------------------------------------------------
RegisterNetEvent('arca_health:client:alert', function(coords, name)
    notify(('Injured person reported: %s'):format(name), 'warning')
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.1)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Injured person')
    EndTextCommandSetBlipName(blip)
    SetTimeout(120000, function() RemoveBlip(blip) end)
end)

---------------------------------------------------------------------
-- Hospital check-in desk
---------------------------------------------------------------------
local deskPeds = {}

local function checkIn()
    local ok = Arca.Callback.Await('arca_health:checkIn')
    if not ok then return end
    withProgress('Getting treated', cfg.CheckIn.Duration, { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 1 }, function()
        TriggerServerEvent('arca_health:server:checkInDone')
    end)
end

local function spawnDesk(loc)
    local model = joaat(cfg.CheckIn.Ped)
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(model) then return end
    local ped = CreatePed(4, model, loc.x, loc.y, loc.z - 1.0, loc.w, false, true)
    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    -- pcall: arca_target may not be ready yet; the desk respawns (and registers) when it starts
    if GetResourceState('arca_target') == 'started' then
        pcall(function()
            exports.arca_target:addLocalEntity(ped, {
                { name = 'arca_health:checkin', label = ('Check in ($%d)'):format(cfg.CheckIn.Fee), icon = 'fa-solid fa-hospital', distance = 2.5,
                  onSelect = checkIn },
            })
        end)
    end
    return ped
end

if cfg.CheckIn.Enabled then
    CreateThread(function()
        local prompt = false
        while true do
            local coords = GetEntityCoords(PlayerPedId())
            local near
            for i, loc in ipairs(cfg.CheckIn.Locations) do
                local dist = #(coords - vector3(loc.x, loc.y, loc.z))
                if dist < 40.0 and not deskPeds[i] then
                    deskPeds[i] = spawnDesk(loc)
                elseif dist > 50.0 and deskPeds[i] then
                    DeleteEntity(deskPeds[i])
                    deskPeds[i] = nil
                end
                if dist < 2.0 then near = true end
            end
            -- without arca_target: walk up and press E
            if near and GetResourceState('arca_target') ~= 'started' and Health.state == 'alive' then
                if not prompt then
                    exports.arca_core:ShowTextUI(('[E] Check in ($%d)'):format(cfg.CheckIn.Fee), { icon = 'fa-solid fa-hospital' })
                    prompt = true
                end
                if IsControlJustPressed(0, 38) then checkIn() end
                Wait(0)
            else
                if prompt then exports.arca_core:HideTextUI() prompt = false end
                Wait(500)
            end
        end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, ped in pairs(deskPeds) do DeleteEntity(ped) end
end)

-- arca_target (re)started: respawn the desk peds so they register their option
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'arca_target' then return end
    for i, ped in pairs(deskPeds) do DeleteEntity(ped) deskPeds[i] = nil end
end)
