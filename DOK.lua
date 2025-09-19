-- File: CombatModifier.lua
local Patcher = {}

function Patcher:Apply(config)
    local settings = config or {}
    local shotInterval = settings.shotInterval
    local reloadTime = settings.reloadTime
    local firerateMultiplier = settings.firerateMultiplier
    local spreadDegrees = settings.spreadDegrees

    for _, mod in ipairs(getloadedmodules()) do
        if mod.Name == "FirstPersonAttackHandlerClass" then
            local ModuleTable = require(mod)
            if ModuleTable and ModuleTable.New then
                local oldNew = ModuleTable.New
                ModuleTable.New = function(...)
                    local obj = oldNew(...)
                    obj.DefaultShotInterval = shotInterval
                    obj.ReloadTime = reloadTime
                    obj.CurrentFirerateMultiplier = firerateMultiplier
                    obj.DefaultSpreadDegrees = spreadDegrees
                    return obj
                end
            end
        elseif mod.Name == "FirstPersonCameraHandler" then
            local cameraMod = require(mod)
            if cameraMod then
                if cameraMod.CameraShake then cameraMod.CameraShake = function() end end
                if cameraMod.ApplyRecoil then cameraMod.ApplyRecoil = function() end end
            end
        end
    end
end

return Patcher