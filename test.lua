-- PlayerScripts/GameClass/EnemyClass.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Common = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local ResourceManager = require(Common:WaitForChild("ResourceManager"))
local EnemyUtilities = require(Common:WaitForChild("EnemyUtilities"))

local EnemyClass = {}
EnemyClass.__index = EnemyClass

--[[
Cấu trúc initData:
[1] = hash,
[2] = randomHash,
[3] = enemyType,
[4] = stealthFlag,
[5] = stoppedFlag,
[...]
[24] = uniqueId
--]]

function EnemyClass.new(initData)
    local self = setmetatable({}, EnemyClass)
    
    -- Core Identification
    self._id = initData[24] or game:GetService("HttpService"):GenerateGUID(false)
    self._hash = assert(initData[1], "Missing enemy hash")
    self._type = assert(initData[3], "Missing enemy type")
    
    -- Configuration
    self._config = ResourceManager.GetEnemyConfig(self._type)
    assert(self._config, "Config not found for "..self._type)
    
    -- Combat Systems
    self.Health = self:InitializeHealthSystem(initData)
    self.Bounty = self:InitializeBountySystem(initData)
    self.Movement = self:InitializeMovementSystem(initData)
    self.Attacks = self:InitializeAttackSystem()
    
    -- State Management
    self._states = {
        Alive = true,
        Stunned = initData[13] or false,
        Stealthed = initData[4] or false,
        Invulnerable = initData[25] or false,
        AirUnit = self._config.AirUnit
    }
    
    -- Visual Representation
    self._character = self:InitializeVisuals(initData)
    
    return self
end

function EnemyClass:InitializeHealthSystem(initData)
    return {
        Current = initData[9] or self._config.BaseHealth,
        Max = initData[10] or self._config.BaseHealth,
        Armor = initData[14] or self._config.BaseArmor,
        Shield = initData[15] or 0,
        
        GetPercent = function()
            return math.floor((self.Health.Current / self.Health.Max) * 100)
        end,
        
        TakeDamage = function(dmg, damageType)
            if not self._states.Alive or self._states.Invulnerable then return end
            
            local reduction = self._config.DamageReductionTable[damageType] or 1.0
            local finalDamage = dmg * reduction
            
            self.Health.Current = math.max(0, self.Health.Current - finalDamage)
            
            if self.Health.Current <= 0 then
                self:Die()
            end
        end
    }
end

function EnemyClass:InitializeBountySystem(initData)
    local base = self._config.BaseBounty or 0
    local multiplier = initData[23] or 1
    
    return {
        Value = base * multiplier,
        Display = function()
            -- Hiển thị bounty khi enemy chết
        end
    }
end

function EnemyClass:InitializeMovementSystem(initData)
    return {
        Speed = self._config.MoveSpeed * (initData[16] or 1),
        Path = initData[8],
        Position = initData[8] and initData[8][1] or Vector3.new(),
        
        Update = function(dt)
            -- Logic di chuyển
        end
    }
end

function EnemyClass:InitializeAttackSystem()
    if not self._config.HasAttack then return nil end
    
    local attacks = {}
    
    for i, config in ipairs(self._config.AttackData) do
        attacks[i] = {
            Type = config.IsProjectile and "PROJECTILE" or "MELEE",
            Range = config.Range,
            Damage = config.Damage,
            Cooldown = config.ReloadTime,
            LastUsed = 0
        }
    end
    
    return attacks
end

function EnemyClass:InitializeVisuals(initData)
    -- Tạo model enemy trong workspace
    local model = Instance.new("Model")
    model.Name = self._type
    model.Parent = workspace.Enemies
    
    -- Thêm các thành phần vật lý
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Anchored = false
    root.CanCollide = true
    root.Parent = model
    
    -- ... (Thêm các part khác)
    
    return {
        Model = model,
        Destroy = function()
            model:Destroy()
        end
    }
end

-- Core Methods
function EnemyClass:Die()
    if not self._states.Alive then return end
    
    self._states.Alive = false
    self.Bounty.Display()
    self._character.Destroy()
    
    -- Gửi sự kiện đến server
    game:GetService("ReplicatedStorage").Remotes.EnemyDied:FireServer(self._hash)
end

function EnemyClass:Update(dt)
    if not self._states.Alive then return end
    
    self.Movement.Update(dt)
    
    -- Cập nhật thời gian hồi chiêu
    if self.Attacks then
        for _, attack in pairs(self.Attacks) do
            attack.LastUsed = attack.LastUsed + dt
        end
    end
end

-- API Methods
function EnemyClass:GetInfo()
    return {
        ID = self._id,
        Type = self._type,
        Health = self.Health.Current,
        MaxHealth = self.Health.Max,
        HealthPercent = self.Health.GetPercent(),
        Bounty = self.Bounty.Value,
        Position = self.Movement.Position,
        States = table.clone(self._states)
    }
end

return EnemyClass
