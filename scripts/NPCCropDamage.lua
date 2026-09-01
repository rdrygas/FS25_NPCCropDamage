--[[
    NPC Crop Damage for Farming Simulator 25

    Extends the vanilla WheelDestruction logic to NPC-owned fields.
    Only player-controlled vehicles are handled. AI workers are ignored.

    Compensation formula:
        damagedAreaSqm * fruitDesc.literPerSqm * maxCurrentPricePerLiter
        * PENALTY_MULTIPLIER
]]

NPCCropDamage = {}

NPCCropDamage.MOD_NAME = g_currentModName or "FS25_NPCCropDamage"

-- User settings -------------------------------------------------------------

-- 1.0 = charge 100% of the estimated market value of the destroyed crop.
-- Change, for example, to 0.5 for 50% or 2.0 for 200%.
NPCCropDamage.PENALTY_MULTIPLIER = 1.0

-- Aggregate small deductions so the money HUD is not updated every frame.
NPCCropDamage.CHARGE_INTERVAL_MS = 1500

-- Selling-point prices are not worth scanning every wheel update.
NPCCropDamage.PRICE_CACHE_MS = 5000

-- A new warning is shown only after this many milliseconds without any newly
-- destroyed crop. This prevents one notification per wheel/frame.
NPCCropDamage.WARNING_RESET_MS = 3000

-- Set to true to print detailed diagnostic information to log.txt.
NPCCropDamage.DEBUG = false

-- Internal state ------------------------------------------------------------

NPCCropDamage.moneyType = nil
NPCCropDamage.pendingCosts = {}
NPCCropDamage.chargeTimer = 0
NPCCropDamage.priceCache = {}
NPCCropDamage.fruitAreaTools = {}
NPCCropDamage.lastDamageTimeByVehicle = {}

-- Debug print function. Only prints if NPCCropDamage.DEBUG is true.
local function debugPrint(formatString, ...)
    if NPCCropDamage.DEBUG then
        Logging.info("[%s] %s", NPCCropDamage.MOD_NAME, string.format(formatString, ...))
    end
end

-- Get the root vehicle of the given vehicle. 
-- If the vehicle is a trailer or implements, this returns the main tractor or truck. 
-- If the vehicle is already a root vehicle, it returns itself. Returns nil if the input is nil.
local function getRootVehicle(vehicle)
    if vehicle == nil then
        return nil
    end

    if vehicle.getRootVehicle ~= nil then
        return vehicle:getRootVehicle()
    end

    return vehicle
end

-- Check if the given vehicle is player-controlled. 
-- Returns true if the vehicle is controlled by a player, false otherwise.
local function isPlayerControlledVehicle(vehicle)
    local rootVehicle = getRootVehicle(vehicle)
    if rootVehicle == nil or rootVehicle.getIsControlled == nil then
        return false
    end

    if not rootVehicle:getIsControlled() then
        return false
    end

    -- This is mainly a safety guard. The vanilla Wheels specialization already
    -- passes allowFoliageDestruction=false while an AI worker is active.
    if rootVehicle.getIsAIActive ~= nil and rootVehicle:getIsAIActive() then
        return false
    end

    return true
end

-- Get the farm ID of the player controlling the given vehicle. 
-- Returns nil if the vehicle is not player-controlled or has no active farm.
local function getActiveFarmId(vehicle)
    local rootVehicle = getRootVehicle(vehicle)
    if rootVehicle ~= nil and rootVehicle.getActiveFarm ~= nil then
        return rootVehicle:getActiveFarm()
    end

    if vehicle ~= nil and vehicle.getActiveFarm ~= nil then
        return vehicle:getActiveFarm()
    end

    return nil
end

-- Check if the given world position is on an NPC-owned field. 
-- Returns true if the position is on a field that has no owner farm, false otherwise.
local function isNpcFieldAtWorldPosition(x, z)
    if g_farmlandManager == nil then
        return false
    end

    local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
    if farmlandId == nil or farmlandId == FarmlandManager.NOT_BUYABLE_FARM_ID then
        return false
    end

    local ownerFarmId = g_farmlandManager:getFarmlandOwner(farmlandId)
    if ownerFarmId ~= FarmlandManager.NO_OWNER_FARM_ID then
        return false
    end

    -- Do not affect decorative vegetation on otherwise unowned land.
    local isOnField = FSDensityMapUtil.getIsFieldAtWorldPos(x, z)
    return isOnField == true or (type(isOnField) == "number" and isOnField > 0)
end

