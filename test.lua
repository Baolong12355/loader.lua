-- Advanced Combat System with Rayfield GUI and Fast Tweening
-- Generated with enhanced combat mechanics and smooth movement

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Player and Character
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")

-- Remote Function
local FireInput = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.MoveInputService.RF.FireInput

-- Game Services - Using the actual game modules
local CombatService = game:GetService("ReplicatedStorage").ReplicatedRoot.Services.CombatService.Client
local ClientCooldown = require(CombatService.ClientCooldown)
local ClientRagdoll = require(CombatService.ClientRagdoll)
local ClientStun = require(CombatService.ClientStun)

-- Loading Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Tween Configuration for near-instant movement
local TWEEN_INFO = TweenInfo.new(
    0,  -- Very fast duration (0.05 seconds)
    Enum.EasingStyle.Linear,  -- Linear for consistent speed
    Enum.EasingDirection.InOut,
    0,  -- No repeat
    false,  -- Don't reverse
    0   -- No delay
)

-- Combat System Variables
local CombatSystem = {
    enabled = false,
    currentTarget = nil,
    waitPositionCultists = Vector3.new(10291.4921875, 6204.5986328125, -255.45745849609375),
    waitPositionCursed = Vector3.new(-240.7166290283203, 233.30340576171875, 417.1275939941406),
    targetFolders = {"Assailant", "Conjurer", "Roppongi Curse", "Mantis Curse", "Jujutsu Sorcerer", "Flyhead"},
    selectedSkills = {},
    selectedPlusSkills = {}, -- For skills with +
    farmMode = "Cultists", -- "Cultists" or "Cursed"
    isInCombat = false,
    lastM1Time = 0,
    lastM2Time = 0,
    skillCooldowns = {},
    heartbeatConnection = nil,
    currentTween = nil,
    tweenSpeed = 0.05 -- Adjustable tween speed (lower = faster)
}

-- Status Check Functions using game modules
local function getCooldown(character, skillName)
    if not character then return nil end
    
    -- Try using ClientCooldown service
    local success, result = pcall(function()
        return ClientCooldown.