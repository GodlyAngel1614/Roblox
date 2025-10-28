-- Services

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- folders

local Effects = ReplicatedStorage:WaitForChild("Effects")

-- modules

local soundControllerModule = require(ReplicatedStorage:WaitForChild("modules").SoundModule)
local animationControllerModule = require(ReplicatedStorage:WaitForChild("modules").AnimationModule)

-- dict to determine which player is on cooldown and for how long 

local Cooldown = {}

--[[
    Fire Ability Module (228 lines)
    Author: Heavenslay2020/Un6dinary/LightYagami
    
    Overview:
    This module handles the behavior of a Fireball ability in Roblox.
      - TweenService for projectile motion
      - CFrame math for dynamic targeting
      - Tables/metatables for object-like structures
      - Animation and sound integration
      - Cooldown and mana management
    
    The module is designed to be modular, efficient, and readable,
    with explanatory comments to show understanding of Roblox API and game logic.
]]

local Fire = {}
Fire.__index = Fire -- set the metatable

-- Constructor
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

function Fire:_checkPlayer() -- Check if a player exists and if the character exists if none is found then return false
	if not self.player then
		warn("[Conjure] Player is nil!")
		return false
	end
	if not self.player.Character then
		warn("[Conjure] Player has no character!")
		return false
	end
	return true
end

function Fire:_checkMana() 
	if not self:_checkPlayer() then return false end -- If no player or character then return false
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


function Fire:_playAnimation()
	if self.animation and self.character then -- if we find animation then we'll call the animationControllerModule and ask it to play a custom animation (we pass the animation id)
		animationControllerModule:PlayCustom(self.character, self.animation)
	else
		print("?[NO ANIMATION]? ? '" .. self.ability.Name .. "' has no animation.") -- print that the ability has no animation if it's either "" or there's simply not an animation specified 
	end
end

function Fire:_spawnVfx(vfxName, cframe) -- spawn the vfx and return the clone
	local vfxTemplate = Effects:FindFirstChild(vfxName) -- find the vfx name from the effects folder
	if not vfxTemplate then -- if we can't find that effect in the effects folder then print an error to the console
		warn("Couldn't find VFX: " .. tostring(vfxName))
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
			for _, emitter in (attachment:GetChildren()) do
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(5) -- Emit the particles 5 times.
				end
			end
		end
	end

	return clone -- return the clone if need be we can manipulate its position further
end

local Calculate = require(ReplicatedStorage.modules.CalculationModule) -- The main calculations module.

function Fire:_applyDamage(originCFrame) -- apply the damage to the targets
	local enemiesFolder = workspace:FindFirstChild("Enemies") -- This is where all Enemy npcs are stored therefore friendly fire is eliminated from the equation that and passerbys within radius
	if not enemiesFolder then return end -- if wee cannot find the folder then don't run all that comes after this.
	-- In a production sceneio consider spatial partitioning or caching nearby enemies to prevent lag.
	for _, model in ipairs(enemiesFolder:GetDescendants()) do
		if model:IsA("Model") 
			and model:FindFirstChildOfClass("Humanoid") 
			and model:FindFirstChild("HumanoidRootPart") 
			and model ~= self.character then -- check if the model is our player or not if it's not then we can apply the damage to it. This prevents players from damaging themselves by their own spells.

			local dist = (model.HumanoidRootPart.Position - originCFrame.Position).Magnitude -- determine the distance between the model and the originCFrame by checking the magnitude.
			-- Using magnitude is simpler than raycasting or Region3 for an AoE (Area of effect) ability.
			--but this is a more simplistic approach.
			
			if dist <= self.range then -- if the distance is less than or equal to the range then apply the damage.
				if not self._hitChars[model] or self.sustainTime > 0 then -- if no models have been hit or the sustain time is greater than 0 then apply the damage. (This is for the sustain time to allow multiple hits to the same target.)
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
					
					--[[
						Apply a knockback effect to the enemy's HumanoidRootPart.
						
						1. force determines the horizontal strength of the knockback (up and down)
						2. knockbackVelocity combines the horizontal knockback direction and upward boost (Vector3.new(0, 50, 0))
						to make the enemy lift slightly off the ground
						3. BodyBelocity instance is created to move the enemy 
						4. Velocity is set to our calculated knockback vector
						5. p sets the power of the force, affecting responsiveness to velocity changes.
						6.`Debris:AddItem` removes the BodyVelocity after 0.6 seconds so the enemy can return 
	  					 to normal physics without being permanently forced.
					]]

					local force = 200 -- horizontal knockback strength (200) 
					local knockbackVelocity = direction * force + Vector3.new(0, 50, 0) -- direction + upward lift
					local bodyVelocity = Instance.new("BodyVelocity")
					bodyVelocity.MaxForce = Vector3.new(1e6, 1e6, 1e6) -- allow full force in all directions
					bodyVelocity.Velocity = knockbackVelocity -- apply our knockback velocity
					bodyVelocity.P = 950 -- power/responsiveness of the body velocity
					bodyVelocity.Parent = model.HumanoidRootPart -- attach it to the enemy to apply the knockback
					Debris:AddItem(bodyVelocity, 0.6) -- remove after 0.6 seconds to restore normal physics behavior
				end
			end
		end
	end
