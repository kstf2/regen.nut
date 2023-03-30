/*
====================================================================================================
regen.nut: Better Ammo Regen for Jump Maps
by Kingstripes, ficool2

Repo:
Forum Post:
====================================================================================================
*/

ClearGameEventCallbacks()

const VERSION = "1.0"

// Condensed version of ETFClass class constants, used for user-supplied arguments:
const scout = 1
const sniper = 2
const soldier = 3; const solly = 3
const demoman = 4; const demo = 4
const medic = 5
const heavy = 6
const pyro = 7
const spy = 8
const engineer = 9
const civilian = 10
const any = 11

// Better not to deal with dropped weapon bugs
// (in particular weapons in a limited projectile state)
Convars.SetValue("tf_dropped_weapon_lifetime", 0)

/*
When CVAR_REGEN_DEBUG_MODE is turned on, useful info
will be printed to the (server) console

Run "script DebugToggle()" in server console to toggle
*/
if (!("CVAR_REGEN_DEBUG_MODE" in getroottable()))
    ::CVAR_REGEN_DEBUG_MODE <- false

::DebugToggle <- function()
{
    CVAR_REGEN_DEBUG_MODE = !CVAR_REGEN_DEBUG_MODE
    local toggleState = CVAR_REGEN_DEBUG_MODE ? "\x073EFF3EON" : "\x07FF4040OFF"

    ClientPrint(null, Constants.EHudNotify.HUD_PRINTTALK, "\x07191970[\x074B69FFregen.nut\x07191970]\x01 Debug mode " + toggleState)
    printl(CVAR_REGEN_DEBUG_MODE ? "[regen.nut] Script version " + VERSION : "")
    printl("[regen.nut] Debug mode " + (CVAR_REGEN_DEBUG_MODE ? "ON" : "OFF"))
}

::DebugPrint <- function(message, client = null)
{
    if (!CVAR_REGEN_DEBUG_MODE)
    {
        return
    }

    local clientName
    if (client)
    {
        clientName = NetProps.GetPropString(client, "m_szNetname")
    }

    printl("[regen.nut|" + Time() + "] " + (clientName != null ? clientName + ": " : "") + message)
}

/*
====================================================================================================
1. SIMPLE LIMITED REGEN

Description:    Similar to func_regenerate triggers except there is no 3.0 second timer.
                You are regenerated instantly upon touching a trigger but you can only be
                regenerated by each trigger *ONCE* per attempt (so no lingering in a trigger
                for infinite ammo like a normal func_regenerate trigger).

Demonstration: https://youtu.be/N8VZVMei1zc?t=5

Usage:
====================================================================================================
*/

::CTFPlayer.RegenInit <- function()
{
        if (this.ValidateScriptScope())
        {
            if (!("touchedTriggers" in this.GetScriptScope()))
                this.GetScriptScope().touchedTriggers <- []
        }
}

::CTFPlayer.RegenReset <- function()
{
    if (this.ValidateScriptScope())
    {
        DebugPrint("reset touched regen triggers", this)
        this.GetScriptScope().touchedTriggers.clear()
    }
}

function Regen(playerClass = any)
{
    local player = activator
    if (!player || !player.IsPlayer())
    {
        return
    }

    if (playerClass != any && player.GetPlayerClass() != playerClass)
    {
        return
    }

    if (player.ValidateScriptScope())
    {
        local touchedTriggers = player.GetScriptScope().touchedTriggers
        local trigger = caller

        if (touchedTriggers.find(trigger) == null)
        {
            DebugPrint("touched regen trigger " + trigger, player)
            touchedTriggers.append(trigger)
            player.GetScriptScope().lastRegenTick <- Time()
            player.Regenerate(true)
        }
    }
}

function ResetTouched()
{
    local player = activator
    if (!player || !player.IsPlayer())
    {
        return
    }

    player.RegenReset()
}

function OnGameEvent_player_spawn(params)
{
    if ("userid" in params)
    {
        local player = GetPlayerFromUserID(params.userid)
        player.RegenInit()
        player.RegenReset()
    }
}

/*
====================================================================================================
2. PROJECTILE LIMIT TRIGGERS (MMOD STYLE)

Description:    Inspired by Momentum Mod's proposed system for dealing with limited regen.
                Upon touching a limit trigger, you are given X number of projectiles to complete
                a jump. In this state, reloading weapons is blocked and once reaching 0 clip ammo,
                the weapon will turn translucent and will not be shootable until another trigger
                (i.e. either reset or another limit trigger) is touched. You can currently limit
                all rocket launcher primaries, shotguns, all grenade launcher primaries and all
                stickybomb launcher secondaries.

Demonstration: https://youtu.be/N8VZVMei1zc?t=62

Usage:
====================================================================================================
*/

const GLOBAL_WEAPON_COUNT = 10
const RENDER_TRANSCOLOR = 1
const destroy = 1

const ORIGINAL_IDX = 513
const BEGGARS_BAZOOKA_IDX = 730
const LOCH_N_LOAD_IDX = 308

