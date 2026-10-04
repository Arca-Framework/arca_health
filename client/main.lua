-- Last stand, death, the death screen and reviving.
--   alive -> laststand (downed, can be revived) -> dead (respawn at a hospital)

Health = {
    state = 'alive',        -- 'alive' | 'laststand' | 'dead'
    cause = nil,            -- what put us down, from client/injuries.lua
}

local cfg = HealthConfig
local stateEndsAt = 0       -- GetGameTimer() when the current timer runs out
local lastEmsCall = 0

local function notify(msg, kind) exports.arca_core:Notify(msg, kind or 'inform') end

---------------------------------------------------------------------
-- Animations
---------------------------------------------------------------------
local ANIMS = {
    laststand = { dict = 'combat@damage@writhe', clip = 'writhe_loop' },
    dead = { dict = 'dead', clip = 'dead_a' },
    vehicle = { dict = 'veh@low@front_ps@idle_duck', clip = 'sit' },
}

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
end

local function currentAnim()
    if IsPedInAnyVehicle(PlayerPedId(), false) then return ANIMS.vehicle end
    return ANIMS[Health.state]
end

---------------------------------------------------------------------
-- Entering / leaving states
---------------------------------------------------------------------
local function sendScreen()
    if Health.state == 'alive' then
        return SendNUIMessage({ action = 'hide' })
    end
    SendNUIMessage({
        action = 'show',
        data = {
            state = Health.state,
            cause = Health.cause,
            seconds = math.max(0, math.ceil((stateEndsAt - GetGameTimer()) / 1000)),
            total = Health.state == 'laststand' and cfg.LastStand.Time or cfg.DeathTime,
            holdTime = cfg.RespawnHoldTime,
        },
    })
end

---Bring the ped back to life where it lies, so it stays in place for the anims
local function resurrect()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local seat
    if veh ~= 0 then
        for s = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
            if GetPedInVehicleSeat(veh, s) == ped then seat = s break end
        end
    end
    if IsEntityDead(ped) then
        local c = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
        if veh ~= 0 and seat then SetPedIntoVehicle(ped, veh, seat) end
    end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetEntityInvincible(ped, true)
    SetPlayerInvincible(PlayerId(), true)
    ClearPedBloodDamage(ped)
    return ped
end

local function setState(state, cause)
    Health.state = state
    if cause then Health.cause = cause end
    if state == 'laststand' then
        stateEndsAt = GetGameTimer() + cfg.LastStand.Time * 1000
    elseif state == 'dead' then
        stateEndsAt = GetGameTimer() + cfg.DeathTime * 1000
    end
    TriggerServerEvent('arca_health:server:setState', state, Health.cause)
    TriggerEvent('arca_health:client:stateChanged', state, Health.cause)
    sendScreen()
end

---Called when the ped dies (or on login while dead)
local function goDown(cause, forceDead)
    if Health.state == 'dead' then return end
    resurrect()
    if not forceDead and cfg.LastStand.Enabled and Health.state == 'alive' then
        setState('laststand', cause)
    else
        setState('dead', cause)
    end
end

---Back on your feet (EMS, admin, respawn). Safe to call more than once.
function HealthRevive()
    local wasDown = Health.state ~= 'alive'
    local ped = PlayerPedId()
    if IsEntityDead(ped) then ped = resurrect() end
    Health.state, Health.cause = 'alive', nil
    if IsPedInAnyVehicle(ped, false) then ClearPedTasks(ped) else ClearPedTasksImmediately(ped) end
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    SendNUIMessage({ action = 'hide' })
    if wasDown then
        TriggerServerEvent('arca_health:server:setState', 'alive')
        TriggerEvent('arca_health:client:stateChanged', 'alive')
    end
end

---------------------------------------------------------------------
-- Watching for death
---------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 250
        if LocalPlayer.state.isLoggedIn then
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                if Health.state == 'alive' then
                    goDown(HealthLastCause and HealthLastCause() or 'Unknown')
                elseif Health.state == 'laststand' then
                    -- finished off while downed (e.g. invincibility removed by another script)
                    goDown(Health.cause, true)
                else
                    resurrect()
                end
            end
            if Health.state ~= 'alive' then sleep = 0 end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------