-- Get or create a DensityMapModifier and DensityMapFilter for the given fruit type.
local function getFruitAreaTool(fruitDesc)
    local fruitTypeIndex = fruitDesc.index
    local tool = NPCCropDamage.fruitAreaTools[fruitTypeIndex]
    if tool ~= nil then
        return tool
    end

    if fruitDesc.terrainDataPlaneId == nil
        or fruitDesc.minWheelDestructionState == nil
        or fruitDesc.maxWheelDestructionState == nil then
        return nil
    end

    local modifier = DensityMapModifier.new(
        fruitDesc.terrainDataPlaneId,
        fruitDesc.startStateChannel,
        fruitDesc.numStateChannels,
        g_terrainNode
    )

    local filter = DensityMapFilter.new(
        fruitDesc.terrainDataPlaneId,
        fruitDesc.startStateChannel,
        fruitDesc.numStateChannels
    )

    filter:setValueCompareParams(
        DensityValueCompareType.BETWEEN,
        fruitDesc.minWheelDestructionState,
        fruitDesc.maxWheelDestructionState
    )

    local witheredFilter = nil
    if fruitDesc.witheredState ~= nil then
        witheredFilter = DensityMapFilter.new(
            fruitDesc.terrainDataPlaneId,
            fruitDesc.startStateChannel,
            fruitDesc.numStateChannels
        )

        witheredFilter:setValueCompareParams(
            DensityValueCompareType.EQUAL,
            fruitDesc.witheredState
        )
    end

    tool = {
        modifier = modifier,
        filter = filter,
        witheredFilter = witheredFilter
    }

    NPCCropDamage.fruitAreaTools[fruitTypeIndex] = tool
    return tool
end

-- Add the fruit type to the candidates table if it is not already present and has a valid terrain data plane.
local function addFruitCandidate(candidates, fruitTypeIndex)
    if fruitTypeIndex == nil or candidates[fruitTypeIndex] then
        return
    end

    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if fruitDesc ~= nil
        and fruitDesc.terrainDataPlaneId ~= nil
        and fruitDesc.minWheelDestructionState ~= nil
        and fruitDesc.maxWheelDestructionState ~= nil
        and fruitDesc.wheelDestructionState ~= nil then
        candidates[fruitTypeIndex] = fruitDesc
    end
end

-- Get the fruit types that are present in the given parallelogram area. 
-- The area is defined by three corners (x0, z0), (x1, z1), (x2, z2). The fourth corner is calculated automatically.
local function getFruitCandidates(x0, z0, x1, z1, x2, z2)
    -- The fourth corner of the parallelogram.
    local x3 = x1 + x2 - x0
    local z3 = z1 + z2 - z0
    local centerX = (x0 + x1 + x2 + x3) * 0.25
    local centerZ = (z0 + z1 + z2 + z3) * 0.25

    local candidates = {}
    local samplePoints = {
        {centerX, centerZ},
        {x0, z0},
        {x1, z1},
        {x2, z2},
        {x3, z3}
    }

    for _, point in ipairs(samplePoints) do
        local fruitTypeIndex = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(point[1], point[2])
        addFruitCandidate(candidates, fruitTypeIndex)
    end

    return candidates
end

-- Get the maximum current price per liter for the given fill type index. 
-- The price is cached for PRICE_CACHE_MS milliseconds to avoid scanning all selling points every frame.
local function getMaxCurrentPrice(fillTypeIndex)
    if fillTypeIndex == nil or g_currentMission == nil then
        return 0
    end

    local now = g_currentMission.time or 0
    local cached = NPCCropDamage.priceCache[fillTypeIndex]
    if cached ~= nil and now - cached.time < NPCCropDamage.PRICE_CACHE_MS then
        return cached.price
    end

    local maxPrice = 0
    local storageSystem = g_currentMission.storageSystem

    if storageSystem ~= nil and storageSystem.getUnloadingStations ~= nil then
        for _, unloadingStation in pairs(storageSystem:getUnloadingStations()) do
            if unloadingStation ~= nil
                and unloadingStation.isSellingPoint
                and unloadingStation.acceptedFillTypes ~= nil
                and unloadingStation.acceptedFillTypes[fillTypeIndex]
                and unloadingStation.getEffectiveFillTypePrice ~= nil then

                local price = unloadingStation:getEffectiveFillTypePrice(fillTypeIndex) or 0
                maxPrice = math.max(maxPrice, price)
            end
        end
    end

    -- Fallback for a fruit that has no active selling point on the map.
    if maxPrice <= 0
        and g_currentMission.economyManager ~= nil
        and g_currentMission.economyManager.getPricePerLiter ~= nil then
        maxPrice = g_currentMission.economyManager:getPricePerLiter(fillTypeIndex) or 0
    end

    NPCCropDamage.priceCache[fillTypeIndex] = {
        time = now,
        price = maxPrice
    }

    return maxPrice