enum TF_WEAPONSLOTS {
    PRIMARY,
    SECONDARY,
    MELEE
}

local AllowedWeapons = ["tf_weapon_rocketlauncher", "tf_weapon_particle_cannon", "tf_weapon_rocketlauncher_directhit",
                        "tf_weapon_rocketlauncher_airstrike", "tf_weapon_shotgun_soldier", "tf_weapon_shotgun",
                        "tf_weapon_raygun", "tf_weapon_grenadelauncher", "tf_weapon_cannon", "tf_weapon_pipebomblauncher"]

local LimitFunctions = ["RocketLimit", "ShotgunLimit", "PipeLimit", "StickyLimit", "ResetTouched"]

local AnimSequences = {
    // Soldier primary/secondary
    tf_weapon_rocketlauncher   = {idle = 2, reloadStart = 5, reloadFinish = 10}, // + _directhit/_airstrike
    tf_weapon_particle_cannon  = {idle = 2, reloadStart = 12, reloadFinish = 14},
    tf_weapon_shotgun          = {idle = 29, reloadStart = 31, reloadFinish = 33}, // + _soldier
    tf_weapon_raygun           = {idle = 38, reloadStart = 40, reloadFinish = 42},

    // Demoman primary/secondary
    tf_weapon_grenadelauncher  = {idle = 25, reloadStart = 28, reloadFinish = 30},
    tf_weapon_pipebomblauncher = {idle = 17, reloadStart = 21, reloadFinish = 23}
}

// Weapons that do not have a unique classname, but *do* have unique animations
AnimSequences[ORIGINAL_IDX] <- {idle = 43, reloadStart = 46, reloadFinish = 48}
AnimSequences[LOCH_N_LOAD_IDX] <- {idle = 25, reloadStart = 36, reloadFinish = 38}

::SetEntityColor <- function(entity, r, g, b, a)
{
    local color = (r) | (g << 8) | (b << 16) | (a << 24)
    NetProps.SetPropInt(entity, "m_nRenderMode", RENDER_TRANSCOLOR)
    NetProps.SetPropInt(entity, "m_clrRender", color)
}

::CTFWeaponBase.GetItemDefinitionIndex <- function()
{
    if (this == null) return

    return NetProps.GetPropInt(this, "m_AttributeManager.m_Item.m_iItemDefinitionIndex")
}

::CTFWeaponBase.GetReserveAmmo <- function()
{
    if (this == null || this.GetOwner() == null || !this.GetOwner().IsPlayer()) return null

    return NetProps.GetPropIntArray(this.GetOwner(), "m_iAmmo", this.GetPrimaryAmmoType())
}

::CTFWeaponBase.SetReserveAmmo <- function(amount)
{
    if (this == null || this.GetOwner() == null || !this.GetOwner().IsPlayer()) return

    NetProps.SetPropIntArray(this.GetOwner(), "m_iAmmo", amount, this.GetPrimaryAmmoType())
}

::CTFWeaponBase.BlockReload <- function()
{
    if (NetProps.GetPropInt(this, "m_iReloadMode") > 0)
    {
        if (NetProps.GetPropFloat(this, "m_flNextPrimaryAttack") > Time()) // reload time increase means that this is set to Time()+50s
        {
            // This won't impact anything while weapon equipped, but is useful for when switching weapons
            // and iReloadMode goes back to 0, where firing with >curTime means +attack won't work
            NetProps.SetPropFloat(this, "m_flNextPrimaryAttack", Time())
            DebugPrint("override next primary attack (BlockReload)", this.GetOwner())
        }

        // Listen servers get jittery setting this every tick so let's call it less frequently
        if (NetProps.GetPropFloat(this, "m_flTimeWeaponIdle") < Time() + 1.0 || NetProps.GetPropFloat(this, "m_flTimeWeaponIdle") > Time() + 2.0)
        {
            // Overrides reload in CTFWeaponBase::ReloadSinglyPostFrame
            NetProps.SetPropFloat(this, "m_flTimeWeaponIdle", Time() + 2.0)
        }
    }
}

