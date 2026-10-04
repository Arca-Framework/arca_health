-- Injuries per body part, bleeding, limping and what caused the last hit.

local cfg = HealthConfig.Injuries

-- severity 0-4 per part, bleeding 0-4
Injuries = { parts = {}, bleeding = 0 }

local PART_LABELS = {
    head = 'Head', torso = 'Torso', larm = 'Left arm', rarm = 'Right arm', lleg = 'Left leg', rleg = 'Right leg',
}
local SEVERITY = { 'Bruised', 'Hurt', 'Badly hurt', 'Critical' }

local BONES = {
    [31086] = 'head', [39317] = 'head', [12844] = 'head', [65068] = 'head',
    [24816] = 'torso', [24817] = 'torso', [24818] = 'torso', [11816] = 'torso', [57597] = 'torso', [23553] = 'torso', [0] = 'torso',
    [18905] = 'larm', [61163] = 'larm', [45509] = 'larm', [64729] = 'larm',
    [57005] = 'rarm', [28252] = 'rarm', [40269] = 'rarm', [10706] = 'rarm',
    [14201] = 'lleg', [63931] = 'lleg', [58271] = 'lleg', [65245] = 'lleg',
    [52301] = 'rleg', [36864] = 'rleg', [51826] = 'rleg', [35502] = 'rleg',
}

-- weapon groups (GetWeapontypeGroup)
local BULLET_GROUPS = { [416676503] = true, [-957766203] = true, [970310034] = true, [1159398588] = true, [860033945] = true, [-1212426201] = true, [-1569042529] = true }
local MELEE_GROUPS = { [-728555052] = true, [-1609580060] = true }
local CUTTING = {
    [`WEAPON_KNIFE`] = true, [`WEAPON_DAGGER`] = true, [`WEAPON_MACHETE`] = true, [`WEAPON_SWITCHBLADE`] = true,
    [`WEAPON_BOTTLE`] = true, [`WEAPON_HATCHET`] = true, [`WEAPON_BATTLEAXE`] = true, [`WEAPON_STONE_HATCHET`] = true,
}
local SPECIAL = {
    [`WEAPON_FALL`] = 'Fall',
    [`WEAPON_RUN_OVER_BY_CAR`] = 'Hit by a vehicle', [`WEAPON_RAMMED_BY_CAR`] = 'Vehicle crash',
    [`WEAPON_EXPLOSION`] = 'Explosion', [`WEAPON_FIRE`] = 'Burns', [`WEAPON_MOLOTOV`] = 'Burns',
    [`WEAPON_DROWNING`] = 'Drowned', [`WEAPON_DROWNING_IN_VEHICLE`] = 'Drowned',
    [`WEAPON_BLEEDING`] = 'Blood loss', [`WEAPON_ANIMAL`] = 'Animal attack', [`WEAPON_COUGAR`] = 'Animal attack',
    [`WEAPON_STUNGUN`] = 'Tased', [`WEAPON_BARBED_WIRE`] = 'Cuts',
}

local lastCause = 'Unknown'
function HealthLastCause() return lastCause end

local function classify(weapon)
    if SPECIAL[weapon] then return SPECIAL[weapon], weapon == `WEAPON_FALL` and 'fall' or 'other' end
    if CUTTING[weapon] then return 'Stab wound', 'cut' end
    local group = GetWeapontypeGroup(weapon)
    if BULLET_GROUPS[group] then return 'Gunshot wound', 'bullet' end
    if MELEE_GROUPS[group] then return 'Blunt force', 'blunt' end
    return 'Unknown', 'other'
end

---------------------------------------------------------------------
-- Syncing to the server (saved in metadata.injuries)
---------------------------------------------------------------------
local dirty = false
local function changed() dirty = true end

CreateThread(function()
    while true do
        Wait(2000)
        if dirty and LocalPlayer.state.isLoggedIn then
            dirty = false
            TriggerServerEvent('arca_health:server:syncInjuries', Injuries)
        end
    end
end)

function HealthClearInjuries()
    Injuries.parts, Injuries.bleeding = {}, 0
    changed()
end