-- While down: anims, controls, timers, keys
---------------------------------------------------------------------
local ALLOWED = { 1, 2, 245, 249, 199, 200, 38, 47 } -- look, chat, push-to-talk, pause, E, G

CreateThread(function()
    local holdStart, lastScreen = nil, 0
    while true do
        if Health.state == 'alive' then
            Wait(250)
        else
            local ped = PlayerPedId()
            DisableAllControlActions(0)
            for i = 1, #ALLOWED do EnableControlAction(0, ALLOWED[i], true) end

            -- keep the anim playing (other scripts / ragdoll can cancel it)
            local anim = currentAnim()
            if anim and not IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
                loadDict(anim.dict)
                TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, 8.0, -1, 1, 0, false, false, false)
            end

            local now = GetGameTimer()

            -- G: call EMS
            if IsControlJustPressed(0, 47) then
                if now - lastEmsCall < cfg.CallEMSCooldown * 1000 then
                    notify('You already called for help', 'error')
                else
                    lastEmsCall = now
                    TriggerServerEvent('arca_health:server:callEMS')
                    notify('EMS have been notified', 'success')
                end
            end

            -- downed timer runs out: bleed out
            if Health.state == 'laststand' and now >= stateEndsAt then
                setState('dead')
            end

            -- dead and the timer is done: hold E to respawn
            if Health.state == 'dead' and now >= stateEndsAt then
                if IsControlPressed(0, 38) then
                    holdStart = holdStart or now
                    SendNUIMessage({ action = 'hold', data = math.min(1, (now - holdStart) / (cfg.RespawnHoldTime * 1000)) })
                    if now - holdStart >= cfg.RespawnHoldTime * 1000 then
                        holdStart = nil
                        TriggerServerEvent('arca_health:server:respawn')
                        Wait(1000)
                    end
                elseif holdStart then
                    holdStart = nil
                    SendNUIMessage({ action = 'hold', data = 0 })
                end
            end

            if now - lastScreen > 1000 then
                lastScreen = now
                sendScreen()
            end
            Wait(0)
        end
    end
end)

---------------------------------------------------------------------
-- From the server / other resources
---------------------------------------------------------------------
RegisterNetEvent('arca_health:client:revive', HealthRevive)
AddEventHandler('arca_core:client:revived', HealthRevive)          -- arca_admin revive
RegisterNetEvent('hospital:client:Revive', HealthRevive)           -- qb scripts (network and local)

RegisterNetEvent('arca_health:client:respawn', function(coords)
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    HealthRevive()
    if HealthClearInjuries then HealthClearInjuries() end
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, coords.w)
    Wait(500)
    DoScreenFadeIn(800)
end)

RegisterNetEvent('arca_health:client:kill', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

-- coming back online while downed / dead
AddEventHandler('arca_core:client:onPlayerLoaded', function(data)
    local meta = data.metadata or {}
    Wait(2000) -- let arca_character finish spawning
    if meta.isdead then
        goDown(meta.deathcause or 'Unknown', true)
    elseif meta.inlaststand then
        goDown(meta.deathcause or 'Unknown')
    end
end)

AddEventHandler('arca_core:client:onPlayerUnloaded', function()
    if Health.state ~= 'alive' then
        Health.state = 'alive'
        SendNUIMessage({ action = 'hide' })
        SetEntityInvincible(PlayerPedId(), false)
    end
end)

---------------------------------------------------------------------
-- Exports
---------------------------------------------------------------------
exports('GetState', function() return Health.state end)
exports('IsDead', function() return Health.state == 'dead' end)
exports('IsDown', function() return Health.state ~= 'alive' end)
exports('Revive', HealthRevive)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or Health.state == 'alive' then return end
    SetEntityInvincible(PlayerPedId(), false)
    ClearPedTasks(PlayerPedId())
end)