end

-- Calculate the total cost of the crop damage in the given parallelogram area.
local function calculateDamageCost(x0, z0, x1, z1, x2, z2)
    local totalCost = 0
    local totalAreaSqm = 0
    local candidates = getFruitCandidates(x0, z0, x1, z1, x2, z2)

    for _, fruitDesc in pairs(candidates) do
        local tool = getFruitAreaTool(fruitDesc)
        if tool ~= nil then
            tool.modifier:setParallelogramWorldCoords(
                x0, z0,
                x1, z1,
                x2, z2,
                DensityCoordType.POINT_POINT_POINT
            )

            -- executeGet returns statistics only; it does not change the crop.
            -- The filter counts only growth states that the base game marks as
            -- destructible by wheels. This prevents charging the same flattened
            -- crop over and over again.
            local _, numPixels, _ = tool.modifier:executeGet(tool.filter)
            numPixels = numPixels or 0

            -- Some fruit definitions include the withered/dead state inside the
            -- broad wheel-destructible state range. A dead crop has no remaining
            -- harvest value, so it must not generate compensation or warnings.
            -- Count the explicitly defined withered state separately and remove
            -- those pixels from the chargeable area.
            local witheredPixels = 0
            if tool.witheredFilter ~= nil then
                local _, numWitheredPixels, _ = tool.modifier:executeGet(tool.witheredFilter)
                witheredPixels = numWitheredPixels or 0
            end

            local chargeablePixels = math.max(numPixels - witheredPixels, 0)

            if chargeablePixels > 0 then
                local areaSqm = MathUtil.areaToHa(
                    chargeablePixels,
                    g_currentMission:getFruitPixelsToSqm()
                ) * 10000

                local litersPerSqm = fruitDesc.literPerSqm or 0
                local fillType = fruitDesc.fillType
                local fillTypeIndex = fillType ~= nil and fillType.index or nil
                local pricePerLiter = getMaxCurrentPrice(fillTypeIndex)
                local cost = areaSqm
                    * litersPerSqm
                    * pricePerLiter
                    * NPCCropDamage.PENALTY_MULTIPLIER

                totalAreaSqm = totalAreaSqm + areaSqm
                totalCost = totalCost + cost

                debugPrint(
                    "%s: %.3f m2, %.3f l/m2, %.4f /l -> %.2f",
                    tostring(fruitDesc.name),
                    areaSqm,
                    litersPerSqm,
                    pricePerLiter,
                    cost
                )

                if witheredPixels > 0 then
                    debugPrint(
                        "%s: ignored %d withered/dead pixel(s)",
                        tostring(fruitDesc.name),
                        witheredPixels
                    )
                end
            end
        end
    end

    return totalCost, totalAreaSqm
end

-- Add the cost to the pending costs for the given farm. 
-- The actual money deduction is performed later in flushPendingCosts().
local function addPendingCost(farmId, cost)
    if farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID or cost <= 0 then
        return
    end

    NPCCropDamage.pendingCosts[farmId] = (NPCCropDamage.pendingCosts[farmId] or 0) + cost
end

-- Show a warning message to the player if they have damaged NPC crops. 
-- The message is shown only once per WARNING_RESET_MS milliseconds.
local function showDamageWarning(vehicle)
    if g_currentMission == nil
        or g_currentMission.addIngameNotification == nil
        or g_i18n == nil then
        return
    end

    local rootVehicle = getRootVehicle(vehicle)
    if rootVehicle == nil then
        return
    end

    local now = g_time or 0
    local lastDamageTime = NPCCropDamage.lastDamageTimeByVehicle[rootVehicle] -- If the vehicle has not damaged crops before, lastDamageTime will be nil.

    -- Show the warning only if enough time has passed since the last damage event.
    if lastDamageTime == nil or now - lastDamageTime >= NPCCropDamage.WARNING_RESET_MS then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("warning_npcCropDamage")
        )
    end

    NPCCropDamage.lastDamageTimeByVehicle[rootVehicle] = now
end

