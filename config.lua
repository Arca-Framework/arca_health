HealthConfig = {
    -- Downed first (can be revived, can call for help), then dead (respawn at a hospital)
    LastStand = {
        Enabled = true,
        Time = 180,             -- seconds downed before bleeding out
    },
    DeathTime = 300,            -- seconds dead before "hold E to respawn" appears
    RespawnHoldTime = 3,        -- seconds to hold E

    -- Respawning at a hospital after dying
    Respawn = {
        Fee = 500,              -- taken from bank (0 = free)
        ClearInventory = false, -- lose everything (needs arca_inventory)
        Hospitals = {
            { label = 'Pillbox Hill Medical', coords = vector4(357.43, -593.36, 28.79, 250.0) },
            { label = 'Sandy Shores Medical', coords = vector4(1839.22, 3672.89, 34.28, 210.0) },
            { label = 'Paleto Bay Medical', coords = vector4(-247.76, 6331.23, 32.43, 225.0) },
        },
    },

    -- Who counts as EMS (job name = minimum grade)
    EMSJobs = { ambulance = 0 },
    CallEMSCooldown = 60,       -- seconds between "call EMS" presses

    -- What EMS (and admins) can do to other players
    Revive = {
        Distance = 3.0,
        Duration = 8000,        -- ms progress bar
        Item = false,           -- item used up per revive, e.g. 'medikit' (false = none)
    },
    Treat = {
        Duration = 5000,        -- ms to treat wounds (stops bleeding, heals injuries)
        Item = false,           -- e.g. 'bandage'
    },

    -- Hospital check-in desk: heal yourself for a fee when few EMS are on duty
    CheckIn = {
        Enabled = true,
        Fee = 250,
        Duration = 10000,
        MaxEMSOnDuty = 0,       -- only allowed when this many EMS or fewer are on duty
        Ped = 's_m_m_doctor_01',
        Locations = {
            vector4(308.52, -592.30, 43.28, 70.0),     -- Pillbox Hill reception
        },
    },

    -- Injuries & bleeding
    Injuries = {
        Enabled = true,
        BleedInterval = 30,     -- seconds between bleed ticks
        BleedDamage = 2,        -- health lost per tick per bleed level (1-4)
        LimpFromSeverity = 2,   -- leg injury severity that makes you limp and stop sprinting
        BlurFromBleeding = 3,   -- bleed level that blurs the screen
    },
}