::CTFWeaponBase.ResetAnimSequence <- function()
{
    // Don't set to idle animation for unmodified BB because "reloading" is actually loading the clip instead
    if (this.GetItemDefinitionIndex() == BEGGARS_BAZOOKA_IDX && GetMaxClip1() == 3)
    {
        return
    }

    local playerClass = this.GetOwner().GetPlayerClass()

    // Since this function only ever runs post-GetWeaponBySlot, the else conditions
    // *will* be matching weapons in the allow list
    switch (playerClass)
    {
        case Constants.ETFClass.TF_CLASS_SOLDIER:
            if (this.GetSlot() == TF_WEAPONSLOTS.PRIMARY)
            {
                if (this.GetItemDefinitionIndex() == ORIGINAL_IDX)
                {
                    SetToIdleAnim(ORIGINAL_IDX)
                }
                else if (this.GetClassname() == "tf_weapon_particle_cannon")
                {
                    SetToIdleAnim("tf_weapon_particle_cannon")
                }
                else // Matches tf_weapon_rocketlauncher and all variants
                {
                    SetToIdleAnim("tf_weapon_rocketlauncher")
                }
            }
            else if (this.GetSlot() == TF_WEAPONSLOTS.SECONDARY)
            {
                if (this.GetClassname() == "tf_weapon_raygun")
                {
                    SetToIdleAnim("tf_weapon_raygun")
                }
                else // Matches tf_weapon_shotgun and _soldier variant
                {
                    SetToIdleAnim("tf_weapon_shotgun")
                }
            }
            break

        case Constants.ETFClass.TF_CLASS_DEMOMAN:
            if (this.GetSlot() == TF_WEAPONSLOTS.PRIMARY)
            {
                if (this.GetItemDefinitionIndex() == LOCH_N_LOAD_IDX)
                {
                    SetToIdleAnim(LOCH_N_LOAD_IDX)
                }
                else // Matches all tf_weapon_grenadelauncher + tf_weapon_cannon
                {
                    SetToIdleAnim("tf_weapon_grenadelauncher")
                }
            }
            else if (this.GetSlot() == TF_WEAPONSLOTS.SECONDARY)
            {
                SetToIdleAnim("tf_weapon_pipebomblauncher")
            }
    }
}

::CTFWeaponBase.SetToIdleAnim <- function(sequenceKey)
{
    local player = this.GetOwner()
    local viewmodel = NetProps.GetPropEntity(player, "m_hViewModel")
    local sequence = AnimSequences[sequenceKey]

    if (viewmodel.GetSequence() >= sequence.reloadStart && viewmodel.GetSequence() <= sequence.reloadFinish)
    {
        viewmodel.SetSequence(sequence.idle)
    }
}

::CTFPlayer.DestroyProjectile <- function(classname)
{
    local ent = null
    local playerClass = this.GetPlayerClass()

    while (ent = Entities.FindByClassname(ent, classname))
    {
        local owner = (playerClass == Constants.ETFClass.TF_CLASS_DEMOMAN) ? NetProps.GetPropEntity(ent, "m_hThrower") : ent.GetOwner()
        if (owner == this)
        {
            ent.Destroy()
        }
    }
}

::CTFPlayer.DestroySollyProjectiles <- function()
{
    local primaryWep = this.GetWeaponBySlot(Constants.ETFClass.TF_CLASS_SOLDIER, TF_WEAPONSLOTS.PRIMARY)
    local secondaryWep = this.GetWeaponBySlot(Constants.ETFClass.TF_CLASS_SOLDIER, TF_WEAPONSLOTS.SECONDARY)

    if (primaryWep)
    {
        if (primaryWep.GetClassname().find("tf_weapon_rocketlauncher") != null)
        {
            this.DestroyProjectile("tf_projectile_rocket")
        }
        else if (primaryWep.GetClassname() == "tf_weapon_particle_cannon")
        {
            this.DestroyProjectile("tf_projectile_energy_ball")
        }
    }

    if (secondaryWep && secondaryWep.GetClassname() == "tf_weapon_raygun")
    {
        this.DestroyProjectile("tf_projectile_energy_ring")
    }
}

::CTFPlayer.DestroyDemoProjectiles <- function()
{
    local primaryWep = this.GetWeaponBySlot(Constants.ETFClass.TF_CLASS_DEMOMAN, TF_WEAPONSLOTS.PRIMARY)
    local secondaryWep = this.GetWeaponBySlot(Constants.ETFClass.TF_CLASS_DEMOMAN, TF_WEAPONSLOTS.SECONDARY)

    if (primaryWep)
    {
        if (primaryWep.GetClassname() == "tf_weapon_grenadelauncher" || primaryWep.GetClassname() == "tf_weapon_cannon")
        {
            this.DestroyProjectile("tf_projectile_pipe")
        }
    }

    if (secondaryWep && secondaryWep.GetClassname() == "tf_weapon_pipebomblauncher")
    {
        this.DestroyProjectile("tf_projectile_pipe_remote")
    }
}

::CTFPlayer.GetWeaponBySlot <- function(playerClass, slot)
{
    if (this.GetPlayerClass() != playerClass) return false

    for (local i = 0; i < GLOBAL_WEAPON_COUNT; i++)
	{
		local weapon = NetProps.GetPropEntityArray(this, "m_hMyWeapons", i)

		if (weapon != null)
		{
			if (weapon.GetSlot() == slot && AllowedWeapons.find(weapon.GetClassname()) != null)
			{
				return weapon
			}
		}
	}
    return false
}

