// Button script for jump_regen by Kingstripes
// Mostly multiplayer friendly but would also need filtered tele at final door

const BUTTON_AMOUNT = 7

::CTFPlayer.AddButton <- function(button)
{
    if (ValidateScriptScope())
    {
        local scope = GetScriptScope()
        if (!("buttons" in scope))
        {
            scope.buttons <- []
        }

        if (scope.buttons.find(button) == null)
        {
            scope.buttons.append(button)
            if (scope.buttons.len() == 1)
            {
                EntFire("limitregensolly3_door1", "Open", null)
                EntFire("limitregensolly3_door1", "Close", null, 3.5)
            }
            else if (scope.buttons.len() == 7)
            {
                EntFire("limitregensolly3_door2", "Open", null)
                EntFire("limitregensolly3_door2", "Close", null, 3.5)
                EntFire("limitregensolly3_spotlight", "TurnOn", null)
                EntFire("limitregensolly3_spotlight", "TurnOff", null, NetProps.GetPropFloat(caller, "m_flWait") + 1.5)           
            }
        }
    }
}

::CTFPlayer.ResetButtons <- function()
{
    if (ValidateScriptScope())
    {
        local scope = GetScriptScope()
        if ("buttons" in scope)
        {
            scope.buttons.clear()
        }

    }    
}

function OnShoot()
{
    EntFire("!self", "PressIn", null)
    EntFire("!self", "Alpha", 190)
    EntFire("!self", "Alpha", 255, NetProps.GetPropFloat(caller, "m_flWait") + 0.1)

    activator.AddButton(caller)
}

function ResetButtons()
{
    activator.ResetButtons()
}
