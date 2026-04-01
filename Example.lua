--!nonstrict
-- LOCATION: ServerScriptService/Modules/ItemManager
 
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
 
-- [ MODULES ]
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)
local MutationConfigurations = require(ReplicatedStorage.Modules.MutationConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local ProductsConfigurations = require(
	ReplicatedStorage.Modules.ProductConfigurations
)
local PlayerController = require(
	ServerScriptService.Controllers.PlayerController
)
-- [ LAZY DEPENDENCIES ]
local CarrySystem 
 
-- [ ASSETS ]
local ItemsFolder = ReplicatedStorage:WaitForChild("Items")
local ItemSpawnsFolder = Workspace:WaitForChild("ItemSpawns")
local Templates = ReplicatedStorage:WaitForChild("Templates")
local InfoGUI_Template = Templates:WaitForChild("InfoGUI")
local CollectionZones = Workspace:WaitForChild("Zones")
 
-- [ CONFIGURATION ]
local INCOME_SCALING = 1.125 
local RECYCLE_MIN_TIME = 30
local RECYCLE_MAX_TIME = 90
local RESPAWN_TIME = 30
local DROPPED_LIFETIME = 30
-- Тут
local MAX_ITEMS_PER_SPAWNER = 1
local MIN_ITEM_SPACING = 4.5 -- Minimum distance in studs between spawned items
 
local ITEM_SPAWN_ORIENTATION_OFFSET = CFrame.Angles(
	math.rad(0),
	math.rad(0),
	math.rad(0)
)
 
-- Тут
local SPAWNER_TIERS = {
	["1"] = { Common = 100, Mutations = false },
	["2"] = { Uncommon = 100, Mutations = false },
	["3"] = { Rare = 100, Mutations = false },
	["4"] = { Epic = 100, Mutations = false },
	["5"] = { Legendary = 100, Mutations = false },
	["6"] = { Mythical = 100, Mutations = false },
 
	["1.1"] = {Common = 100, Mutations = true},
	["2.1"] = {Uncommon = 100, Mutations = true},
	["3.1"] = {Rare = 100, Mutations = true},
	["4.1"] = {Epic = 100, Mutations = true},
	["5.1"] = {Legendary = 100, Mutations = true},
	["6.1"] = {Mythical = 100, Mutations = true},
 
	["VIP"] = {Epic = 100, Mutations = true, Neon = true},
	["SUPER_VIP"] = {Mythical = 100, Mutations = true, Neon = true},
}
 
local DEFAULT_CHANCE = { Common = 100 }
 
local MUTATIONS = {
	{Name = "Neon", Chance = 10},
	{Name = "Ruby", Chance = 5},
	{Name = "Diamond", Chance = 3},
	{Name = "Golden", Chance = 1},
}
 
local MUTATION_MULTIPLIERS = {
	["Normal"] = 1,
	["Golden"] = 2,
	["Diamond"] = 3,
	["Ruby"] = 4,
	["Neon"] = 5,
}
 
local ItemManager = {}
 
-- [ HELPERS ]
 
local function getYSizeOfModelGlobal(model: Model)
	local extentsSize = model:GetExtentsSize()
	local upVector = model:GetPivot().UpVector
 
	local upX = math.abs(math.round(upVector.X))
	local upY = math.abs(math.round(upVector.Y))
 
	if upX == 1 then
		return extentsSize.X
	elseif upY == 1 then
		return extentsSize.Y
	else
		return extentsSize.Z
	end
end
 
local function getRandomUpVectorRotation(model: Model)
	local upVector = model:GetPivot().UpVector
	local rotation = math.rad(math.random(0, 360))
 
	local upX = math.abs(math.round(upVector.X))
	local upY = math.abs(math.round(upVector.Y))
 
	if upX == 1 then
		return CFrame.Angles(rotation, 0, 0)
	elseif upY == 1 then
		return CFrame.Angles(0, rotation, 0)
	else
		return CFrame.Angles(0, 0, rotation)
	end
end
 
local function isInsideAnyZone(position: Vector3): boolean
	for _, zonePart in ipairs(CollectionZones:GetChildren()) do
		if zonePart:IsA("BasePart") then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size
 
			local inside = math.abs(relativePos.X) <= size.X / 2 and
				math.abs(relativePos.Y) <= size.Y / 2 and
				math.abs(relativePos.Z) <= size.Z / 2
 
			if inside then return true end
		end
	end
	return false
end
 
local function getMutation(isEnabled: boolean, info): string
	if not isEnabled then
		return "Normal"
	end
	for _, mutationInfo in pairs(MUTATIONS) do
		if info[mutationInfo.Name] then
			return mutationInfo.Name
		end
	end
	for _, mutation in ipairs(MUTATIONS) do
		local roll = math.random(1, mutation.Chance)
		if roll == 1 then return mutation.Name end
	end
	return "Normal"
end
 
local function getRarityFromTier(tierName: string): string
	local chances = SPAWNER_TIERS[tierName] or DEFAULT_CHANCE
	local totalWeight = 0
 
	for _, weight in pairs(chances) do
		if typeof(weight) ~= "number" then
			continue
		end
		totalWeight += weight
	end
 
	local roll = math.random(0, totalWeight)
	local current = 0
 
	for rarity, weight in pairs(chances) do
		if typeof(weight) ~= "number" then
			continue
		end
		current += weight
		if roll <= current then
			return rarity, SPAWNER_TIERS[tierName].Mutations == true
		end
	end
 
	return "Common", false -- Fallback
end
 
local function applyAnimation(model: Model, animation: Animation)
	local animationController: AnimationController = model:FindFirstChild("AnimationController")
 
	if not animationController then return end
 
	local animator: Animator = animationController.Animator
	local track: AnimationTrack = animator:LoadAnimation(animation)
	track:Play()
end
 
local function clearAnimations(model: Model)
	local animationController = 
		model:FindFirstChild("AnimationController")
	if not animationController then
		return
	end
	local animator = 
		animationController:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop()
		track:Destroy()
	end
end
 
-- [ VISUALS & GUI ]
 
local function setupItemGUI(
	target: Instance, 
	level: number?, 
	totalMultiplier: number?
)
	local rootPart: BasePart?
 
	if target:IsA("Model") then
		rootPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	elseif target:IsA("Tool") then
		rootPart = target:FindFirstChild("Handle") :: BasePart
	end
 
	if not rootPart then return end
	if target:FindFirstChild("InfoGUI") then target.InfoGUI:Destroy() end
 
	local infoGui = InfoGUI_Template:Clone()
	infoGui.Name = "InfoGUI"
	local labelsFrame = infoGui:WaitForChild("TextLabels")
 
	local lblEarnings = labelsFrame:WaitForChild("Earnings") :: TextLabel
	local lblRarity = labelsFrame:WaitForChild("Rarity") :: TextLabel
	local lblName = labelsFrame:WaitForChild("Name") :: TextLabel
	local lblMutation = labelsFrame:WaitForChild("Mutation") :: TextLabel
 
	local itemName = target:GetAttribute("OriginalName") or "Unknown"
	local rarityName = target:GetAttribute("Rarity") or "Common"
	local mutationName = target:GetAttribute("Mutation") or "Normal"
 
	lblName.Text = itemName
 
	-- [[ INCOME CALCULATION UPDATE ]] --
	local itemData = ItemConfigurations.GetItemData(itemName)
	local baseIncome = itemData and itemData.Income or 0
 
	local totalIncome = 
		baseIncome * 
		(MUTATION_MULTIPLIERS[mutationName] or 1) 
		* (INCOME_SCALING ^ ((level or 1) - 1)) 
		* totalMultiplier
 
	lblEarnings.Text = "+" .. NumberFormatter.Format(totalIncome) .. "/s"
 
	-- Rarity Styling
	local rarityConfig = RarityConfigurations[rarityName]
	if rarityConfig then
		lblRarity.Text = rarityConfig.DisplayName
		lblRarity.TextColor3 = rarityConfig.TextColor
		local stroke = lblRarity:FindFirstChild("UIStroke") or lblRarity:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = rarityConfig.StrokeColor; stroke.Thickness = rarityConfig.StrokeThickness end
		local gradient = lblRarity:FindFirstChild("UIGradient") or lblRarity:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Color = rarityConfig.GradientColor end
	end
 
	-- Mutation Styling
	local mutationConfig = MutationConfigurations[mutationName]
	if mutationConfig then
		lblMutation.Text = mutationConfig.DisplayName
		lblMutation.TextColor3 = mutationConfig.TextColor
		local stroke = lblMutation:FindFirstChild("UIStroke") or lblMutation:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = mutationConfig.StrokeColor; stroke.Thickness = mutationConfig.StrokeThickness end
		local gradient = lblMutation:FindFirstChild("UIGradient") or lblMutation:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Color = mutationConfig.GradientColor end
	end
	-- HGH
	infoGui.StudsOffsetWorldSpace = Vector3.new(
		0,
		target:GetExtentsSize().Y / 4,
		0
	)
	infoGui.Adornee = rootPart
	infoGui.Parent = target
end
 
-- [ TOOL CREATION ]
 
function ItemManager.GiveItemToPlayer(
	player: Player, 
	itemName: string,
	mutation: string, 
	rarity: string, 
	level: number?, 
	isTemporary: boolean?
)
	if not itemName then return end
 
	local itemConf = ItemConfigurations.GetItemData(itemName)
	local mutationFolder = ItemsFolder:FindFirstChild(mutation) or ItemsFolder.Normal
	local itemTemplate = mutationFolder:FindFirstChild(itemName) or ItemsFolder.Normal:FindFirstChild(itemName)
 
	if not itemTemplate then warn("Template missing for: " .. itemName) return end
 
	if isTemporary then return end
 
	local newTool = Instance.new("Tool")
	newTool.Name = itemName
	if itemConf then newTool.TextureId = itemConf.ImageId end
 
	newTool:SetAttribute("IsTemporary", false)
	newTool:SetAttribute("OriginalName", itemName)
	newTool:SetAttribute("Mutation", mutation)
	newTool:SetAttribute("Rarity", rarity)
	newTool:SetAttribute("Level", level or 1)
	newTool:SetAttribute("IsSpawnedItem", false)
 
	newTool.Grip = itemConf.Grip
 
	--local handle = Instance.new("Part")
	--handle.Name = "Handle"
	--handle.Transparency = 1
	--handle.Size = Vector3.new(1, 1, 1)
	--handle.CanCollide = false
	--handle.Massless = true
	--handle.Parent = newTool
 
	local model = itemTemplate:Clone()
	model.Name = "StackedItem"
	model:SetAttribute("OriginalName", itemName)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Level", level or 1)
	model:SetAttribute("IsSpawnedItem", false)
 
	--model:Destroy()
	--model:PivotTo(handle.CFrame)
 
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle
			w.Part1 = p
			w.Parent = p
		end
	end
 
	for _, child in ipairs(model:GetChildren()) do
		child.Parent = newTool
	end
	model.Parent = newTool
 
	newTool.Parent = player:WaitForChild("Backpack")
end
 
-- [ PICKUP LOGIC ] -----------------------------------------------------------
-- HGH
local function onItemPickedUp(player: Player, itemModel: Model)
	if not CarrySystem then 
		CarrySystem = require(
			ServerScriptService.Modules.CarrySystem
		) 
	end
	if not itemModel or not itemModel.Parent then return end
 
	local spawnerPart = itemModel.Parent 
 
	local name = itemModel:GetAttribute("OriginalName")
	local mutation = itemModel:GetAttribute("Mutation")
	local rarity = itemModel:GetAttribute("Rarity")
	local level = itemModel:GetAttribute("Level") or 1 
 
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
 
	if 
		spawnerPart.Name == "VIP" 
		and not (
			PlayerController:IsVIP(player)
			or PlayerController:IsSUPER_VIP(player) 
		) 
	then
		MarketplaceService:PromptGamePassPurchase(
			player,
			ProductsConfigurations.GamePasses.VIP
		)
		return
	elseif 
		spawnerPart.Name == "SUPER_VIP" 
		and not PlayerController:IsSUPER_VIP(player) 
	then
		MarketplaceService:PromptGamePassPurchase(
			player,
			ProductsConfigurations.GamePasses["SUPER VIP"]
		)
		return
	end
 
	if name and mutation and rarity and rootPart then
		local inZone = isInsideAnyZone(rootPart.Position)
		local pickedUp = false
 
		if inZone then
			local source = if spawnerPart:IsA("BasePart") then spawnerPart else nil
 
			if CarrySystem.CanCarryMore(player) then
				local success = CarrySystem.AddItemToCarry(player, name, mutation, rarity, source)
				if success then
					pickedUp = true
				end
			else
				local Events = ReplicatedStorage:FindFirstChild("Events")
				local notif = Events and Events:FindFirstChild("ShowNotification")
				if notif then notif:FireClient(player, "Carry limit reached!", "Error") end
			end
		else
			ItemManager.GiveItemToPlayer(player, name, mutation, rarity, level, false)
			pickedUp = true
		end
 
		if pickedUp then
			itemModel:Destroy()
		end
	end
end
 
-- [ SPAWNING LOGIC ]
 
function ItemManager.SpawnVisualItem(
	parentPart: BasePart, 
	itemName: string, 
	mutation: string, 
	rarity: string, 
	level: number, 
	player: Player?
)
	local mutationFolder = ItemsFolder:FindFirstChild(mutation) or ItemsFolder:FindFirstChild("Normal")
	local itemTemplate = mutationFolder:FindFirstChild(itemName) or ItemsFolder.Normal:FindFirstChild(itemName)
 
	if not itemTemplate then return end
	local itemConfig = ItemConfigurations.GetItemData(itemName)
 
	local model = itemTemplate:Clone() :: Model
	model.Name = "VisualItem"
	model:SetAttribute("OriginalName", itemName)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Level", level)
	model:SetAttribute("IsSpawnedItem", false)
 
	if itemConfig.PodiumSize then
		model:ScaleTo(itemConfig.PodiumSize)
	end
 
	local run = ItemConfigurations.GetItemAnimation(itemName, "Run")
	if run then
		applyAnimation(model, run)
	end
 
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true; part.CanCollide = false
		end
	end
 
	model:PivotTo(
		model:GetPivot() * ITEM_SPAWN_ORIENTATION_OFFSET
	)
	local offset = Vector3.new(
		0, 
		parentPart.Size.Y / 2 + getYSizeOfModelGlobal(model) / 2, 
		0
	)
	model:PivotTo(
		parentPart.CFrame * (itemConfig.PodiumOffset or CFrame.new(0, 0, 0)) * ITEM_SPAWN_ORIENTATION_OFFSET + offset
	)
	model.Parent = parentPart
 
	-- Pass rebirths and VIP status down
	setupItemGUI(
		model, 
		level, 
		player 
			and PlayerController:GetTotalMultiplier(player)
			or 1
	)
end
 
function ItemManager.SpawnOnSpawner(spawnerPart: BasePart) -- HGH
	if not spawnerPart or not spawnerPart.Parent then return end
 
	-- 1. Count how many items are currently on this spawner and log their positions
	local currentItems = 0
	local existingPositions = {}
	for _, child in ipairs(spawnerPart:GetChildren()) do
		if child.Name == "SpawnedItem" and child:IsA("Model") then
			currentItems += 1
			table.insert(existingPositions, child:GetPivot().Position)
		end
	end
 
	-- 2. Calculate how many items we need to spawn to reach the max
	local itemsToSpawn = MAX_ITEMS_PER_SPAWNER - currentItems
	if itemsToSpawn <= 0 then return end
 
	local tier = spawnerPart.Name 
	local rarity, isMutationsEnabled = getRarityFromTier(tier)
	local possibleItems = 
		ItemConfigurations.GetSpawnableItemsByRarity(rarity)
	--print(possibleItems)
	if #possibleItems == 0 then 
		return 
	end
 
	-- 3. Loop and spawn the missing items
	for i = 1, itemsToSpawn do
		local randomItemName = nil
		local mutationName = getMutation(
			isMutationsEnabled, 
			SPAWNER_TIERS[tier]
		)
		local itemTemplate = nil
 
		for j = 1, 5 do
			randomItemName = possibleItems[
				math.random(1, #possibleItems)
			]
			local mutationFolder = ItemsFolder:FindFirstChild(
				mutationName
			) or ItemsFolder.Normal
			itemTemplate = mutationFolder:FindFirstChild(
				randomItemName
			) or ItemsFolder.Normal:FindFirstChild(
				randomItemName
			)
 
			if itemTemplate then break end
		end
 
		if not itemTemplate then continue end
 
		local newItem = itemTemplate:Clone() :: Model
		newItem.Name = "SpawnedItem"
 
		-- ## ADDED: Tag so the Helicopter raycast ignores the item on the ground ##
		CollectionService:AddTag(newItem, "HelicopterIgnore")
 
		newItem:SetAttribute("IsSpawnedItem", true)
		newItem:SetAttribute("OriginalName", randomItemName)
		newItem:SetAttribute("Rarity", rarity)
		newItem:SetAttribute("Mutation", mutationName)
		newItem:SetAttribute("Level", 1)
 
		newItem:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + math.random(RECYCLE_MIN_TIME, RECYCLE_MAX_TIME))
 
		local idle = ItemConfigurations.GetItemAnimation(randomItemName, "Idle")
		if idle then
			applyAnimation(newItem, idle)
		end
 
		for _, part in ipairs(newItem:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Anchored = true
			end
		end
 
		newItem:PivotTo(
			newItem:GetPivot() * ITEM_SPAWN_ORIENTATION_OFFSET
		)
 
		local sizeY = getYSizeOfModelGlobal(newItem)
		local distToBottom = newItem:GetPivot().Position.Y - (newItem:GetBoundingBox().Position.Y - (sizeY / 2))
 
		-- [[ ADDED: Smart Spawning Logic ]]
		local maxAttempts = 15
		local spawnCFrame
		local randomRot = getRandomUpVectorRotation(newItem)
 
		for attempt = 1, maxAttempts do
			-- Calculate a random position on the surface of the spawner part
			local randomX = (math.random() - 0.5) * (spawnerPart.Size.X * 0.8)
			local randomZ = (math.random() - 0.5) * (spawnerPart.Size.Z * 0.8)
			spawnCFrame = spawnerPart.CFrame * CFrame.new(randomX, spawnerPart.Size.Y/2, randomZ)
 
			-- Check if it's too close to an existing item
			local tooClose = false
			for _, pos in ipairs(existingPositions) do
				-- We use Vector2 to ignore height differences and only check the floor plane
				local dist = Vector2.new(spawnCFrame.Position.X - pos.X, spawnCFrame.Position.Z - pos.Z).Magnitude
				if dist < MIN_ITEM_SPACING then
					tooClose = true
					break
				end
			end
 
			-- If it passed the distance check, we break the loop and use this spot
			if not tooClose then break end
		end
 
		-- Log this new position so the NEXT item in the loop avoids it too
		if spawnCFrame then
			table.insert(existingPositions, spawnCFrame.Position)
 
			newItem:PivotTo(
				spawnCFrame 
					* ITEM_SPAWN_ORIENTATION_OFFSET
					* randomRot 
					+ Vector3.new(0, distToBottom, 0)
			)
			newItem.Parent = spawnerPart
 
			-- Spawners generally show base stats (0 rebirths)
			setupItemGUI(
				newItem, 
				1, 
				1
			)
 
			if newItem.PrimaryPart then
				local prompt = Instance.new("ProximityPrompt")
				prompt.ObjectText = randomItemName
				prompt.ActionText = "Pick Up"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false 
				prompt.HoldDuration = 0
				prompt.Name = "OBJECT_PICKUP"
				prompt.MaxActivationDistance = 16
				prompt.Style = Enum.ProximityPromptStyle.Custom
				prompt.Parent = newItem.PrimaryPart
 
				prompt.Triggered:Connect(function(player)
					onItemPickedUp(player, newItem)
				end)
			end
 
			local expireTime = newItem:GetAttribute("ExpiresAt")
			local lifetime = expireTime - Workspace:GetServerTimeNow()
 
			-- Recycle logic: Despawn and replace if not picked up
			task.delay(lifetime, function()
				if newItem and newItem.Parent then
					newItem:Destroy()
					ItemManager.SpawnOnSpawner(spawnerPart)
				end
			end)
		end
	end
end
 
function ItemManager.SpawnDroppedItem(itemName: string, mutation: string, rarity: string, targetPos: Vector3, originPos: Vector3?)
	local mutationFolder = ItemsFolder:FindFirstChild(mutation) or ItemsFolder.Normal
	local itemTemplate = mutationFolder:FindFirstChild(itemName) or ItemsFolder.Normal:FindFirstChild(itemName)
 
	if not itemTemplate then return end
 
	local newItem = itemTemplate:Clone() :: Model
	newItem.Name = "SpawnedItem"
 
	-- ## ADDED: Tag so the Helicopter raycast ignores the dropped item ##
	CollectionService:AddTag(newItem, "HelicopterIgnore")
 
	newItem:SetAttribute("IsSpawnedItem", true)
	newItem:SetAttribute("OriginalName", itemName)
	newItem:SetAttribute("Mutation", mutation)
	newItem:SetAttribute("Rarity", rarity)
	newItem:SetAttribute("Level", 1)
 
	newItem:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + DROPPED_LIFETIME)
 
	for _, part in ipairs(newItem:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = true
		end
	end
 
	local rayOrigin = targetPos + Vector3.new(0, 5, 0)
	local rayDirection = Vector3.new(0, -20, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {newItem}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
 
	local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local floorY = result and result.Position.Y or targetPos.Y
 
	local itemExtents = newItem:GetExtentsSize()
	local distToBottom = newItem:GetPivot().Position.Y - (newItem:GetBoundingBox().Position.Y - (itemExtents.Y / 2))
 
	local finalCFrame = CFrame.new(targetPos.X, floorY + distToBottom, targetPos.Z) * ITEM_SPAWN_ORIENTATION_OFFSET * CFrame.Angles(0, math.random(0,360), 0)
 
	newItem.Parent = ItemSpawnsFolder
 
	if originPos then
		newItem:PivotTo(
			CFrame.new(originPos) * ITEM_SPAWN_ORIENTATION_OFFSET
		)
 
		local cfValue = Instance.new("CFrameValue")
		cfValue.Value = CFrame.new(originPos) * ITEM_SPAWN_ORIENTATION_OFFSET
		cfValue.Parent = newItem 
 
		cfValue.Changed:Connect(function(val)
			if newItem.Parent then
				newItem:PivotTo(val)
			end
		end)
 
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(cfValue, tweenInfo, {Value = finalCFrame})
		tween:Play()
 
		tween.Completed:Connect(function()
			cfValue:Destroy()
		end)
	else
		newItem:PivotTo(finalCFrame)
	end
 
	-- Dropped items show base stats
	setupItemGUI(
		newItem, 
		1, 
		1
	)
 
	if newItem.PrimaryPart then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = itemName
		prompt.ActionText = "Pick Up"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false 
		prompt.HoldDuration = 1
		prompt.MaxActivationDistance = 16
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Parent = newItem.PrimaryPart
 
		prompt.Triggered:Connect(function(player)
			onItemPickedUp(player, newItem)
		end)
	end
 
	local lifetime = DROPPED_LIFETIME
	task.delay(lifetime, function()
		if newItem and newItem.Parent then
			newItem:Destroy()
		end
	end)
end
 
function ItemManager.RespawnItem(spawnerPart: BasePart)
	task.delay(RESPAWN_TIME, function()
		ItemManager.SpawnOnSpawner(spawnerPart)
	end)
end
 
function ItemManager.SpawnAllItems()
	for _, spawner in ipairs(ItemSpawnsFolder:GetChildren()) do
		if spawner:IsA("BasePart") then
			ItemManager.SpawnOnSpawner(spawner)
		end
	end
end
 
Players.PlayerAdded:Connect(function(player)
	ItemManager.SpawnAllItems()
end)
 
return ItemManager