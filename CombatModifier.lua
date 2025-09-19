local Patcher = {}

function Patcher:Apply()
    -- Đọc các giá trị trực tiếp từ biến toàn cục (_G)
    -- Nếu biến không tồn tại, nó sẽ dùng một giá trị mặc định an toàn
    local shotInterval = _G.CombatMod_ShotInterval or 0
    local reloadTime = _G.CombatMod_ReloadTime or 0
    local firerateMultiplier = _G.CombatMod_FirerateMultiplier or 0.001
    local spreadDegrees = _G.CombatMod_SpreadDegrees or 0

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