// The default think function for blocking reloads (all non-energy weapons)
::DefaultCancelReloadThink <- function()
{
    if (self.IsValid() && self.ValidateScriptScope())
    {
        local limitAmount = self.GetScriptScope().limitAmount
        if (self.Clip1() == 0 && limitAmount != 0 && self.GetReserveAmmo() != limitAmount)
        {
            local amount = self.GetScriptScope().limitAmount
            self.SetReserveAmmo(amount)
            SetEntityColor(self, 255, 255, 255, 100)

            DebugPrint(self + " is out of ammo! Make translucent and set reserve ammo to " + amount, self.GetOwner())
        }

        /*
        Generally, if you go from a reload state to a new clip of rockets, you are still
        able to fire even when m_flNextAttack == Time() + (0.5 * 100.0). Starting and
        ending a taunt means that m_flNextAttack will be respected, however. So let's
        set it to a more reasonable value to avoid cooldown.
        */
        if (NetProps.GetPropFloat(self.GetOwner(), "m_flNextAttack") > Time() + 30.0)
        {
            NetProps.SetPropFloat(self.GetOwner(), "m_flNextAttack", Time() + 0.5)
        }

        self.BlockReload()
    }

    return 0
}

// For energy weapons (Mangler/Righteous Bison)
::EnergyCancelReloadThink <- function()
{
    if (self.IsValid())
    {
        if (NetProps.GetPropFloat(self, "m_flEnergy") == 0.0)
        {
            SetEntityColor(self, 255, 255, 255, 100)
            NetProps.SetPropFloat(self, "m_flEnergy", -1.0)
            DebugPrint(self + " is out of ammo! Make translucent", self.GetOwner())
        }

        /*
        Charged Cow Mangler shots respect m_flNextAttack, which will be Time() + (0.5 * 100.0)
        due to reload increase attribute. This is to make sure there isn't a 50 second cooldown
        */
        if (NetProps.GetPropFloat(self.GetOwner(), "m_flNextAttack") > Time() + 30.0)
        {
            NetProps.SetPropFloat(self.GetOwner(), "m_flNextAttack", Time() + 0.5)
        }

        self.BlockReload()
    }

    return 0
}

// For unmodified BB (e.g. no jumpnormalizer plugin)
::BeggarsCancelReloadThink <- function()
{
    if (self.IsValid() && self.ValidateScriptScope())
    {
        local amount = self.GetScriptScope().limitAmount
        if ((self.GetReserveAmmo() == 0 && self.Clip1() == 0) || amount == 0)
        {
            if (!self.GetScriptScope().isBlocked)
            {
                DebugPrint(self + " is out of ammo! Make translucent and set reserve ammo to " + (amount == 0 ? 1 : amount), self.GetOwner())
            }

            self.GetScriptScope().isBlocked <- true
            self.SetReserveAmmo(amount == 0 ? 1 : amount)
            self.AddAttribute("reload time increased hidden", 100.0, 0)
            SetEntityColor(self, 255, 255, 255, 100)
        }

        if ("isBlocked" in self.GetScriptScope() && self.GetScriptScope().isBlocked)
        {
            self.BlockReload()
            NetProps.SetPropInt(self, "m_iReloadMode", 0)
        }
    }

    return 0
}


