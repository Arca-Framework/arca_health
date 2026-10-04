# arca_health

The medical core for the Arca framework: last stand, death screen, injuries, bleeding, EMS tools and hospital respawns.

## How it works

1. **Downed.** When your health hits zero you go down (last stand). You can talk and press **G** to call EMS. A timer counts down until you bleed out.
2. **Unconscious.** When the timer runs out, or with last stand turned off, you're unconscious. After `DeathTime`, **hold E** to respawn at the nearest hospital. The bill comes out of your bank.
3. **Revived.** EMS, admins or scripts can revive you at any point.

Death state is saved in metadata (`isdead`, `inlaststand`, `deathcause`), so logging out doesn't get you out of it.

## Injuries

- Hits are tracked per body part (head, torso, arms, legs) with a severity from 1 to 4. The cause is worked out from the weapon: gunshot, stab, blunt force, fall, vehicle, burns and so on.
- **Bullets and blades** cause bleeding, which takes health every 30 seconds. Heavy bleeding blurs the screen.
- **Leg injuries** make you limp, and you can't sprint or jump.
- **arca_inventory bandage** lowers bleeding. A **medikit** stops it.
- Injuries are saved and come back after a relog.

## EMS

For on-duty `ambulance` players, using arca_target:

- **Revive** a downed or unconscious player (CPR progress).
- **Treat wounds**: heals and clears injuries and bleeding.
- **Check injuries**: shows their state, the likely cause, bleeding and each injured body part.
- **Alerts**: when someone presses G, EMS get a notification and a flashing blip.

**Check-in desk:** at Pillbox reception, players can pay to be treated when no EMS are on duty.

## Commands

| Command | Permission | |
|---|---|---|
| `/revive [id]` | admin | Revive a player (or yourself) |
| `/heal [id]` | admin | Heal a player and clear their injuries |

The arca_admin menu's Revive and Heal buttons work with arca_health.

## Exports

**Server:** `Revive(src)`, `Heal(src)`, `Kill(src)`, `GetState(src)` (`'alive'`, `'laststand'` or `'dead'`), `IsDead(src)`, `IsDown(src)`

**Client:** `GetState()`, `IsDead()`, `IsDown()`, `Revive()`, `GetInjuries()`, `ClearInjuries()`, `IsBleeding()`

**Statebag:** `Player(src).state.healthState`, readable on every client.

## Events

| Event | Side | Arguments |
|---|---|---|
| `arca_health:client:stateChanged` | client (local) | `state, cause` |
| `arca_health:server:stateChanged` | server | `source, state, cause` |
| `arca_health:server:emsCalled` | server | `source, coords`, for dispatch scripts |

It also listens to `hospital:client:Revive` and `hospital:client:HealInjuries`, so qb scripts that revive or heal still work.
