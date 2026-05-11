local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local abilityEffects = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("abilityEffects")
local Effects = ReplicatedStorage:WaitForChild("Effects")

local animationCache = require(ReplicatedStorage.modules.Server.animationCaller)
local Calculate = require(ReplicatedStorage.modules.CalculationModule)
local soundControllerModule = require(ReplicatedStorage.modules.SoundModule)

local cooldownByPlayer = {}

local Fire = {}
Fire.__index = Fire

export type ClassType = typeof(setmetatable({} :: {
	player: Player,
	ability: any,
	character: Model,
	damage: number,
	bodyPart: string,
	sustainTime: number,
	range: number,
	cooldown: number,
	manaCost: number,
	vfxName: string,
	impactVfxName: string,
	soundEffect: string,
	animation: string,
	target: any,
	_hitChars: {[Model]: boolean},
}, Fire))

function Fire.new(player: Player, ability, target): ClassType
	local self = setmetatable({}, Fire)

	self.player = player
	self.ability = ability
	self.character = player.Character
	self.target = target

	self.damage = ability.Damage or 0
	self.bodyPart = ability.BodyPart or "Head"
	self.sustainTime = ability.SustainTime or 5
	self.range = ability.Range or 10
	self.cooldown = ability.Cooldown or 10
	self.manaCost = ability.ManaCost or 10

	self.vfxName = (ability.Effects and ability.Effects.Effect) or "Conjure"
	self.impactVfxName = (ability.Effects and ability.Effects.Impact) or "Conjure"
	self.soundEffect = ability.SoundEffect or ""
	self.animation = ability.Animation or ""

	-- Tracks who's been hit so that we can loop through and damage them all since this is a range based spell
	self._hitChars = {}

	self:activate()
	return self
end

function Fire:isValidCharacter()
	return self.player ~= nil and self.player.Character ~= nil
end

function Fire:hasMana()
	if not self:isValidCharacter() then
		return false
	end

	local stats = self.player:FindFirstChild("ClassStats")
	if not stats then
		return false
	end

	local attributes = stats:FindFirstChild("Attributes")
	if not attributes then
		return false
	end

	local mana = attributes:GetAttribute("Mana")
	if not mana then
		return false
	end

	if self.manaCost > mana then
		return false
	end

	attributes:SetAttribute("Mana", mana - self.manaCost)
	return true
end

function Fire:playAnimation()
	if self.animation and self.character then
		animationCache:Get(self.player):PlayCustom(self.animation)
	end
end

function Fire:spawnVfx(name, cframe)
	local template = Effects:FindFirstChild(name)
	if not template then
		return nil
	end

	local clone = template:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.CFrame = cframe
	clone.Transparency = 1
	clone.Parent = workspace

	-- Emit particles
	for _, child in clone:GetChildren() do
		if child:IsA("Attachment") then
			for _, emitter in child:GetChildren() do
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(5)
				end
			end
		end
	end

	return clone
end

-- Outer impact ring 
function Fire:impactRing(position)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 82, 48)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(0.35), {
		Size = Vector3.new(0.2, self.range * 6, self.range * 6),
		Transparency = 1
	}):Play()

	Debris:AddItem(ring, 0.4)
end

-- Inner impact ring 
function Fire:snapRing(position)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(209, 10, 10)
	ring.Transparency = 0.4
	ring.Size = Vector3.new(0.2, self.range * 2, self.range * 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(0.25), {
		Size = Vector3.new(0.2, self.range * 2.5, self.range * 2.5)
	}):Play()

	TweenService:Create(ring, TweenInfo.new(0.4), {
		Transparency = 1
	}):Play()

	Debris:AddItem(ring, 0.5)
end

function Fire:applyDamage(origin)
	local enemies = workspace:FindFirstChild("Enemies")
	if not enemies then return end

	for _, model in enemies:GetChildren() do
		if model:IsA("Model") and model ~= self.character then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if not hum or not hrp then continue end

			local dist = (hrp.Position - origin.Position).Magnitude

			if dist <= self.range and not self._hitChars[model] then
				self._hitChars[model] = true

				local calc = Calculate.new(self.player, model)
				local crit = calc:ApplyCritChance()

				local finalDamage = calc:ApplyDamage(self.damage, "Fire", crit, false)

				-- Knockback away from the hit spot 
				local dir = (hrp.Position - origin.Position)
				if dir.Magnitude == 0 then
					dir = Vector3.new(0, 0, 1)
				end
				dir = dir.Unit

				local att = hrp:FindFirstChild("KnockbackAttachment")
				if not att then
					att = Instance.new("Attachment")
					att.Name = "KnockbackAttachment"
					att.Parent = hrp
				end

				local lv = Instance.new("LinearVelocity")
				lv.Attachment0 = att
				lv.VectorVelocity = dir * 60 + Vector3.new(0, 50, 0)
				lv.MaxForce = math.huge
				lv.Parent = hrp

				Debris:AddItem(lv, 0.25)
			end
		end
	end
end

function Fire:getTargetCFrame()
	if typeof(self.target) == "Instance" and self.target:IsA("Model") then
		local root = self.target:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		return root.CFrame
	elseif typeof(self.target) == "Vector3" then
		return CFrame.new(self.target)
	end
	return nil
end

function Fire:startCooldown()
	cooldownByPlayer[self.player] = true
	task.delay(self.cooldown, function()
		cooldownByPlayer[self.player] = false
	end)
end

function Fire:activate()
	if cooldownByPlayer[self.player] then return end
	if not self:hasMana() then return end
	if not self:isValidCharacter() then return end

	local spawnPart = self.character:FindFirstChild(self.bodyPart)
	if not spawnPart then return end

	self:playAnimation()

	local targetCFrame = self:getTargetCFrame()
	if not targetCFrame then return end

	local projectile = self:spawnVfx(self.vfxName, spawnPart.CFrame)
	if not projectile then return end

	abilityEffects:FireClient(self.player, "FireballCast")

	local tween = TweenService:Create(projectile, TweenInfo.new(0.8), {
		CFrame = targetCFrame
	})

	tween:Play()
	tween.Completed:Wait()
	projectile:Destroy()

	local impact = self:spawnVfx(self.impactVfxName, targetCFrame)
	if impact then
		soundControllerModule:Play(self.soundEffect, impact)
		Debris:AddItem(impact, self.sustainTime)

		local pos = targetCFrame.Position
		self:snapRing(pos)
		self:impactRing(pos)
	end

	abilityEffects:FireClient(self.player, "ExplosionHit")

	-- Sustained damage window players take damage for as long as the current t is less than sustainTime
	task.spawn(function()
		local t = 0
		while t < self.sustainTime do
			self:applyDamage(targetCFrame)
			task.wait(0.5)
			t += 0.5
		end
	end)

	self:startCooldown()
end

return Fire
