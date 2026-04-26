-- Services

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local abilityEffects = ReplicatedStorage.remotes:WaitForChild("abilityEffects")

-- folders

local Effects = ReplicatedStorage:WaitForChild("Effects")

-- modules

local soundControllerModule = require(ReplicatedStorage:WaitForChild("modules").SoundModule)
local animationCache = require(ReplicatedStorage.modules.Server.animationCaller)
local Calculate = require(ReplicatedStorage.modules.CalculationModule) -- The main calculations module.

local Cooldown = {}

local Fire = {}
Fire.__index = Fire 

function Fire.new(player, ability, target)
	local self = setmetatable({}, Fire)  -- create new fire object
	
	self.player = player -- the player sent from the server script
	self.ability = ability 
	self.character = player.Character
	self.damage = ability.Damage or 0 -- the original damage from the ability
	self.bodyPart = ability.BodyPart or "Head" -- the body part to attach the vfx to or a regular basepart.
	self.sustainTime = ability.SustainTime or 5 
	self.range = ability.Range or 10 
	self.cooldown = ability.Cooldown or 10 -- the cooldown of the ability either given from the ability data logic or set to a default value of 10
	self.manaCost = ability.ManaCost or 10 -- how much mana this ability costs either given from the ability data logic or set to default value of 10
	self.vfxName = (ability.Effects and ability.Effects.Effect) or "Conjure" 
	self.impactVfxName = (ability.Effects and ability.Effects.Impact) or "Conjure" 
	self.soundEffect = ability.SoundEffect or "" -- the sound effect for the ability or if none found then just be soundless
	self.animation = ability.Animation or ""-- the animation id to play which we give to our main animation module  
	self.target = target -- the target can either be ground/baseplate or a player
	self._hitChars = {}
	
	self:Activate() -- call the activate function to start the ability as soon as the module is called.
	return self
end

function Fire:checkPlayer() -- Check if a player exists and if the character exists if none is found then return false a basic safety check
	if not self.player or not self.player.Character then
		return false
	end
	return true
end

function Fire:checkMana() 
	if not self:checkPlayer() then return false end 
	-- Check mana
	local ClassAttributes = self.player:WaitForChild("ClassStats") 
	
	local attr = ClassAttributes:FindFirstChild("Attributes") -- Attributes holds the mana attribute for only the mage class
	if not attr then return false end
	
	local mana = attr:GetAttribute("Mana")
	if not mana then return false end -- If no mana attribute then return false we have a warrior and rogue class they use Stamina so if somehow? A warrior or rogue calls this then it won't run
	
	-- Check if mana is enough for ability if not then return false
	if tonumber(self.manaCost) > tonumber(mana) then -- mana is an attribute not a number value or any other checkable value like nummy.Value so we don't need to check for it's value it is a number.
		warn("Not enough mana for player: " .. self.player.Name) -- print the warning to the console 
		return false
	end
	
	local proceeds = mana - self.manaCost -- calculate the remaining mana after the ability is used
	attr:SetAttribute("Mana", proceeds) 
	
	return true
end

function Fire:playAnimation()
	if self.animation and self.character then -- check if anim and char exist
		animationCache:Get(self.player):PlayCustom(self.animation) -- pass in a anim to the cache if the cache found a instance for this player
	else
		-- no anim 
	end
end

function Fire:spawnVfx(vfxName, cframe) -- spawn the vfx and return the clone
	local vfxTemplate = Effects:FindFirstChild(vfxName) -- find the vfx name from the effects folder
	if not vfxTemplate then 
		return nil 
	end

	local clone = vfxTemplate:Clone() -- clone the vfx template if found
	clone.Anchored = true
	clone.CanCollide = false
	clone.CFrame = cframe -- The CFrame we passed into the function is the target position and that's where it'll originally start.
	clone.Transparency = 1 -- the transparency of the part should be 1 to not break immersion by seeing a part floating randomly in the world
	clone.Parent = workspace 

	for _, attachment in (clone:GetChildren()) do -- if we find an attachment in the clone then we'll go deeper to find the particle emitter inside it.
		if attachment:IsA("Attachment") then
			for _, emitter in (attachment:GetChildren()) do -- if we find a particle emitter inside the attachment then we'll emit 5 particles
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(5) -- Emit the particles 5 times. I was considering making it scale with damage but that seemed visually tacky and i couldn't find a good ratio so 5 is good
				end
			end
		end
	end
	
	return clone -- return the clone if need be manipulate its position further
