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

-- dict to determine which player is on cooldown and for how long 

local Cooldown = {}

local Fire = {}
Fire.__index = Fire -- set the metatable

function Fire.new(player, ability, target)
	local self = setmetatable({}, Fire)  -- create new fire object
	
	self.player = player -- the player sent from the server script
	self.ability = ability -- which fire variation was called
	self.character = player.Character
	self.damage = ability.Damage or 0 -- the original damage from the ability
	self.bodyPart = ability.BodyPart or "Head" -- the body part to attach the vfx to or a regular basepart.
	self.sustainTime = ability.SustainTime or 5 -- how long the ability lasts in world after being casted
	self.range = ability.Range or 10 -- the range of enemies it will afflict
	self.cooldown = ability.Cooldown or 10 -- the cooldown of the ability either given from the ability data logic or set to a default value of 10
	self.manaCost = ability.ManaCost or 10 -- how much mana this ability costs either given from the ability data logic or set to default value of 10
	self.vfxName = (ability.Effects and ability.Effects.Effect) or "Conjure" -- the name of the vfx to be found in the effects folder
	self.impactVfxName = (ability.Effects and ability.Effects.Impact) or "Conjure" -- the name of the impact to be found in the effects folder
	self.soundEffect = ability.SoundEffect or "" -- the sound effect for the ability or if none found then just be soundless
	self.animation = ability.Animation or ""-- the animation id to play which we give to our main animation module  
	self.target = target -- the target can either be ground/baseplate or a player
	self._hitChars = {} -- the number of targets within radius of the target 
	
	self:Activate() -- call the activate function to start the ability as soon as the module is called.
	return self
end

function Fire:checkPlayer() -- Check if a player exists and if the character exists if none is found then return false
	if not self.player or not self.player.Character then
		return false
	end
	return true
end

function Fire:checkMana() 
	if not self:checkPlayer() then return false end -- If no player or character then return false
	-- Check mana
	
	local ClassAttributes = self.player:WaitForChild("ClassStats") -- This is the config which holds the attributes child config
	if not ClassAttributes then return end
	
	local Attributes = ClassAttributes:FindFirstChild("Attributes") -- Attributes holds the mana attribute for only the mage class
	if not Attributes then return false end
	
	local mana = Attributes:GetAttribute("Mana")
	if not mana then return false end -- If no mana attribute then return false
	
	-- Check if mana is enough for ability if not then return false
	if self.manaCost > tonumber(mana) then -- mana is an attribute not a number value or any other checkable value so we don't need to check for it's value it is a number.
		warn("Not enough mana for player: " .. self.player.Name) -- print the warning to the console 
		return false
	end
	
	local proceeds = mana - self.manaCost -- calculate the remaining mana after the ability is used
	Attributes:SetAttribute("Mana", proceeds) -- set the remaining mana attribute because we're using attributes we can't just subtract and manually set the value like that
	
	return true
end


function Fire:playAnimation()
	if self.animation and self.character then -- if we find animation then we'll call the animationControllerModule and ask it to play a custom animation (we pass the animation id)
		animationCache:Get(self.player):PlayCustom(self.animation)
	else
		print(self.ability.Name .. "' has no animation.") -- print that the ability has no animation if it's either "" or there's simply not an animation specified 
	end
end

function Fire:spawnVfx(vfxName, cframe) -- spawn the vfx and return the clone
	local vfxTemplate = Effects:FindFirstChild(vfxName) -- find the vfx name from the effects folder
	if not vfxTemplate then 
		return nil -- return nil if we can't find it (making nothing beyond this point run.)
	end

	local clone = vfxTemplate:Clone() -- clone the vfx template if found
	clone.Anchored = true
	clone.CanCollide = false
	clone.CFrame = cframe -- The CFrame we passed into the function is the target position and that's where it'll originally start.
	clone.Transparency = 1 -- the transparency of the part should be 1 to not break immersion by seeing a part in the world
	clone.Parent = workspace -- clone it to the workspace so all players can see it.

	for _, attachment in (clone:GetChildren()) do -- if we find an attachment in the clone then we'll go deeper to find the particle emitter inside it.
		if attachment:IsA("Attachment") then
			for _, emitter in (attachment:GetChildren()) do -- if we find a particle emitter inside the attachment then we'll emit 5 particles
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(5) -- Emit the particles 5 times. I was considering making it scale with damage but that seemed visually tacky and i couldn't find a good ratio so 5 is good
				end
			end
		end
	end
	
	return clone -- return the clone if need be we can manipulate its position further
