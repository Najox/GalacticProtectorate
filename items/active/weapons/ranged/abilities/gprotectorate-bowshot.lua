--Modified bow shot ability that drains energy while drawing and holding, with configurable drain rates. Has an animation state for when arrows have been loosed

require "/scripts/vec2.lua"

-- Bow primary ability
GProtBowShot = WeaponAbility:new()

function GProtBowShot:init()
  self.energyPerShot = self.energyPerShot or 0

  self.drawTimer = 0
  animator.setAnimationState("bow", "idle")
  self.cooldownTimer = 0

  self:reset()

  self.weapon.onLeaveAbility = function()
    self:reset()
  end
end

function GProtBowShot:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  world.debugPoint(self:firePosition(), "red")
  
  self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)

  if not self.weapon.currentAbility and self.fireMode == (self.activatingFireMode or self.abilitySlot) and self.cooldownTimer == 0 and (self.drawTimer > 0 or not status.resourceLocked("energy")) then
    self:setState(self.draw)
  end
end

function GProtBowShot:uninit()
  self:reset()
end

function GProtBowShot:reset()
  animator.setGlobalTag("drawFrame", "0")
  animator.setAnimationState("bow", "idle")
  animator.stopAllSounds("draw")
  animator.stopAllSounds("ready")
  self.weapon:setStance(self.stances.idle)
end

function GProtBowShot:draw()
  self.weapon:setStance(self.stances.draw)

  animator.playSound("draw", -1)
  local readySoundPlayed = false

  while self.fireMode == (self.activatingFireMode or self.abilitySlot) and not status.resourceLocked("energy") do
    if self.walkWhileFiring then
	  mcontroller.controlModifiers({runningSuppressed = true})
	end

    self.drawTimer = self.drawTimer + self.dt

    local drawFrame = math.min(#self.drawArmFrames - 2, math.floor(self.drawTimer / self.drawTime * (#self.drawArmFrames - 1)))
	
	--If not yet fully drawn, drain energy quickly
	if self.drawTimer < self.drawTime then
	  status.overConsumeResource("energy", self.energyPerShot / self.drawTime * self.dt)
	
	--If fully drawn and at peak power, prevent energy regen and set the drawFrame to power charged
	elseif self.drawTimer > self.drawTime and self.drawTimer <= (self.drawTime + (self.powerProjectileTime or 0)) then
	  status.setResourcePercentage("energyRegenBlock", 0.6)
	  drawFrame = #self.drawArmFrames - 1
	  if self.drainEnergyWhilePowerful then
		status.overConsumeResource("energy", self.holdEnergyUsage * self.dt) --Optionally drain energy while at max power level
	  end
	
	--If drawn beyond power peak levels, drain energy slowly
	elseif self.drawTimer > (self.drawTime + (self.powerProjectileTime or 0)) then
	  status.overConsumeResource("energy", self.holdEnergyUsage * self.dt)
	end
	
	--If the bow is almost fully drawn, stop the draw sound and play the ready sound
	--Do this slightly before the draw is ready so the player can release when they hear the sound
	--This way, the sound plays at the same moment in the draw phase for every bow regardless of draw time
	if self.drawTimer >= (self.drawTime - 0.15) then
	  animator.stopAllSounds("draw")
	  if not readySoundPlayed then
		animator.playSound("ready")
		readySoundPlayed = true
	  end
	end
	
    animator.setGlobalTag("drawFrame", drawFrame)
    self.stances.draw.frontArmFrame = self.drawArmFrames[drawFrame + 1]
	
	world.debugText(drawFrame .. " | " .. sb.printJson(self:perfectTiming()), mcontroller.position(), "red")
	--world.debugText(sb.printJson(self:currentProjectileParameters(), 1), mcontroller.position(), "yellow")
	
    coroutine.yield()
  end

  animator.stopAllSounds("draw")
  self:setState(self.fire)
end

function GProtBowShot:fire()
  self.weapon:setStance(self.stances.fire)

  animator.setGlobalTag("drawFrame", "0")
  animator.stopAllSounds("ready")

  if not world.lineTileCollision(mcontroller.position(), self:firePosition()) then
    for i = 1, (self.projectileCount or 1) do
	  world.spawnProjectile(
        self:perfectTiming() and self.powerProjectileType or self.projectileType,
        self:firePosition(),
        activeItem.ownerEntityId(),
        self:aimVector(),
        false,
        self:currentProjectileParameters()
      )

	  if self:perfectTiming() then
		animator.playSound("perfectRelease")
	  else
		animator.playSound("release")
	  end
	end
	
	animator.setAnimationState("bow", "loosed")

    self.drawTimer = 0

    util.wait(self.stances.fire.duration)
  end

  self.cooldownTimer = self.cooldownTime
end

--Call this to check if the bow was released at the perfect moment. Bows can be configured to not use perfect timing mechanics
function GProtBowShot:perfectTiming()
  if self.powerProjectileTime then
	return self.drawTimer > self.drawTime and self.drawTimer < (self.drawTime + self.powerProjectileTime)
  else
	return false
  end
end

function GProtBowShot:currentProjectileParameters()
  --Set projectile parameters based on draw power level
  local projectileParameters = copy(self:perfectTiming() and self.powerProjectileParameters or self.projectileParameters or {})
  --Load the root projectile config based on draw power level
  local projectileConfig = root.projectileConfig(self:perfectTiming() and self.powerProjectileType or self.projectileType)
  
  --Calculate projectile speed based on draw time and projectile parameters
  projectileParameters.speed = projectileParameters.speed or projectileConfig.speed
  if self.speedNotAffectedByDraw ~= false then
    projectileParameters.speed = projectileParameters.speed * math.min(1, (self.drawTimer / self.drawTime))
  end

  --Calculate projectile power based on draw time and projectile parameters
  local drawTimeMultiplier = self.staticDamageMultiplier or math.min(1, (self.drawTimer / self.drawTime))
  projectileParameters.power = projectileParameters.power or projectileConfig.power
  projectileParameters.power = projectileParameters.power
	* self.weapon.damageLevelMultiplier
	* drawTimeMultiplier
	* (self.dynamicDamageMultiplier or 1)
	/ (self.projectileCount or 1)
  projectileParameters.powerMultiplier = activeItem.ownerPowerMultiplier()

  return projectileParameters
end

function GProtBowShot:aimVector()
  local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(self.inaccuracy or 0, 0))
  aimVector[1] = aimVector[1] * self.weapon.aimDirection
  return aimVector
end

function GProtBowShot:firePosition()
  return vec2.add(mcontroller.position(), activeItem.handPosition(self.fireOffset))
end