---------------------------------------------------------------------
-- Taking damage
---------------------------------------------------------------------
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local ped = PlayerPedId()
    if args[1] ~= ped then return end
    local weapon = args[7]
    local cause, kind = classify(weapon)
    lastCause = cause
    if not cfg.Enabled or Health.state ~= 'alive' then return end

    local hit, bone = GetPedLastDamageBone(ped)
    local part = (hit and BONES[bone]) or 'torso'
    if kind == 'fall' then part = math.random(2) == 1 and 'lleg' or 'rleg' end
    if kind == 'other' and cause == 'Unknown' then return end
    if cause == 'Tased' then return end

    Injuries.parts[part] = math.min(4, (Injuries.parts[part] or 0) + 1)
    if kind == 'bullet' or (kind == 'cut' and math.random(100) <= 70) then
        local before = Injuries.bleeding
        Injuries.bleeding = math.min(4, Injuries.bleeding + 1)
        if before == 0 then exports.arca_core:Notify('You are bleeding', 'error') end
    end
    changed()
end)

---------------------------------------------------------------------
-- Effects: bleeding, limping, blur
---------------------------------------------------------------------
local limping, blurred = false, false

local function legSeverity()
    return math.max(Injuries.parts.lleg or 0, Injuries.parts.rleg or 0)
end

-- bleed ticks
CreateThread(function()
    while true do
        Wait(cfg.BleedInterval * 1000)
        if cfg.Enabled and Injuries.bleeding > 0 and Health.state == 'alive' and LocalPlayer.state.isLoggedIn then
            local ped = PlayerPedId()
            lastCause = 'Blood loss'
            SetEntityHealth(ped, math.max(0, GetEntityHealth(ped) - Injuries.bleeding * cfg.BleedDamage))
            -- a little blood on the clothes
            ApplyPedDamagePack(ped, 'BigHitByVehicle', 0.0, 0.3)
        end
    end
end)

-- movement / screen effects
CreateThread(function()
    RequestAnimSet('move_m@injured')
    while true do
        local sleep = 500
        if cfg.Enabled and Health.state == 'alive' then
            local ped = PlayerPedId()
            local limp = legSeverity() >= cfg.LimpFromSeverity
            if limp then
                sleep = 0
                DisableControlAction(0, 21, true) -- sprint
                DisableControlAction(0, 22, true) -- jump
            end
            if limp ~= limping then
                limping = limp
                if limp then SetPedMovementClipset(ped, 'move_m@injured', 1.0) else ResetPedMovementClipset(ped, 1.0) end
            end
            local blur = Injuries.bleeding >= cfg.BlurFromBleeding
            if blur ~= blurred then
                blurred = blur
                if blur then SetTimecycleModifier('BarryFadeOut') SetTimecycleModifierStrength(0.35) else ClearTimecycleModifier() end
            end
        elseif limping or blurred then
            limping, blurred = false, false
            ResetPedMovementClipset(PlayerPedId(), 1.0)
            ClearTimecycleModifier()
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------
-- Healing
---------------------------------------------------------------------
-- EMS treatment: everything fixed
RegisterNetEvent('arca_health:client:treat', function()
    HealthClearInjuries()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    exports.arca_core:Notify('Your wounds have been treated', 'success')
end)

-- arca_inventory bandage (25) slows bleeding, medikit (100) stops it
RegisterNetEvent('arca_inventory:client:heal', function(amount)
    if amount >= 100 then
        Injuries.bleeding = 0
        for part, sev in pairs(Injuries.parts) do Injuries.parts[part] = math.max(0, sev - 2) end
    else
        Injuries.bleeding = math.max(0, Injuries.bleeding - 1)
    end
    changed()
end)

-- admin heal / qb heal events
RegisterNetEvent('arca_admin:client:heal', HealthClearInjuries)
RegisterNetEvent('hospital:client:HealInjuries', HealthClearInjuries)

-- revived -> injuries reset
AddEventHandler('arca_health:client:stateChanged', function(state)
    if state == 'alive' then HealthClearInjuries() end
end)

-- saved injuries come back on login
AddEventHandler('arca_core:client:onPlayerLoaded', function(data)
    local saved = data.metadata and data.metadata.injuries
    if type(saved) == 'table' then
        Injuries.parts = type(saved.parts) == 'table' and saved.parts or {}
        Injuries.bleeding = tonumber(saved.bleeding) or 0
    end
end)

---------------------------------------------------------------------
-- Readable list (used by EMS "check injuries" and the export)
---------------------------------------------------------------------
function HealthDescribe(data)
    local list = {}
    for part, sev in pairs(data.parts or {}) do
        if sev > 0 then list[#list + 1] = { part = PART_LABELS[part] or part, severity = sev, label = SEVERITY[sev] or 'Hurt' } end
    end
    table.sort(list, function(a, b) return a.severity > b.severity end)
    return list
end

exports('GetInjuries', function() return Injuries end)
exports('ClearInjuries', HealthClearInjuries)
exports('IsBleeding', function() return Injuries.bleeding > 0 end)