end

function Fire:Snapshot(position)
	local zone = Instance.new("Part")
	zone.Shape = Enum.PartType.Cylinder
	zone.Anchored = true
	zone.CanCollide = false
	zone.Material = Enum.Material.Neon
	zone.Color = Color3.fromRGB(209, 10, 10) -- Darker red 
	zone.Transparency = 0.4

	zone.Size = Vector3.new(0.2, self.range * 2, self.range * 2) -- Set the size of the cylinder it should be smaller than the shockwave like a inner circle hence *2
	zone.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	zone.Parent = workspace

	TweenService:Create(zone, TweenInfo.new(0.25), {
		Size = Vector3.new(0.2, self.range * 2.5, self.range * 2.5) -- Tween the size of the cylinder to be the range * 2.5 shockwave is m
	}):Play()

	TweenService:Create(zone, TweenInfo.new(0.4), {
		Transparency = 1 -- Tween the transparency to 1 after 0.4 seconds
	}):Play()

	game:GetService("Debris"):AddItem(zone, 0.5) -- Give it a .1 second to fully tween transparency = 1
end

function Fire:shocka(position) -- Create a shockwave effect "After effects?" it's like a risidual visual after the explosion
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 82, 48) -- Reddish color?
	ring.Transparency = 0.2 -- Make it slightly transparent

	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)) -- Make it a cylinder and also rotate it so it's flat on the ground
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, self.range * 6, self.range * 6), -- Tween the shckwave to be as wise as the range * 6
		Transparency = 1
	}):Play()

	game:GetService("Debris"):AddItem(ring, 0.4)  -- Remove the ring after 0.4 seconds
end

function Fire:applyDamage(originCFrame) -- apply the damage to the targets
	local enemiesFolder = workspace:FindFirstChild("Enemies") -- This is where all Enemy npcs are stored therefore friendly fire is eliminated from the equation that and passerbys within radius
	if not enemiesFolder then return end -- if we cannot find the folder then don't run all that comes after this.
	-- In a production sceneio consider spatial partitioning or caching nearby enemies to prevent lag.
	for _, model in (enemiesFolder:GetDescendants()) do
		if model:IsA("Model") 
			and model:FindFirstChildOfClass("Humanoid") 
			and model:FindFirstChild("HumanoidRootPart") 
			and model ~= self.character then -- check if the model is our player or not if it's not then we can apply the damage to it. This prevents players from damaging themselves by their own spells.

			local dist = (model.HumanoidRootPart.Position - originCFrame.Position).Magnitude -- determine the distance between the model and the originCFrame by checking the magnitude.
			
			if dist <= self.range then -- if the distance is less than or equal to the range then apply the damage.
				if not self._hitChars[model] then -- if no models have been hit then we can apply the damage.
					self._hitChars[model] = true -- Put the targeted model in the table of models that have been hit.

					local calc = Calculate.new(self.player, model) -- Create a new calculator instance and send it the player and the targets model

					local isCrit = calc:ApplyCritChance() -- check if it's a critical hit or not and scale up base damage accordingly.
					local isFlank = false -- we determine if this is flank in this module and scale up base damage accordingly.

					local finalDamage = calc:ApplyDamage(self.damage, "Fire", isCrit, isFlank) -- we get the final damage from the calculation module. We send it base damage, which ability type was cast, if it was a critical hit and if we the player caught the enemies by suprise

					print("Applied", finalDamage, "damage to", model.Name) -- print what the final damage was.

					-- Apply knockback as before
					local direction = (model.HumanoidRootPart.Position - originCFrame.Position).Unit -- Determine the direction of the force and normalize the vector
					if direction.Magnitude == 0 then -- if magnitude is 0 then we set the direction to the +Z axis to prevent a divide by zero error.
						direction = Vector3.new(0, 0, 1) 
					end
					
					--Apply a knockback effect to the enemy's HumanoidRootPart.
					local force = 60 -- horizontal knockback strength (200) 
					local knockbackVelocity = direction * force + Vector3.new(0, 50, 0) -- direction + upward lift
					local attachment = model.HumanoidRootPart:FindFirstChild("KnockbackAttachment")

					if not attachment then
						attachment = Instance.new("Attachment") -- create a new attachment
						attachment.Name = "KnockbackAttachment" 
						attachment.Parent = model.HumanoidRootPart
					end

					local linearVelocity = Instance.new("LinearVelocity")
					linearVelocity.Attachment0 = attachment
					linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World -- apply force in world space
					linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector -- apply force in world space
					linearVelocity.VectorVelocity = knockbackVelocity * 0.8
					linearVelocity.MaxForce = math.huge
					linearVelocity.Parent = model.HumanoidRootPart 

					Debris:AddItem(linearVelocity, 0.25)
				end
			end
		end
	end
