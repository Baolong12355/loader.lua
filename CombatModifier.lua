-- File: CombatModifier.lua (Để tải lên GitHub)
local Patcher = {}

function Patcher:Apply(config)
    local settings = config or {}
    local shotInterval = settings.shotInterval
    local reloadTime = settings.reloadTime
    local firerateMultiplier = settings.firerateMultiplier
    local spreadDegrees = settings.spreadDegrees

    -- Chỉ áp dụng nếu giá trị là một số (để tránh lỗi)
    if type(shotInterval) ~= "number" then shotInterval = 0 end
    if type(reloadTime) ~= "number" then reloadTime = 0 end
    if type(firerateMultiplier) ~= "number" then firerateMultiplier = 0 end
    if type(spreadDegrees) ~= "number" then spreadDegrees = 0 end

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