end

function Fire:Snapshot(position)
	local hitZ = Instance.new("Part")
	hitZ.Shape = Enum.PartType.Cylinder
	hitZ.Anchored = true
	hitZ.CanCollide = false
	hitZ.Material = Enum.Material.Neon
	hitZ.Color = Color3.fromRGB(209, 10, 10) -- Darker red than shockwave (snap)
	hitZ.Transparency = 0.4

	hitZ.Size = Vector3.new(0.2, self.range * 2, self.range * 2) -- Set the size of the cylinder it should be smaller than the shockwave like a inner circle hence *2
	hitZ.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)) -- Same as in shock just make the cylinder flat on the ground
	hitZ.Parent = workspace

	TweenService:Create(hitZ, TweenInfo.new(0.25), {
		Size = Vector3.new(0.2, self.range * 2.5, self.range * 2.5) -- Tween the size of the cylinder to be the range * 2.5 shockwave is m
	}):Play()

	TweenService:Create(hitZ, TweenInfo.new(0.4), {
		Transparency = 1 -- Tween the transparency to 1 after 0.4 seconds
	}):Play()

	game:GetService("Debris"):AddItem(hitZ, 0.5) -- Give it a .1 second to fully tween transparency = 1 if it prematurely deletes itself that looks very poor
end

function Fire:Inner(position) -- Create a shockwave effect "After effects?" it's like a risidual visual after the explosion
	local ri = Instance.new("Part")
	ri.Shape = Enum.PartType.Cylinder
	ri.Anchored = true
	ri.CanCollide = false
	ri.Material = Enum.Material.Neon
	ri.Color = Color3.fromRGB(255, 82, 48) -- Reddish color?
	ri.Transparency = 0.2 -- Make it slightly transparent

	ri.Size = Vector3.new(0.2, 1, 1)
	ri.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)) -- Make it a cylinder and also rotate it so it's flat on the ground
	ri.Parent = workspace

	TweenService:Create(ri, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, self.range * 6, self.range * 6), -- Tween the shckwave to be as wide as the range * 6
		Transparency = 1
	}):Play()

	game:GetService("Debris"):AddItem(ri, 0.4)  -- Remove the ring after 0.4 seconds
end

function Fire:applyDamage(originCFrame) -- apply the damage to the targets
	local enemiesFolder = workspace:FindFirstChild("Enemies") -- This is where all Enemy npcs are stored therefore friendly fire is eliminated from the equation that and passerbys within radius
	if not enemiesFolder then return end 
	for _, model in (enemiesFolder:GetChildren()) do
		if model:IsA("Model") and model ~= self.character then 
			local hum = model:FindFirstChildOfClass("Humanoid") 
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if not hum or not hrp then continue end
			
			local dist = (hrp.Position - originCFrame.Position).Magnitude -- determine the distance between the model and the originCFrame by checking the magnitude.
			
			if dist <= self.range then -- if the distance is less than or equal to the range then apply the damage.
				if not self._hitChars[model] then
					self._hitChars[model] = true -- Put the targeted model(s) in the table of models that have been hit.

					local calc = Calculate.new(self.player, model) -- Create a new calculator instance and send it the player and the targets model

					local isCrit = calc:ApplyCritChance() -- check if it's a critical hit or not and scale up base damage accordingly.
					local isFlank = false 

					local finalDamage = calc:ApplyDamage(self.damage, "Fire", isCrit, isFlank) -- we get the final damage from the calculation module. We send it base damage, which ability type was cast, if it was a critical hit and if we the player caught the enemies by suprise

					print("Applied", finalDamage, "damage to", model.Name) -- print what the final damage was.

					-- Apply knockback as before
					local direction = (hrp.Position - originCFrame.Position).Unit -- Determine the direction of the force and normalize the vector
					if direction.Magnitude == 0 then -- if magnitude is 0 then we set the direction to the +Z axis to prevent a divide by zero error.
						direction = Vector3.new(0, 0, 1) 
					end
					
					--Apply a knockback effect to the enemy's HumanoidRootPart.
					local force = 60 -- horizontal knockback strength (200) 
					local knockbackVelocity = direction * force + Vector3.new(0, 50, 0) -- direction + upward lift
					local attachment = hrp:FindFirstChild("KnockbackAttachment")

					if not attachment then
						attachment = Instance.new("Attachment") -- create a new attachment
						attachment.Name = "KnockbackAttachment" 
						attachment.Parent = model.HumanoidRootPart
					end

					local lv = Instance.new("LinearVelocity") -- Use linear velocity to apply a knockback effect
					lv.Attachment0 = attachment
					lv.RelativeTo = Enum.ActuatorRelativeTo.World 
					lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
					lv.VectorVelocity = knockbackVelocity * 0.8
					lv.MaxForce = math.huge
					lv.Parent = hrp

					Debris:AddItem(lv, 0.25)
				end
			end
		end
	end