::CTFPlayer.SetClip <- function(weapon, amount, bIsDestroyTrigger)
{
    local classname = weapon.GetClassname()
    local slot = weapon.GetSlot()

    if (!bIsDestroyTrigger)
    {
        if (this.ValidateScriptScope())
        {
            local scope = this.GetScriptScope()
            if (scope.touchedTriggers.find(caller) != null && scope.lastSetClip != Time())
            {
                DebugPrint(caller + " has already been touched, cancel SetClip", this)
                return
            }
        }
    }

    if (this.ValidateScriptScope())
    {
        if (!("lastRegenTick" in this.GetScriptScope()) || this.GetScriptScope().lastRegenTick != Time())
        {
            DebugPrint("call SetClip regenerate", this)
            this.GetScriptScope().lastRegenTick <- Time()
            this.Regenerate(true)

            if (!weapon.IsValid()) // weapon was replaced during Regenerate (loadout change)
            {
                DebugPrint("weapon was replaced during loadout change! Redo SetClip", this)
                local newWeapon = this.GetWeaponBySlot(this.GetPlayerClass(), slot)
                if (newWeapon)
                {
                    this.ValidateScriptScope()
                    this.SetClip(newWeapon, amount, bIsDestroyTrigger)
                }
                return
            }
        }
    }

    /*
    A consequence of increasing reload time attribute is that if you go from a pre-limit
    state to a limited clip state and are in the middle of a reload sequence, the animation
    will freeze in that position (until a projectile is fired or something else interrupts it).
    So if we are reloading OnStartTouch of a limit trigger, let's reset to an idle sequence
    to prevent this.
    */
    weapon.ResetAnimSequence()

    DebugPrint("set clip of " + weapon + " to " + amount + (bIsDestroyTrigger ? " [destroy]" : ""), this)
    switch (classname)
    {
        case "tf_weapon_particle_cannon":
        case "tf_weapon_raygun":
            weapon.AddAttribute("clip size bonus upgrade", (amount == 0 ? 1 : amount) / 4.0, 0) // so that energy bar visually depletes when amount > 4
            weapon.AddAttribute("reload time increased hidden", 100.0, 0) // to make the reload sequence anim visually not play
            SetEntityColor(weapon, 255, 255, 255, 255)

            NetProps.SetPropFloat(weapon, "m_flEnergy", amount * 5.0)

            if (weapon.ValidateScriptScope())
            {
                if (!("CancelReload" in weapon.GetScriptScope()))
                {
                    weapon.GetScriptScope()["CancelReload"] <- EnergyCancelReloadThink
                }
                AddThinkToEnt(weapon, "CancelReload")
            }
            break

        case "tf_weapon_rocketlauncher":
            if (weapon.GetItemDefinitionIndex() == BEGGARS_BAZOOKA_IDX)
            {
                // This is for unmodified Beggar's Bazooka (i.e. no jump normalizer plugin)
                // Would ideally check this via attributes but don't think I can with VScript alone(?)
                if (weapon.GetMaxClip1() == 3)
                {
                    SetEntityColor(weapon, 255, 255, 255, 255)
                    weapon.RemoveAttribute("reload time increased hidden")
                    weapon.SetReserveAmmo(amount == 0 ? 1 : amount)

                    if (weapon.ValidateScriptScope())
                    {
                        if ("isBlocked" in weapon.GetScriptScope() && weapon.GetScriptScope().isBlocked)
                        {
                            NetProps.SetPropFloat(this, "m_flNextAttack", Time())
                        }
                        weapon.GetScriptScope().isBlocked <- false
                        weapon.GetScriptScope().limitAmount <- amount
                        if (!("CancelReload" in weapon.GetScriptScope()))
                        {
                            weapon.GetScriptScope()["CancelReload"] <- BeggarsCancelReloadThink
                        }
                        AddThinkToEnt(weapon, "CancelReload")
                    }
                    break
                }
            }

        default:
            weapon.AddAttribute("reload time increased hidden", 100.0, 0) // to make the reload sequence anim visually not play
            SetEntityColor(weapon, 255, 255, 255, 255)

            NetProps.SetPropInt(weapon, "m_iClip1", amount)
            if (amount == 0)
            {
                weapon.SetReserveAmmo(1) // 0 amount disables weapon; set to 1 so the weapon is not unequipped
                SetEntityColor(weapon, 255, 255, 255, 100)
                DebugPrint(weapon + " is out of ammo! Make translucent and set reserve ammo to 1", weapon.GetOwner())

                /*
                Charging with ammo into a 0 sticky limit trigger will fire a sticky at full charge,
                regardless of whether the clip is subsequently set to 0. Let's reset the charge
                to avoid this bug.
                */
                if (classname == "tf_weapon_pipebomblauncher" && NetProps.GetPropFloatArray(weapon, "PipebombLauncherLocalData", 1) != 0.0)
                {
                    NetProps.SetPropFloatArray(weapon, "PipebombLauncherLocalData", 0.0, 1)
                    StopSoundOn("Weapon_StickyBombLauncher.ChargeUp", weapon)
                }

                if (classname == "tf_weapon_cannon" && NetProps.GetPropFloat(weapon, "m_flDetonateTime") != 0.0)
                {
                    NetProps.SetPropFloat(weapon, "m_flDetonateTime", 0.0)

                    // Kill loose_cannon_sparks and loose_cannon_buildup_smoke3
                    DoEntFire("!self", "DispatchEffect", "ParticleEffectStop", 0.0, weapon, weapon)
                    StopSoundOn("Weapon_LooseCannon.Charge", weapon)
                }
            }
            else weapon.SetReserveAmmo(0)

            if (weapon.ValidateScriptScope())
            {
                weapon.GetScriptScope().limitAmount <- amount
                if (!("CancelReload" in weapon.GetScriptScope()))
                {
                    weapon.GetScriptScope()["CancelReload"] <- DefaultCancelReloadThink
                }
                AddThinkToEnt(weapon, "CancelReload")
            }
    }
}