end


function Fire:Activate() -- Our Main activate caller.
	if not self:checkMana() then return end -- Check if player has enough mana to cast ability. If not, return.
	if Cooldown[self.player] then -- if we find the player has already casted the ability and is still on cooldown then return and prevent the code from running.
		return
	end
	if not self.character then return end

	local spawnPart = self.character:FindFirstChild(self.bodyPart) -- the spawn part is the part of the player's character that the ability will originate from.
	if not spawnPart then -- if we can't find spawnPos then return
		warn("Couldn't find spawn part: " .. self.bodyPart)
		return
	end

	self:playAnimation() --Call play animation
	local startCFrame = spawnPart.CFrame -- start CFrame is where we originate
	local targetCFrame -- targetCFrame is where the effect is traveling too.

	if typeof(self.target) == "Instance" and self.target:IsA("Model") then -- Check if it's a model or "instance" possibly another player
		local root = self.target:FindFirstChild("HumanoidRootPart") -- Find the root part of the target model
		if not root then return end -- If we can't find the root part then return
		targetCFrame = root.CFrame -- Set the targetCFrame to the root part of the target model
	elseif typeof(self.target) == "Vector3" then -- if we have a Vector3 then that means the player has pointed towards the ground
		targetCFrame = CFrame.new(self.target) -- we don't have to search for the root since a vector already is a position we make the Vector a CFrame 
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
		self:shocka(impactPos) 
	end
	abilityEffects:FireClient(self.player, "ExplosionHit") -- Fire the client event the client will run the camera function for the given param this case being "ExplosionHit"

	task.spawn(function() -- this function runs completely indepent of the rest of the code so it doesn't halt progress with the whole loop.
		local elapsed = 0 -- default time elapsed is set to 0
		local step = 0.5 -- step is the time between each step and how long it takes for elapsed to equal sustain time (How long the ability will last on impact)
		while elapsed < self.sustainTime do -- while elapsed is less than the sustain time then
			self:applyDamage(targetCFrame) -- apply the damage to the targets
			task.wait(step) -- wait step amount
			elapsed += step -- add step to elapsed
		end

		Cooldown[self.player] = true -- We put the player on cooldown since they have activated the ability
		task.delay(self.cooldown, function() -- we have an inbuilt delay which will wait the cooldown time
			Cooldown[self.player] = false -- finally the player is off cooldown and can use the ability again!
		end)
	end)
end

return Fire 