end


function Fire:Activate() 
	if not self:checkMana() then return end -- Check if player has enough mana to cast ability. If not, return.
	if Cooldown[self.player] then -- This player is still on cooldown.
		return
	end
	if not self.character then return end

	local spawnPart = self.character:FindFirstChild(self.bodyPart) -- spawn at that part in the character
	if not spawnPart then 
		warn("Couldn't find spawn part: " .. self.bodyPart)
		return
	end

	self:playAnimation() -- play anim
	local startCFrame = spawnPart.CFrame 
	local targetCFrame

	if typeof(self.target) == "Instance" and self.target:IsA("Model") then -- Check if it's a model or "instance" possibly another player
		local root = self.target:FindFirstChild("HumanoidRootPart") -- Find the root part of the target model
		if not root then return end -- If we can't find the root part then return
		targetCFrame = root.CFrame 
	elseif typeof(self.target) == "Vector3" then -- if we have a Vector3 then that means the player has pointed towards the ground
		targetCFrame = CFrame.new(self.target) 
	else
		warn("Invalid target for Conjure") -- If we have an invalid target then return
		return
	end

	local conjureClone = self:spawnVfx(self.vfxName, startCFrame) -- This is the vfx we have at the start of the ability
	if not conjureClone then return end -- if the vfx didn't spawn then return
	abilityEffects:FireClient(self.player, "FireballCast")

	local tween = TweenService:Create(conjureClone, TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {CFrame = targetCFrame}) -- we tween the conjure vfx to the targetCFrame at a speed of 2 and tweening its CFrame to the target
	tween:Play()
	tween.Completed:Wait() -- when the tween is completed we will destroy it which means we have reached our destination and have started impact.
	conjureClone:Destroy()

	local impactClone = self:spawnVfx(self.impactVfxName, targetCFrame) -- Spawn the impact vfx at the targetCFrame
	if impactClone then -- if the impact vfx spawned then
		soundControllerModule:Play(self.soundEffect, impactClone) -- We play the sound effect using our main sould module we pass two args (the sound id = soundEffect, and the part the sound will be attached to in workspace) need to add in another {} params for settings
		Debris:AddItem(impactClone, self.sustainTime) -- The Debris module will remove the vfx after 5 seconds
		
		local impactPos = targetCFrame.Position 

		self:Snapshot(impactPos)
		self:Inner(impactPos) 
	end
	abilityEffects:FireClient(self.player, "ExplosionHit") -- Fire the client event the client will run the camera function for the given param this case being "ExplosionHit"

	task.spawn(function() -- this function runs completely indepent of the rest of the code so it doesn't halt progress with the whole loop.
		local t = 0 
		local step = 0.5 -- step is the time between each step and how long it takes for elapsed to equal sustain time (How long the ability will last on impact)
		while t < self.sustainTime do -- while elapsed is less than the sustain time then
			self:applyDamage(targetCFrame) -- apply the damage to the targets
			task.wait(step) -- wait t amount
			t += step -- add step to t
		end

		Cooldown[self.player] = true -- put player on cooldown
		task.delay(self.cooldown, function()
			Cooldown[self.player] = false -- finally the player is off cooldown and can use the ability again!
		end)
	end)
end

return Fire 
