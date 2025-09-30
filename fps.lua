local REMOVAL_LEVEL = 2
print = function() end; warn = function() end

task.wait(1)
pcall(function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local PlayerScripts = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")
    local GameClass = PlayerScripts.Client:WaitForChild("GameClass")
    local NetworkingHandler = require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common"):WaitForChild("NetworkingHandler"))
    local TowerClass = require(GameClass:WaitForChild("TowerClass"))
    local EnemyClass = require(GameClass:WaitForChild("EnemyClass"))
    local PathEntityClass = require(GameClass:WaitForChild("PathEntityClass"))
    local ProjectileHandler = require(GameClass:WaitForChild("ProjectileHandler"))

    local analyticsEvent = ReplicatedStorage:WaitForChild("GameAnalyticsError", 60)
    if analyticsEvent then local original_mt = getmetatable(analyticsEvent); local hook_mt = {__index = original_mt}; function hook_mt:__namecall(...) if getnamecallmethod() == "FireServer" then return end; return original_mt.__namecall(...) end; setmetatable(analyticsEvent, hook_mt) end

    local newBurnEvent = NetworkingHandler:GetEvent("NewBurnEffect"); if newBurnEvent then newBurnEvent.AttachCallback = function() end end
    local removeBurnEvent = NetworkingHandler:GetEvent("RemoveBurnEffect"); if removeBurnEvent then removeBurnEvent.AttachCallback = function() end end
    
    local originalNewProjectile = ProjectileHandler.NewProjectile
    ProjectileHandler.NewProjectile = function(...) local realProjectiles = originalNewProjectile(...); if realProjectiles then for _, proj in ipairs(realProjectiles) do task.spawn(function() if not proj or not proj.Model then return end; local function stripFX(instance) if instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") or instance:IsA("Light") then instance.Enabled = false end end; for _, d in ipairs(proj.Model:GetDescendants()) do stripFX(d) end; proj.Model.DescendantAdded:Connect(stripFX) end) end end; return realProjectiles end

    require(GameClass:WaitForChild("VisualEffectHandler")).NewVisualEffect = function() return end
    require(GameClass:WaitForChild("VisualSequenceHandler")).StartNewSequence = function() return end

    local function disableTowerFX(instance) if not instance or not instance.Parent then return end; if string.find(instance.Name, "Ring", 1, true) or (instance.Parent and string.find(instance.Parent.Name, "Ring", 1, true)) then return end; local cn = instance.ClassName; if cn == "ParticleEmitter" or cn == "Beam" or cn == "Trail" or cn == "PointLight" or cn == "SpotLight" then instance.Enabled = false; if instance:IsA("Light") then instance.Brightness = 0 end end end
    local function processTower(tower) if tower and tower.Character and tower.Character.CharacterModel then local charModel = tower.Character.CharacterModel; tower.Character.Attacked = function() return end; tower.Character.RunDefaultBeamEffects = function() return end; for _, v in ipairs(charModel:GetDescendants()) do disableTowerFX(v) end; charModel.DescendantAdded:Connect(disableTowerFX); if REMOVAL_LEVEL >= 2 then local oldSetAnim = tower.SetAnimationState; tower.SetAnimationState = function(self, state, force) if string.find(tostring(state), "Attack", 1, true) then return end; pcall(oldSetAnim, self, state, force) end end end end
    if TowerClass.GetTowers then for _, t in pairs(TowerClass.GetTowers()) do processTower(t) end end
    local oldNewTower = TowerClass.New; TowerClass.New = function(...) local t = oldNewTower(...); if t then task.spawn(processTower, t) end; return t end

    local function disableGenericFX(instance) local cn = instance.ClassName; if cn == "ParticleEmitter" or cn == "Beam" or cn == "Trail" or cn == "PointLight" or cn == "SpotLight" then instance.Enabled = false; if instance:IsA("Light") then instance.Brightness = 0 end end end
    local function processGenericEntity(entity) if entity and entity.Character and entity.Character.CharacterModel then local charModel = entity.Character.CharacterModel; if entity._Attacked then entity._Attacked = function() return end end; if entity.Character.Attacked then entity.Character.Attacked = function() return end end; if entity.Character.RunDefaultBeamEffects then entity.Character.RunDefaultBeamEffects = function() return end end; for _, v in ipairs(charModel:GetDescendants()) do disableGenericFX(v) end; charModel.DescendantAdded:Connect(disableGenericFX); if REMOVAL_LEVEL >= 2 and entity.SetAnimationState then local oldSetAnim = entity.SetAnimationState; entity.SetAnimationState = function(self, state, force) if string.find(tostring(state), "Attack", 1, true) then return end; pcall(oldSetAnim, self, state, force) end end end end

    if EnemyClass.GetEnemies then for _, e in pairs(EnemyClass.GetEnemies()) do processGenericEntity(e) end end
    local oldNewEnemy = EnemyClass.New; EnemyClass.New = function(...) local e = oldNewEnemy(...); if e then task.spawn(processGenericEntity, e) end; return e end

    if PathEntityClass.GetPathEntities then for _, p in pairs(PathEntityClass.GetPathEntities()) do processGenericEntity(p) end end
    local oldNewPathEntity = PathEntityClass.New; PathEntityClass.New = function(...) local p = oldNewPathEntity(...); if p then task.spawn(processGenericEntity, p) end; return p end
end)