::CTFPlayer.DestroyAndLimit <- function(slot, amount, destroy)
{
    local playerClass = this.GetPlayerClass()

    /*
    Cancel velocity here because projectiles are destroyed the tick *after* touching the trigger.
    Without it, you could (for example) pre-place stickies and det within that 1 tick window to get
    significantly more height/speed at the start of the jump and it would not count towards the sticky limit amount.

    X-vel/Y-vel are both canceled if either exceeds max walk speed for a class + 30u.
    Z-vel is canceled if it is higher than initial jump speed (277u/s). Aggressive but necessary for anti-cheat.
    */
    if (destroy && this.GetMoveType() != Constants.EMoveType.MOVETYPE_NOCLIP)
    {
        local vel = this.GetAbsVelocity()
        local maxWalkSpeed = NetProps.GetPropFloat(this, "m_flMaxspeed") + 30

        if (abs(vel.x) > maxWalkSpeed || abs(vel.y) > maxWalkSpeed)
        {
            vel.x = 0
            vel.y = 0
        }

        switch (playerClass)
        {
            case Constants.ETFClass.TF_CLASS_SOLDIER:
                this.DestroySollyProjectiles()
                this.SetAbsVelocity(Vector(vel.x, vel.y, vel.z > 277 ? 0 : vel.z))
                break
            case Constants.ETFClass.TF_CLASS_DEMOMAN:
                this.DestroyDemoProjectiles()
                this.SetAbsVelocity(Vector(vel.x, vel.y, vel.z > 277 ? 0 : vel.z))
                break
        }
    }

    local weapon = this.GetWeaponBySlot(playerClass, slot)
    if (weapon)
    {
        if (this.ValidateScriptScope())
        {
            // TODO: might want to make insideZone an array in case
            // mappers end up having intersecting limit triggers for 1 class
            this.GetScriptScope().insideZone <- caller
            this.SetClip(weapon, amount, destroy)

            local touchedTriggers = this.GetScriptScope().touchedTriggers

            if (!destroy)
            {
                if (touchedTriggers.find(caller) == null)
                {
                    touchedTriggers.append(caller)
                }

                this.GetScriptScope().lastSetClip <- Time()
            }
        }
    }

}

// TODO: May want to consider checking if amount is even set (user error)
function RocketLimit(amount, destroy=false)
{
    local player = activator
    if (!player || !player.IsPlayer() || player.GetPlayerClass() != Constants.ETFClass.TF_CLASS_SOLDIER)
    {
        return
    }

    if (amount >= 0 && amount < 255)
    {
        player.DestroyAndLimit(TF_WEAPONSLOTS.PRIMARY, amount, destroy)
    }
}

function ShotgunLimit(amount, destroy=false)
{
    local player = activator
    if (!player || !player.IsPlayer() || player.GetPlayerClass() != Constants.ETFClass.TF_CLASS_SOLDIER)
    {
        return
    }

    if (amount >= 0 && amount < 255)
    {
        player.DestroyAndLimit(TF_WEAPONSLOTS.SECONDARY, amount, destroy)
    }
}

function PipeLimit(amount, destroy = false)
{
    local player = activator
    if (!player || !player.IsPlayer() || player.GetPlayerClass() != Constants.ETFClass.TF_CLASS_DEMOMAN)
    {
        return
    }

    if (amount >= 0 && amount < 255)
    {
        player.DestroyAndLimit(TF_WEAPONSLOTS.PRIMARY, amount, destroy)
    }
}

function StickyLimit(amount, destroy = false)
{
    local player = activator
    if (!player || !player.IsPlayer() || player.GetPlayerClass() != Constants.ETFClass.TF_CLASS_DEMOMAN)
    {
        return
    }

    if (amount >= 0 && amount < 255)
    {
        player.DestroyAndLimit(TF_WEAPONSLOTS.SECONDARY, amount, destroy)
    }
}

function ResetLimit()
{
    local player = activator
    if (!player || !player.IsPlayer())
    {
        return
    }

    ResetPlayerLimit(player, false)
}

function ResetPlayerLimit(player, bRegenerate=true)
{
    for (local slot = TF_WEAPONSLOTS.PRIMARY; slot < TF_WEAPONSLOTS.MELEE; slot++)
    {
        local weapon = player.GetWeaponBySlot(player.GetPlayerClass(), slot)
        if (weapon && weapon.ValidateScriptScope() && "CancelReload" in weapon.GetScriptScope() && weapon.GetScriptThinkFunc() == "CancelReload")
        {
            if (weapon.GetClassname() == "tf_weapon_particle_cannon" || weapon.GetClassname() == "tf_weapon_raygun")
            {
                weapon.RemoveAttribute("clip size bonus upgrade")
                if (NetProps.GetPropFloat(weapon, "m_flEnergy") > 20.0 ||
                    player.ValidateScriptScope() && player.GetScriptScope().lastRegenTick == Time())
                {
                    NetProps.SetPropFloat(weapon, "m_flEnergy", 20.0)
                }
            }

            weapon.RemoveAttribute("reload time increased hidden")
            NetProps.SetPropFloat(weapon.GetOwner(), "m_flNextAttack", Time())
            NetProps.SetPropInt(weapon, "m_iReloadMode", 0)
            SetEntityColor(weapon, 255, 255, 255, 255)

            AddThinkToEnt(weapon, "") // needed for GetScriptThinkFunc
            AddThinkToEnt(weapon, null)

            DebugPrint("reset limit state for " + weapon, player)

            // Reset isBlocked state for unmodified BB
            if (weapon.GetItemDefinitionIndex() == BEGGARS_BAZOOKA_IDX && weapon.GetMaxClip1() == 3)
            {
                if (weapon.ValidateScriptScope()) weapon.GetScriptScope().isBlocked <- false
            }
        }
    }
    if (player.ValidateScriptScope() && bRegenerate)
    {
        DebugPrint("call ResetLimit regenerate", player)
        player.GetScriptScope().lastRegenTick <- Time()
        player.Regenerate(true)
    }
}