-- Flush the pending costs to the farms and reset the internal state. 
-- This is called periodically to avoid updating the money HUD every frame.
local function flushPendingCosts()
    if g_server == nil or g_currentMission == nil or NPCCropDamage.moneyType == nil then
        return
    end

    for farmId, cost in pairs(NPCCropDamage.pendingCosts) do
        if cost > 0.001 then
            if g_farmManager ~= nil then
                g_farmManager:updateFarmStats(farmId, "expenses", cost)
            end

            g_currentMission:addMoney(-cost, farmId, NPCCropDamage.moneyType, true)
            debugPrint("Charged farm %s: %.2f", tostring(farmId), cost)
        end
    end

    NPCCropDamage.pendingCosts = {}
end

-- Appended to WheelDestruction:update(). The vanilla function has already had
-- its chance to process the wheel. On owned land it performs the normal crop
-- destruction. Here we act only on NPC land, so the two paths do not overlap.
function NPCCropDamage.onWheelDestructionUpdate(wheelDestruction, dt, allowFoliageDestruction)
    if g_server == nil
        or g_currentMission == nil
        or not allowFoliageDestruction
        or wheelDestruction == nil then
        return
    end

    local vehicle = wheelDestruction.vehicle
    if vehicle == nil
        or vehicle.lastSpeedReal == nil
        or vehicle.lastSpeedReal <= 0.0002
        or not isPlayerControlledVehicle(vehicle) then
        return
    end

    local wheel = wheelDestruction.wheel
    if wheel == nil
        or wheel.physics == nil
        or wheel.physics.contact == WheelContactType.NONE
        or wheelDestruction.isCareWheel then
        return
    end

    local destructionNodes = wheelDestruction.destructionNodes
    if destructionNodes == nil then
        return
    end

    for _, destructionNode in ipairs(destructionNodes) do
        local repr = wheel.repr
        local width = 0.5 * destructionNode.width
        local length = math.min(0.5, 0.5 * destructionNode.width)
        local xShift, yShift, zShift = localToLocal(destructionNode.node, repr, 0, 0, 0)

        local x0, _, z0 = localToWorld(repr, xShift + width, yShift, zShift - length)
        local x1, _, z1 = localToWorld(repr, xShift - width, yShift, zShift - length)
        local x2, _, z2 = localToWorld(repr, xShift + width, yShift, zShift + length)

        if isNpcFieldAtWorldPosition(x0, z0) then
            -- Measure the still-destructible crop BEFORE changing its state.
            local cost, damagedAreaSqm = calculateDamageCost(x0, z0, x1, z1, x2, z2)

            if damagedAreaSqm > 0 then
                -- Reuse GIANTS' own wheel-destruction function only when the
                -- footprint contains a living crop that can actually generate
                -- damage. This prevents a purely withered/dead patch from being
                -- treated as a new NPC crop-damage event.
                wheelDestruction:destroyFruitArea(x0, z0, x1, z1, x2, z2)

                showDamageWarning(vehicle)

                if cost > 0 then
                    addPendingCost(getActiveFarmId(vehicle), cost)
                end
            end
        end
    end
end

-- Called when the map is loaded. Initialize internal state and register a new money type.
function NPCCropDamage:loadMap(mapName)
    self.pendingCosts = {}
    self.chargeTimer = 0
    self.priceCache = {}
    self.fruitAreaTools = {}
    self.lastDamageTimeByVehicle = {}

    self.moneyType = MoneyType.register("other", "finance_npcCropDamage")

    Logging.info(
        "[%s] Loaded. NPC crop destruction enabled; penalty multiplier: %.2f",
        self.MOD_NAME,
        self.PENALTY_MULTIPLIER
    )
end

-- Called every frame. Accumulate the pending costs and charge the player at regular intervals.
function NPCCropDamage:update(dt)
    if g_server == nil then
        return
    end

    self.chargeTimer = self.chargeTimer + dt
    if self.chargeTimer >= self.CHARGE_INTERVAL_MS then
        self.chargeTimer = self.chargeTimer - self.CHARGE_INTERVAL_MS
        flushPendingCosts()
    end
end

-- Called when the map is unloaded or the game is exited. Clear all internal state to avoid memory leaks.
function NPCCropDamage:deleteMap()
    flushPendingCosts()
    self.pendingCosts = {}
    self.priceCache = {}
    self.fruitAreaTools = {}
    self.lastDamageTimeByVehicle = {}
end

-- Hook into the vanilla WheelDestruction:update() function. 
-- The original function is called first, then our logic is executed. 
-- This allows the vanilla function to handle owned fields, while we handle NPC-owned fields.
WheelDestruction.update = Utils.appendedFunction(
    WheelDestruction.update,
    NPCCropDamage.onWheelDestructionUpdate
)

-- Register the mod event listener to receive loadMap, update, and deleteMap events.
addModEventListener(NPCCropDamage)