end


function Fire:Activate() -- Our Main activate caller.
	if not self:_checkMana() then return end -- Check if player has enough mana to cast ability. If not, return.
	if Cooldown[self.player] then -- if we find the player has already casted the ability and is still on cooldown then return and prevent the code from running.
		return
	end
	if not self.character then return end

	local spawnPart = self.character:FindFirstChild(self.bodyPart) -- the spawn part is the part of the player's character that the ability will originate from.
	if not spawnPart then -- if we can't find spawnPos then return
		warn("Couldn't find spawn part: " .. self.bodyPart)
		return
	end

	self:_playAnimation() --Call play animation
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

	local conjureClone = self:_spawnVfx(self.vfxName, startCFrame) -- This is the vfx we have at the start of the ability
	if not conjureClone then return end -- if the vfx didn't spawn then return

	local tween = TweenService:Create(conjureClone, TweenInfo.new(2), {CFrame = targetCFrame}) -- we tween the conjure vfx to the targetCFrame at a speed of 2 and tweening its CFrame to the target
	tween:Play()
	tween.Completed:Wait() -- when the tween is completed we will destroy it which means we have reached our destination and have started impact.
	conjureClone:Destroy()

	local impactClone = self:_spawnVfx(self.impactVfxName, targetCFrame) -- Spawn the impact vfx at the targetCFrame
	if impactClone then -- if the impact vfx spawned then
		soundControllerModule:Play(self.soundEffect, impactClone) -- We play the sound effect using our main sould module we pass two args (the sound id = soundEffect, and the part the sound will be attached to in workspace)
		Debris:AddItem(impactClone, self.sustainTime) -- The Debris module will remove the vfx after 5 seconds
	end

	task.spawn(function() -- this function runs completely indepent of the rest of the code so it doesn't halt progress with the whole loop.
		local elapsed = 0 -- default time elapsed is set to 0
		local step = 0.5 -- step is the time between each step and how long it takes for elapsed to equal sustain time (How long the ability will last on impact)
		while elapsed < self.sustainTime do -- while elapsed is less than the sustain time then
			self:_applyDamage(targetCFrame) -- apply the damage to the target
			task.wait(step) -- wait step amount of seconds
			elapsed += step -- add step to elapsed
		end

		Cooldown[self.player] = true -- We put the player on cooldown since they have activated the ability
		task.delay(self.cooldown, function() -- we have an inbuilt delay which will wait the cooldown time
			Cooldown[self.player] = false -- finally the player is off cooldown and can use the ability again!
			print("?[COOLDOWN END]? ? '" .. self.ability.Name .. "' is ready again!")
		end)
	end)
end

return Fire -- Return the fire module.