function LeaveLimit()
{
    local player = activator
    if (!player || !player.IsPlayer())
    {
        return
    }

    if (player.ValidateScriptScope())
    {
        if ("insideZone" in player.GetScriptScope() && player.GetScriptScope().insideZone == caller)
        {
            DebugPrint("leaving limit trigger " + caller, player)
            player.GetScriptScope().insideZone <- null
        }
    }
}

/*
This event hook is purely for Tempus-compatibility/TF2 with plugins that call CTFPlayer::Regenerate()
For example, if a limit trigger is placed at the start of the bonus (e.g. rocket limit set to 2),
on Tempus restarting (sm_r) to the bonus (with sm_setstart) will regenerate the player.
Because clip setting logic happens OnStartTouch, if a player resets multiple times (never leaving
the limit trigger), on subsequent resets ammo will be set back to 4. The goal of this event hook
is to detect regeneration that occurs outside the context of this script, and when this occurs,
re-run the SetClip logic to avoid CTFPlayer::Regenerate() overriding the desired projectile limit.
*/
function OnGameEvent_post_inventory_application(params)
{
    if ("userid" in params)
    {
        local player = GetPlayerFromUserID(params.userid)

        if (player.ValidateScriptScope())
        {
            if ("lastRegenTick" in player.GetScriptScope() && player.GetScriptScope().lastRegenTick < Time())
            {

                /*
                SDKHook_StartTouchPost fires *before* OnStartTouch outputs, so if a plugin trigger
                (e.g. Tempus start zone) intersects with a "limit" trigger_multiple, and touching
                that plugin start zone regenerates the player, then we ignore that as another source of regen.
                We only care about regen from another source if the player is considered
                inside the "limit" trigger_multiple (post-trigger_multiple output function(s))
                e.g. sm_r, sm_b, etc.
                */
                DebugPrint("obtained regen from another source (e.g. plugin or func_regenerate)", player)

                if ("insideZone" in player.GetScriptScope() && player.GetScriptScope().insideZone != null)
                {
                    player.GetScriptScope().lastRegenTick <- Time()
                    local numElements = EntityOutputs.GetNumElements(player.GetScriptScope().insideZone, "OnStartTouch")

                    if (numElements > 0)
                    {
                        local outputs = {}

                        for (local i = 0; i < numElements; i++)
                        {
                            EntityOutputs.GetOutputTable(player.GetScriptScope().insideZone, "OnStartTouch", outputs, i)

                            // Do not call any output functions that do not come from this script
                            for (local i = 0; i < LimitFunctions.len(); i++)
                            {
                                if (outputs.parameter.find(LimitFunctions[i]) != null)
                                {
                                    DoEntFire(outputs.target, outputs.input, outputs.parameter, outputs.delay, player, player.GetScriptScope().insideZone)
                                    break
                                }
                            }
                        }
                    }
                }
            }
            ResetPlayerLimit(player, false) // this fires before the outputs
        }
    }
}

function OnGameEvent_teamplay_round_start(params)
{
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        local player = PlayerInstanceFromIndex(i)
        if (player == null) continue

        ResetPlayerLimit(player)
    }
}

function OnGameEvent_player_death(params)
{
    if ("userid" in params)
    {
        local player = GetPlayerFromUserID(params.userid)
        DebugPrint("died! Reset weapon limit states", player)

        ResetPlayerLimit(player, false)
    }
}

/*
====================================================================================================
3. FUNC_REGENERATE VSCRIPT RE-IMPLEMENTATION (by ficool2, modified)

Description:    A VScript re-implementation of func_regenerate trigger, made by ficool2, originally from:
                https://cdn.discordapp.com/attachments/1039243316920844428/1063959178030358538/regenerate.nut
                Filtering a normal func_regenerate trigger is not possible, so this re-implementation can be
                used for that purpose (e.g. covering the entire map in a trigger_multiple for constant demoman regen,
                but limiting regen for certain soldier jumps)

                Modifications to ficool2's script include:
                1. Executing within the scope of the logic_script entity (as the rest of this script does)
                2. Including a new argument for filtering by class so you don't have to create a separate
                filter_tf_class entity, mainly for convenience.

Demonstration: https://youtu.be/N8VZVMei1zc?t=177

Usage:
====================================================================================================
*/

const RegenerateSound = "Regenerate.Touch"
const RegenerateDelay = 3.0

const GR_STATE_STALEMATE = 7
const GR_STATE_TEAM_WIN = 5

::gamerules <- Entities.FindByClassname(null, "tf_gamerules")

