-- Incêndios: focos, dano por proximidade e extintor.
local Players = game:GetService("Players")
local Fire = {}
local ctx, cfg
local active = {}   -- [spot] = { fire, smoke, light, health }
local count = 0

local function refresh()
	ctx.Systems.Alarm.Set("fire", count > 0)
	ctx.State.Set("Fires", count)
end

local function ignite(spot)
	if active[spot] then return false end
	local f = Instance.new("Fire")
	f.Size = 9
	f.Heat = 10
	f.Color = Color3.fromRGB(255, 150, 30)
	f.SecondaryColor = Color3.fromRGB(255, 70, 0)
	f.Parent = spot
	local s = Instance.new("Smoke")
	s.Size = 12
	s.RiseVelocity = 9
	s.Opacity = 0.5
	s.Color = Color3.fromRGB(40, 40, 40)
	s.Parent = spot
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 140, 50)
	l.Range = 26
	l.Brightness = 2.5
	l.Shadows = false
	l.Parent = spot
	local snd = ctx.Util.PlaySound(spot, ctx.Config.Sounds.FireLoop, { Looped = true, Volume = 0.5, Range = 80 })
	active[spot] = { fire = f, smoke = s, light = l, sound = snd, health = 100 }
	count += 1
	refresh()
	return true
end

local function putOut(spot, player)
	local d = active[spot]
	if not d then return end
	d.fire:Destroy() d.smoke:Destroy() d.light:Destroy()
	if d.sound then d.sound:Destroy() end
	active[spot] = nil
	count -= 1
	refresh()
	if player then ctx.Util.Pay(player, ctx.Config.Rewards.FireOut, "fogo") end
	ctx.Bus.Fire("FireOut", player, spot)
end

function Fire.Count() return count end

function Fire.Spawn(n)
	local free = {}
	for _, o in ipairs(ctx.Objects:GetChildren()) do
		if o.Name:match("^FireSpot_") and not active[o] then table.insert(free, o) end
	end
	local made = 0
	while made < n and #free > 0 do
		local i = math.random(1, #free)
		if ignite(free[i]) then made += 1 end
		table.remove(free, i)
	end
	if made > 0 then ctx.Systems.Radio.Notify("danger", "INCÊNDIO detectado na plataforma!") end
	return made
end

function Fire.ExtinguishAll()
	for spot in pairs(table.clone(active)) do putOut(spot, nil) end
end

local function hook(tool, player)
	local last = 0
	tool.Activated:Connect(function()
		local now = os.clock()
		if now - last < 0.25 then return end
		last = now
		local char = tool.Parent
		local handle = tool:FindFirstChild("Handle")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not handle or not root then return end
		local spray = handle:FindFirstChild("Spray")
		if spray then spray:Emit(12) end
		ctx.Util.PlaySound(handle, ctx.Config.Sounds.Extinguisher, { Volume = 0.5 })
		for spot, d in pairs(table.clone(active)) do
			local to = spot.Position - root.Position
			if to.Magnitude <= cfg.ExtinguishRange and to.Unit:Dot(root.CFrame.LookVector) > 0.25 then
				d.health -= cfg.HitPower
				d.fire.Size = 3 + math.max(d.health, 0) / 100 * 6
				if d.health <= 0 then putOut(spot, player) end
			end
		end
	end)
end

local function giveExtinguisher(player)
	local bp = player:FindFirstChildOfClass("Backpack")
	local char = player.Character
	if (bp and bp:FindFirstChild("Extintor")) or (char and char:FindFirstChild("Extintor")) then
		ctx.Systems.Radio.Notify("info", "Você já está com o extintor.", player)
		return
	end
	local tool = ctx.Util.PrepareTool(ctx.Rig.Tools.Extintor:Clone())
	local handle = tool:FindFirstChild("Handle")
	if handle and not handle:FindFirstChild("Spray") then
		local e = Instance.new("ParticleEmitter")
		e.Name = "Spray"
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.4, 0.8)
		e.Speed = NumberRange.new(18, 26)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.5) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(Color3.fromRGB(245, 245, 250))
		e.EmissionDirection = Enum.NormalId.Front
		e.Parent = handle
	end
	hook(tool, player)
	tool.Parent = bp
	ctx.Systems.Radio.Notify("success", "Extintor equipado.", player)
end

function Fire.Init(c)
	ctx = c
	cfg = ctx.Config.Fire
	local locker = ctx.Objects:FindFirstChild("Locker")
	if locker then
		local pp = ctx.Util.Prompt(locker, "Pegar extintor", "Armário de emergência", 0.6)
		pp.Triggered:Connect(giveExtinguisher)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			if count > 0 then
				for spot in pairs(active) do
					for _, p in ipairs(ctx.Util.PlayersNear(spot.Position, cfg.DamageRadius)) do
						local h = ctx.Util.Humanoid(p)
						if h and h.Health > 0 then h:TakeDamage(cfg.Damage) end
					end
				end
			end
		end
	end)
end

return Fire
