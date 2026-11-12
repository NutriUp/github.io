-- Logística de carga: barris, caixas de suprimento e doca de entrega.
local Cargo = {}
local ctx, cfg
local world = {}     -- [part] = kind
local carried = {}   -- [tool] = kind (Tools de carga entregues aos jogadores)
local dock

local function carrying(player)
	local bp = player:FindFirstChildOfClass("Backpack")
	local char = player.Character
	for _, name in ipairs({ "Barril", "Caixa de Suprimentos" }) do
		local t = (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
		if t then return t end
	end
end

local function giveTool(player, kind)
	if carrying(player) then
		ctx.Systems.Radio.Notify("warn", "Você já está carregando algo.", player)
		return false
	end
	local template = ctx.Rig.Tools:FindFirstChild(kind)
	if not template then return false end
	local tool = ctx.Util.PrepareTool(template:Clone())
	tool.Equipped:Connect(function()
		local h = tool.Parent and tool.Parent:FindFirstChildOfClass("Humanoid")
		if h then h.WalkSpeed = cfg.CarrySpeed end
	end)
	tool.Unequipped:Connect(function()
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then h.WalkSpeed = cfg.NormalSpeed end
	end)
	tool.Destroying:Connect(function()
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then h.WalkSpeed = cfg.NormalSpeed end
	end)
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then tool:Destroy() return false end
	carried[tool] = kind == "Barril" and "Barril" or "Suprimento"
	tool.Destroying:Connect(function() carried[tool] = nil end)
	tool.Parent = bp
	return true
end

local function makeProp(kind, cf)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "Barril" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(3.2, 2.4, 2.4)
		p.Color = Color3.fromRGB(215, 95, 25)
		p.Material = Enum.Material.Metal
		p.CFrame = cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.pi / 2)
		for _, y in ipairs({ -0.9, 0.9 }) do
			local band = Instance.new("Part")
			band.Shape = Enum.PartType.Cylinder
			band.Size = Vector3.new(0.25, 2.5, 2.5)
			band.Color = Color3.fromRGB(40, 40, 40)
			band.Material = Enum.Material.Metal
			band.Anchored = true
			band.CanCollide = false
			band.CFrame = p.CFrame * CFrame.new(y, 0, 0)
			band.Parent = p
		end
	else
		p.Size = Vector3.new(3, 2.4, 3)
		p.Color = Color3.fromRGB(70, 110, 60)
		p.Material = Enum.Material.DiamondPlate
		p.CFrame = cf * CFrame.new(0, 1.3, 0)
	end
	p.Name = kind .. "_Prop"
	local pp = ctx.Util.Prompt(p, "Pegar", kind == "Barril" and "Barril de petróleo" or "Caixa de suprimentos", 0.4)
	pp.Triggered:Connect(function(player)
		if not world[p] then return end
		if giveTool(player, kind == "Barril" and "Barril" or "Caixa de Suprimentos") then
			world[p] = nil
			p:Destroy()
			ctx.Util.PlaySound(ctx.Util.Root(player), ctx.Config.Sounds.CargoPickup, { Volume = 0.6 })
			ctx.Bus.Fire("CargoPicked", player, kind)
		end
	end)
	world[p] = kind
	p.Parent = workspace
	return p
end

function Cargo.SpawnBarrels(n)
	local free = {}
	for _, o in ipairs(ctx.Objects:GetChildren()) do
		if o.Name:match("^BarrelSpawn_") then table.insert(free, o) end
	end
	local made = 0
	while made < n and #free > 0 do
		local i = math.random(1, #free)
		makeProp("Barril", free[i].CFrame * CFrame.new(0, -free[i].Size.Y / 2, 0))
		table.remove(free, i)
		made += 1
	end
	return made
end

function Cargo.SpawnCrates(n)
	local free = {}
	for _, o in ipairs(ctx.Objects:GetChildren()) do
		if o.Name:match("^CrateSpawn_") then table.insert(free, o) end
	end
	local made = 0
	while made < n and #free > 0 do
		local i = math.random(1, #free)
		makeProp("Suprimento", free[i].CFrame * CFrame.new(0, -free[i].Size.Y / 2, 0))
		table.remove(free, i)
		made += 1
	end
	return made
end

function Cargo.Clear(kind)
	for p, k in pairs(table.clone(world)) do
		if not kind or k == kind then
			world[p] = nil
			p:Destroy()
		end
	end
	-- também recolhe as Tools carregadas (mochila, mão ou largadas no chão); Destroying restaura a velocidade
	for tool, k in pairs(table.clone(carried)) do
		if not kind or k == kind then
			carried[tool] = nil
			tool:Destroy()
		end
	end
end

function Cargo.Init(c)
	ctx = c
	cfg = ctx.Config.Cargo
	dock = ctx.Objects:FindFirstChild("DockPad")
	if not dock then warn("[OilRig] DockPad ausente") return end
	local pp = ctx.Util.Prompt(dock, "Entregar carga", "Doca de carregamento", 0.3)
	pp.MaxActivationDistance = 14
	pp.Triggered:Connect(function(player)
		local tool = carrying(player)
		if not tool then
			ctx.Systems.Radio.Notify("warn", "Você não está carregando nada.", player)
			return
		end
		local kind = tool.Name == "Barril" and "Barril" or "Suprimento"
		tool:Destroy()
		local reward = kind == "Barril" and ctx.Config.Rewards.Barrel or ctx.Config.Rewards.Supply
		local paid = ctx.Util.Pay(player, reward, "carga:" .. kind)
		ctx.Util.PlaySound(dock, ctx.Config.Sounds.CargoDeliver, { Volume = 0.7 })
		ctx.State.Set("Delivered", (ctx.State.Get("Delivered") or 0) + 1)
		ctx.Systems.Radio.Notify("success", (paid > 0 and ("+" .. paid .. " • ") or "") .. "carga entregue", player)
		if ctx.Systems.Crane then ctx.Systems.Crane.Flourish() end
		ctx.Bus.Fire("CargoDelivered", player, kind)
	end)
	ctx.State.Set("Delivered", 0)
end

return Cargo