::FuncRegenerate <- function(player)
{
	local time = Time()
	if (player.GetNextRegenTime() > time)
		return

	if (player.InCond(Constants.ETFCond.TF_COND_TAUNTING))
		return

	local scope = self.GetScriptScope()
	local state = NetProps.GetPropInt(gamerules, "m_iRoundState")
	if (state == GR_STATE_STALEMATE)
		return

	if (state != GR_STATE_TEAM_WIN)
	{
		local team = self.GetTeam()
		if (team && (player.GetTeam() != team))
			return
	}
	else
	{
		if (NetProps.GetPropInt(gamerules, "m_iWinningTeam") != player.GetTeam())
			return
	}

    if (player.ValidateScriptScope())
    {
        player.GetScriptScope().lastRegenTick <- Time()
    }

    DebugPrint("regenerated by FuncRegen " + self, player)
	player.Regenerate(true)
	player.SetNextRegenTime(time + RegenerateDelay)

	EmitSoundOnClient("Regenerate.Touch", player)

	if (scope.associatedModel != null && scope.associatedModel.IsValid())
	{
		EntFireByHandle(associatedModel, "SetAnimation", "open", 0.0, self, self)
		EntFireByHandle(associatedModel, "SetAnimation", "close", RegenerateDelay - 1.0, self, self)
	}
}

function FuncRegenStart(playerClass = any)
{
    local player = activator
	local trigger = caller

    if (!player || !player.IsPlayer())
    {
        return
    }

    if (playerClass != any && player.GetPlayerClass() != playerClass)
    {
        return
    }

	if (trigger.ValidateScriptScope())
	{
		local touchers = trigger.GetScriptScope().touchers
		if (touchers.find(player) != null)
			return
		touchers.append(player)
	}
}

function FuncRegenEnd()
{
	local player = activator
	local trigger = caller

    if (!player || !player.IsPlayer())
    {
        return
    }

	local touchers = trigger.GetScriptScope().touchers
	local idx = touchers.find(player)
	if (idx != null)
		touchers.remove(idx)
}

function FuncRegenThink()
{
	local touchers = self.GetScriptScope().touchers
	local num = touchers.len()
	for (local i = num-1; i >= 0; i--)
	{
		local player = touchers[i]
		if (player == null || !player.IsValid())
		{
			touchers.remove(i)
			continue
		}
		FuncRegenerate(player)
	}

	return 0.1
}

function Precache()
{
    PrecacheScriptSound("Weapon_StickyBombLauncher.ChargeUp")
    PrecacheScriptSound("Weapon_LooseCannon.Charge")
	PrecacheScriptSound("Regenerate.Touch")
}

function FuncRegenerateInit(trigger)
{
    DebugPrint("initializing FuncRegen on " + trigger)
    if (trigger.ValidateScriptScope())
    {
        trigger.GetScriptScope().touchers <- []
        trigger.GetScriptScope().associatedModel <- null
        trigger.GetScriptScope()["FuncRegenThink"] <- FuncRegenThink

        local associatedModelName = NetProps.GetPropString(trigger, "m_iszDamageFilterName")
        local associatedModel = null

        if ((associatedModelName != null) && (associatedModelName.len() > 0))
        {
            associatedModel = Entities.FindByName(null, associatedModelName)
            trigger.GetScriptScope().associatedModel = associatedModel
        }

        AddThinkToEnt(trigger, "FuncRegenThink")
    }
}

// Post-spawn of the logic_script entity
function OnPostSpawn()
{
	local trigger = null
	while (trigger = Entities.FindByClassname(trigger, "trigger_multiple"))
	{
		local numElements = EntityOutputs.GetNumElements(trigger, "OnStartTouch")

		if (numElements > 0)
		{
            for (local i = 0; i < numElements; i++)
            {
                local outputs = {}
                EntityOutputs.GetOutputTable(trigger, "OnStartTouch", outputs, i)
                if (outputs.input == "RunScriptCode" && outputs.parameter.find("FuncRegenStart(") != null)
                {
                    FuncRegenerateInit(trigger)
                }
            }
		}
	}
}

/*
====================================================================================================
Useful wrapper functions

Description:    Functions that may be useful as standalone functions. For example, anti-telesync
                by using a combination of DestroySoldierProjectiles() and KillVelocity()
                on your level's fail trigger_teleport.
====================================================================================================
*/

/*
Keep in mind rockets are removed the server frame *after* this output runs.
Depending on your situation, you may want to add KillVelocity() to the trigger
that calls this function to prevent player knockback during that small
window of time.
*/
function DestroySoldierProjectiles()
{
    local player = activator
    if (!player || !player.IsPlayer())
    {
        return
    }

    player.DestroySollyProjectiles()
}

/*
Keep in mind pipes/stickies are removed the server frame *after* this output runs.
Depending on your situation, you may want to add KillVelocity() to the trigger
that calls this function to prevent players from detonating during that small
window of time.
*/
function DestroyDemomanProjectiles()
{
    local player = activator
    if (!player || !player.IsPlayer())
    {
        return
    }

    player.DestroyDemoProjectiles()
}

function KillVelocity(playerClass = any)
{
    local player = activator
    if (!player || !player.IsPlayer())
    {
        return
    }

    if (playerClass != any && player.GetPlayerClass() != playerClass)
    {
        return
    }

    player.SetAbsVelocity(Vector(0, 0, 0))
}

__CollectGameEventCallbacks(this)
