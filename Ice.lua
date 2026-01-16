-- Services

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- folders

local Effects = ReplicatedStorage:WaitForChild("Effects")

-- modules

local soundControllerModule = require(ReplicatedStorage:WaitForChild("modules").SoundModule)
local animationControllerModule = require(ReplicatedStorage:WaitForChild("modules").AnimationModule)

-- dict

local Cooldown = {}


local Ice = {}
Ice.__index = Ice


function Ice.new(player, ability, target)
	local self = setmetatable({}, Ice)

	self.player = player
	self.ability = ability
	self.character = player.Character
	self.damage = ability.Damage
	self.bodyPart = ability.BodyPart or "Head"
	self.sustainTime = ability.SustainTime or 5
	self.cooldown = ability.Cooldown or 10
	self.manaCost = ability.ManaCost or 10
	self.vfxName = (ability.Effects and ability.Effects.Effect) or "Conjure"
	self.impactVfxName = (ability.Effects and ability.Effects.Impact) or "Conjure"
	self.soundEffect = ability.SoundEffect or ""
	self.animation = ability.Animation
	self.target = target

	self.slowPercent = ability.SlowPercent or 0.5
	self.slowAttackPercent = ability.SlowAttackPercent or 0.5
	self.ElementalForce = ability.ElementalForce or 1
	self.FreezeChance = ability.FreezeChance or 100
	self.Brittle = ability.Brittle or 0.4

	print("Ice ability was called.")

	self:Activate()
	return self
end

function Ice:_checkPlayer()
	if not self.player then
		warn("(Conjure) Player is nil!")
		return false
	end
	if not self.player.Character then
		warn("(Conjure) Player has no character!")
		return false
	end
	return true
end


function Ice:_checkMana()
	if not self:_checkPlayer() then return false end

	local ClassAttributes = self.player:WaitForChild("ClassStats")
	if not ClassAttributes then return end

	local Attributes = ClassAttributes:FindFirstChild("Attributes")
	if not Attributes then return false end

	local mana = Attributes:GetAttribute("Mana")
	if not mana then return false end

	if self.manaCost > mana then
		warn("Not enough mana for player: " .. self.player.Name)
		return false
	end

	local proceeds = mana - self.manaCost
	Attributes:SetAttribute("Mana", proceeds)
	print(proceeds)
	
	return true
end

function Ice:_playAnimation()
	if self.animation and self.character then
		animationControllerModule:PlayCustom(self.character, self.animation)
	else
		print("Found no animation.")		
	end
end

function Ice:_spawnVfx(vfxName, cframe)
	local vfxTemplate = Effects:FindFirstChild(vfxName)
	if not vfxTemplate then
		warn("Couldn't find VFX: " .. tostring(vfxName))
		return nil
	end

	local clone = vfxTemplate:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.CFrame = cframe
	clone.Transparency = 1
	clone.Parent = workspace

	for _, attachment in pairs(clone:GetChildren()) do
		if attachment:IsA("Attachment") then
			for _, emitter in pairs(attachment:GetChildren()) do
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(5)
				end
			end
		end
	end

	return clone
end

function Ice:_applySlow(target)
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then return end
	local roll = math.random(1, 100)


	if self.target:IsA("Model") 
		and self.target:FindFirstChildOfClass("Humanoid") 
		and self.target:FindFirstChild("HumanoidRootPart") 
		and self.target ~= self.character then

		if self.sustainTime > 0 then
			local humanoid = self.target:FindFirstChildOfClass("Humanoid")
			local walkSpeed = humanoid.WalkSpeed

			walkSpeed = walkSpeed * (1 - self.slowPercent)

			if roll <= self.FreezeChance then
				local humanoid = self.target:FindFirstChildOfClass("Humanoid")
				local root = self.target:FindFirstChild("HumanoidRootPart")
				if humanoid and root then
					root.Anchored = true
					print(self.target.Name .. " is frozen!")
					for i, bp in (self.target:GetChildren()) do
						if bp:IsA("MeshPart") or bp:IsA("BasePart") then
							task.delay((i - 1) * 0.1, function() -- 0.1s stagger between each part
								local tween = TweenService:Create(
									bp,
									TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
									{ Color = Color3.fromRGB(162, 212, 255) }
								)
								tween:Play()
							end)
						end
					end
				end
			end
			
			task.delay(self.sustainTime, function()
				local root = self.target:FindFirstChild("HumanoidRootPart")
				if root then
					root.Anchored = false
					for i, bp in (self.target:GetChildren()) do
						if bp:IsA("MeshPart") or bp:IsA("BasePart") then
							task.delay((i - 1) * 0.1, function() -- 0.1s stagger between each part (decrease to 0.05??)
								local tween = TweenService:Create(
									bp,
									TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
									{ Color = Color3.fromRGB(255, 255, 255) }
								)
								tween:Play()
							end)
						end
					end
				end
			end) 
		end
	end
end


function Ice:_applyDamage() -- Don't call this outside of this module that's what the _ is for.
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then return end

	if self.target:IsA("Model") 
		and self.target:FindFirstChildOfClass("Humanoid") 
		and self.target:FindFirstChild("HumanoidRootPart") 
		and self.target ~= self.character then
		local humanoid = self.target:FindFirstChildOfClass("Humanoid")

		if self.sustainTime > 0 and humanoid.Health > 0 then			
			humanoid:TakeDamage(self.damage)
		end
	end
end

function Ice:Activate() 
	if not self:_checkMana() then return end
	if Cooldown[self.player] then
		return
	end
	if not self.character then return end

	local spawnPart = self.character:FindFirstChild(self.bodyPart)
	if not spawnPart then
		warn("Couldn't find spawn part: " .. self.bodyPart)
		return
	end

	self:_playAnimation()
	local startCFrame = spawnPart.CFrame
	local targetCFrame

	if typeof(self.target) == "Instance" and self.target:IsA("Model") then
		local root = self.target:FindFirstChild("HumanoidRootPart")
		if not root then return end
		targetCFrame = root.CFrame
	else
		warn("Invalid target for Conjure")
		return
	end

	local conjureClone = self:_spawnVfx(self.vfxName, startCFrame)
	if not conjureClone then return end

	local tween = TweenService:Create(conjureClone, TweenInfo.new(2), {CFrame = targetCFrame})
	tween:Play()
	tween.Completed:Wait()
	conjureClone:Destroy()

	local impactClone = self:_spawnVfx(self.impactVfxName, targetCFrame)
	if impactClone then
		soundControllerModule:Play(self.soundEffect, impactClone)
		Debris:AddItem(impactClone, self.sustainTime)
	end

	task.spawn(function()
		local elapsed = 0
		local step = 1
		while elapsed < self.sustainTime do
			self:_applyDamage()
			self:_applySlow()
			task.wait(step)
			elapsed += step
		end

		Cooldown[self.player] = true
		task.delay(self.cooldown, function()
			Cooldown[self.player] = false
			print("Cooldown over and the player is ready to try again.")
		end)
	end)
end


return Ice
