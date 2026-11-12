-- Suspeitos: NPCs criminosos com estados (fugindo, lutando, rendido, algemado, escoltado, fichado, preso).
-- Suspects.Create(nome, CFrame, opts) -> rec     Suspects.Cuff(rec, player)    Suspects.Escort(rec, player, ligado)
-- Suspects.Stun(rec, seg, player)  Suspects.Hit(rec, dano, player)  Suspects.Surrender(rec)  Suspects.Remove(rec)
-- Suspects.InCone(origem, direcao, alcance, graus) -> lista   Suspects.All()
-- opts: shirt, pants, skin, role, tagColor, speed, hostile, armed, hp, behavior ("stand"|"flee"|"fight"|"hide"),
--       crime, fine, cuffable (permite algemar parado), route (lista de Vector3 para fugir), skittish, loot
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Suspects = {}
local ctx
local list = {}
local byModel = {}

local DOWN = { surrender = true, cuffed = true, escorted = true, booked = true, jailed = true }

local function cfg() return ctx.Config.Suspects end

-- ===== poses (mexe nos ombros; C0 replica para todos) =====
-- Só juntas Motor6D. A pose é apenas visual: se o rig não permitir alterar C0 (em alguns rigs gerados pela
-- engine a propriedade é somente leitura), a pose é ignorada e a ação (render, algemar) continua normalmente.
local function shoulders(model)
	local function find(...)
		for _, nome in ipairs({ ... }) do
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == nome and d:IsA("Motor6D") then return d end
			end
		end
		return nil
	end
	return find("RightShoulder", "Right Shoulder"), find("LeftShoulder", "Left Shoulder")
end

local function pose(rec, kind)
	if rec.NoPose then return end
	local r, l = shoulders(rec.Model)
	if not r or not l then rec.NoPose = true return end
	local ok = pcall(function()
		if not rec.C0 then rec.C0 = { r = r.C0, l = l.C0 } end
		if kind == "handsup" then
			r.C0 = rec.C0.r * CFrame.Angles(0, 0, math.rad(165))
			l.C0 = rec.C0.l * CFrame.Angles(0, 0, -math.rad(165))
		elseif kind == "cuffed" then
			r.C0 = rec.C0.r * CFrame.Angles(math.rad(25), 0, math.rad(8))
			l.C0 = rec.C0.l * CFrame.Angles(math.rad(25), 0, -math.rad(8))
		else
			r.C0 = rec.C0.r
			l.C0 = rec.C0.l
		end
	end)
	if not ok then rec.NoPose = true end
end

-- ===== etiqueta de estado =====
local LABEL = {
	surrender = { "RENDIDO", Color3.fromRGB(255, 200, 50) },
	stunned = { "ATORDOADO", Color3.fromRGB(255, 200, 50) },
	cuffed = { "ALGEMADO", Color3.fromRGB(90, 255, 140) },
	escorted = { "EM ESCOLTA", Color3.fromRGB(90, 255, 140) },
	booked = { "FICHADO", Color3.fromRGB(80, 190, 255) },
	jailed = { "PRESO", Color3.fromRGB(80, 190, 255) },
}

local function refresh(rec)
	local st = rec.State
	if rec.CuffPrompt then
		rec.CuffPrompt.Enabled = (st == "surrender" or st == "stunned" or (st == "idle" and rec.Cuffable == true)) and rec.Alive
	end
	if rec.EscortPrompt then
		rec.EscortPrompt.Enabled = (st == "cuffed" or st == "escorted") and rec.Alive
		rec.EscortPrompt.ActionText = st == "escorted" and "Soltar" or "Escoltar"
	end
	if rec.SearchPrompt then
		rec.SearchPrompt.Enabled = (st == "cuffed" or st == "escorted") and not rec.Searched and rec.Alive
	end
	local head = rec.Model:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("Tag")
	local label = tag and tag:FindFirstChildOfClass("TextLabel")
	if label then
		local info = LABEL[st]
		local base = rec.Name .. (rec.Role and ("\n" .. rec.Role) or "")
		if info then
			label.Text = base .. "\n[" .. info[1] .. "]"
			label.TextColor3 = info[2]
		else
			label.Text = base
		end
	end
	rec.Model:SetAttribute("EstadoSuspeito", st)
end

local function setState(rec, st)
	if rec.State == st then return end
	rec.State = st
	refresh(rec)
	ctx.Bus.Fire("SuspectState", rec, st)
end

local function say(rec, text, secs)
	if rec.Model.Parent then ctx.Systems.Npc.Say(rec.Model, text, secs or 3) end
end
Suspects.Say = say

-- ===== consultas =====
function Suspects.All() return list end
function Suspects.OfModel(m) return byModel[m] end

function Suspects.Nearest(pos, radius, pred)
	local best, bd = nil, radius or math.huge
	for _, rec in ipairs(list) do
		if rec.Alive and rec.Root.Parent and (not pred or pred(rec)) then
			local d = (rec.Root.Position - pos).Magnitude
			if d < bd then best, bd = rec, d end
		end
	end
	return best, bd
end

function Suspects.InCone(origin, dir, range, degrees)
	local out = {}
	local minDot = math.cos(math.rad(degrees))
	for _, rec in ipairs(list) do
		if rec.Alive and rec.Root.Parent then
			local v = rec.Root.Position - origin
			local d = v.Magnitude
			if d <= range and d > 0.1 and v.Unit:Dot(dir) >= minDot then table.insert(out, { rec, d }) end
		end
	end
	table.sort(out, function(a, b) return a[2] < b[2] end)
	local res = {}
	for _, e in ipairs(out) do table.insert(res, e[1]) end
	return res
end

-- ===== ações =====
function Suspects.Surrender(rec)
	if not rec.Alive or DOWN[rec.State] then return end
	rec.Hum.WalkSpeed = 0
	rec.Hum:MoveTo(rec.Root.Position)
	pose(rec, "handsup")
	setState(rec, "surrender")
	say(rec, "Tá bom, tá bom! Me rendo!", 3.5)
end

function Suspects.Stun(rec, seconds, player)
	if not rec.Alive or not rec.Root.Parent then return false end
	if DOWN[rec.State] and rec.State ~= "surrender" then
		if player then
			ctx.Systems.Rank.AddXP(player, -ctx.Config.Weapons.ExcessiveForcePenalty, "força excessiva")
			ctx.Systems.Rank.Conduct(player, -10)
			ctx.Systems.Radio.Notify("danger", "Uso excessivo de força contra suspeito rendido!", player)
		end
		return false
	end
	local prev = rec.State
	setState(rec, "stunned")
	ctx.Systems.Npc.Stun(rec.Model, seconds)
	rec.StunUntil = os.clock() + seconds
	task.delay(seconds + 0.1, function()
		if rec.Alive and rec.State == "stunned" and rec.Model.Parent then
			if rec.HP <= rec.MaxHP * cfg().SurrenderHP then
				setState(rec, "idle")
				Suspects.Surrender(rec)
			else
				setState(rec, prev == "stunned" and "idle" or prev)
			end
		end
	end)
	ctx.Bus.Fire("SuspectStunned", rec, player)
	return true
end

function Suspects.Hit(rec, damage, player)
	if not rec.Alive or not rec.Root.Parent then return false end
	if DOWN[rec.State] or (not rec.Hostile and not rec.Armed and rec.Behavior ~= "flee" and rec.Behavior ~= "fight") then
		if player then
			ctx.Systems.Rank.AddXP(player, -ctx.Config.Weapons.ExcessiveForcePenalty, "força excessiva")
			ctx.Systems.Rank.Conduct(player, -10)
			ctx.Systems.Radio.Notify("danger", "Uso excessivo de força! Conduta reduzida.", player)
		end
		return false
	end
	rec.HP = math.max(1, rec.HP - damage)
	rec.Model:SetAttribute("Vida", rec.HP)
	local h = Instance.new("Highlight")
	h.FillColor = Color3.fromRGB(255, 60, 60)
	h.FillTransparency = 0.5
	h.OutlineTransparency = 1
	h.Parent = rec.Model
	game:GetService("Debris"):AddItem(h, 0.15)
	if rec.HP <= rec.MaxHP * cfg().SurrenderHP then Suspects.Surrender(rec) end
	ctx.Bus.Fire("SuspectHit", rec, player, damage)
	return true
end

function Suspects.Cuff(rec, player)
	if not rec.Alive or rec.State == "cuffed" or rec.State == "escorted" or rec.State == "booked" or rec.State == "jailed" then return false end
	rec.Hum.WalkSpeed = 0
	rec.Hum.PlatformStand = false
	rec.Hum:MoveTo(rec.Root.Position)
	pose(rec, "cuffed")
	rec.Hostile = false
	rec.CuffedBy = player
	setState(rec, "cuffed")
	ctx.Util.PlaySound(rec.Root, ctx.Config.Sounds.Cuff, { Volume = 0.8, Range = 60 })
	say(rec, "Eu tenho direitos!", 3)
	if player then
		ctx.Util.Pay(player, ctx.Config.Rewards.Cuff)
		ctx.Systems.Rank.AddXP(player, 6, "algemar")
		ctx.Systems.Radio.Popup(player, "+" .. ctx.Util.Money(ctx.Config.Rewards.Cuff), "success")
	end
	ctx.Bus.Fire("SuspectCuffed", rec, player)
	return true
end

function Suspects.Escort(rec, player, on)
	if not rec.Alive then return end
	if not on then
		rec.Escort = nil
		if rec.State == "escorted" then
			rec.Hum.WalkSpeed = 0
			rec.Hum:MoveTo(rec.Root.Position)
			setState(rec, "cuffed")
		end
		return
	end
	if rec.State ~= "cuffed" then return end
	rec.Escort = player
	rec.Hum.WalkSpeed = cfg().EscortSpeed
	setState(rec, "escorted")
	ctx.Bus.Fire("SuspectEscort", rec, player)
	task.spawn(function()
		local lastPos, stuck = rec.Root.Position, 0
		while rec.Alive and rec.Escort == player and rec.State == "escorted" and rec.Model.Parent do
			local pr = ctx.Util.Root(player)
			if not pr or not ctx.Util.Alive(player) then
				Suspects.Escort(rec, player, false)
				break
			end
			local d = (pr.Position - rec.Root.Position).Magnitude
			if d > cfg().EscortLeash then
				ctx.Systems.Radio.Notify("warn", "Você perdeu o preso de vista. Ele foi liberado da escolta.", player)
				Suspects.Escort(rec, player, false)
				break
			end
			if d > 5 then
				local target = pr.Position - pr.CFrame.LookVector * 4
				rec.Hum:MoveTo(target)
				if (rec.Root.Position - lastPos).Magnitude < 0.4 then stuck += 1 else stuck = 0 end
				lastPos = rec.Root.Position
				if stuck >= 12 and d > 10 then
					rec.Model:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
					stuck = 0
				elseif stuck >= 4 then
					rec.Hum.Jump = true
				end
			else
				rec.Hum:MoveTo(rec.Root.Position)
			end
			task.wait(0.25)
		end
	end)
end

function Suspects.Book(rec) setState(rec, "booked") end
function Suspects.Jail(rec)
	rec.Escort = nil
	setState(rec, "jailed")
end

function Suspects.SetState(rec, st)
	setState(rec, st)
	refresh(rec)
end
Suspects.Refresh = refresh

function Suspects.Remove(rec)
	if not rec then return end
	rec.Alive = false
	rec.Escort = nil
	local i = table.find(list, rec)
	if i then table.remove(list, i) end
	if rec.Model then
		byModel[rec.Model] = nil
		if rec.Model.Parent then rec.Model:Destroy() end
	end
end

function Suspects.RemoveAll(filter)
	for i = #list, 1, -1 do
		local rec = list[i]
		if not filter or filter(rec) then Suspects.Remove(rec) end
	end
end

-- ===== IA =====
local function nearestThreat(rec, radius)
	local best, bd = nil, radius
	for _, p in ipairs(Players:GetPlayers()) do
		local r = ctx.Util.Root(p)
		if r and ctx.Util.Alive(p) then
			local d = (r.Position - rec.Root.Position).Magnitude
			if d < bd then best, bd = p, d end
		end
	end
	return best, bd
end

local function ai(rec)
	local hitAt = 0
	while rec.Alive and rec.Model.Parent do
		task.wait(0.25)
		if not rec.Root.Parent then break end
		local st = rec.State
		if st == "idle" or st == "flee" or st == "fight" then
			local behavior = rec.Behavior
			if st == "idle" and rec.Skittish then
				local _, d = nearestThreat(rec, 11)
				if d and d < 11 then
					rec.Behavior = "flee"
					behavior = "flee"
					say(rec, "Não chega perto!", 2.5)
				end
			end
			if behavior == "fight" then
				local p, d = nearestThreat(rec, rec.ChaseRange or 55)
				if p then
					local pr = ctx.Util.Root(p)
					if d > (rec.FightRange or 4.8) then
						rec.Hum.WalkSpeed = rec.Speed
						rec.Hum:MoveTo(pr.Position)
						rec.State = "fight"
					else
						rec.Hum:MoveTo(rec.Root.Position)
						if os.clock() - hitAt > 1.1 then
							hitAt = os.clock()
							local ph = ctx.Util.Humanoid(p)
							if ph and ph.Health > 0 then ph:TakeDamage(rec.FightDamage or 6) end
							ctx.Util.PlaySound(rec.Root, ctx.Config.Sounds.Baton, { Volume = 0.5, Range = 40 })
						end
					end
				else
					rec.Hum:MoveTo(rec.Root.Position)
				end
			elseif behavior == "flee" and not rec.RouteBusy then
				if rec.Route and #rec.Route > 0 then
					rec.RouteBusy = true
					task.spawn(function()
						for _, wp in ipairs(rec.Route) do
							if not rec.Alive or rec.State == "stunned" or DOWN[rec.State] then break end
							rec.Hum.WalkSpeed = rec.Speed
							local ok = ctx.Systems.Npc.WalkTo(rec.Model, wp, 14)
							while rec.Alive and rec.State == "stunned" do task.wait(0.2) end
							if DOWN[rec.State] then break end
							if rec.OnWaypoint then pcall(rec.OnWaypoint, rec, wp, ok) end
						end
						rec.RouteBusy = false
						if rec.OnRouteEnd and rec.Alive and not DOWN[rec.State] then pcall(rec.OnRouteEnd, rec) end
					end)
				else
					local p, d = nearestThreat(rec, 40)
					if p then
						local pr = ctx.Util.Root(p)
						local away = (rec.Root.Position - pr.Position) * Vector3.new(1, 0, 1)
						if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
						rec.Hum.WalkSpeed = rec.Speed
						rec.Hum:MoveTo(rec.Root.Position + away.Unit * 30)
					end
				end
			end
		elseif st == "stunned" and rec.StunUntil and os.clock() > rec.StunUntil + 1 and not rec.Model:GetAttribute("Preso") then
			-- segurança: nunca fica atordoado para sempre
			setState(rec, "idle")
		end
	end
end

-- ===== criação =====
function Suspects.Create(name, cf, opts)
	opts = opts or {}
	local model = ctx.Systems.Npc.Create(name, cf, {
		shirt = opts.shirt or Color3.fromRGB(60, 60, 70), pants = opts.pants or Color3.fromRGB(35, 35, 45),
		skin = opts.skin, speed = opts.speed or cfg().WalkSpeed,
		role = opts.role, tagColor = opts.tagColor or Color3.fromRGB(255, 90, 80),
	})
	if not model then return nil end
	local rec = {
		Model = model, Root = model:FindFirstChild("HumanoidRootPart"), Hum = model:FindFirstChildOfClass("Humanoid"),
		Name = name, Role = opts.role, State = "idle", Alive = true, Hostile = opts.hostile == true, Armed = opts.armed == true,
		HP = opts.hp or 100, MaxHP = opts.hp or 100, Behavior = opts.behavior or "stand", Speed = opts.speed or cfg().RunSpeed,
		Crime = opts.crime, Fine = opts.fine or 0, Cuffable = opts.cuffable == true, Route = opts.route, Skittish = opts.skittish == true,
		Loot = opts.loot, FightDamage = opts.fightDamage, Searched = false, Booked = false, Data = {},
		OnWaypoint = opts.onWaypoint, OnRouteEnd = opts.onRouteEnd,
	}
	model:SetAttribute("Suspeito", true)
	model:SetAttribute("Hostil", rec.Hostile)
	CollectionService:AddTag(model, "DelegaciaSuspeito")
	rec.Hum.Died:Connect(function()
		rec.Alive = false
		ctx.Bus.Fire("SuspectDied", rec)
	end)

	-- prompts
	rec.CuffPrompt = ctx.Util.Prompt(rec.Root, "Algemar", name, cfg().CuffHold, Enum.KeyCode.E, ctx.Config.Weapons.Cuffs.Range)
	rec.CuffPrompt.Name = "PromptAlgemar"
	rec.CuffPrompt.Triggered:Connect(function(player)
		if not ctx.Util.OnDuty(player) then ctx.Systems.Radio.Notify("warn", "Entre em serviço para efetuar prisões.", player) return end
		if not ctx.Systems.Tools.Holding(player, "algemas") then
			ctx.Systems.Radio.Notify("warn", "Equipe as ALGEMAS para prender o suspeito.", player)
			return
		end
		Suspects.Cuff(rec, player)
	end)
	rec.EscortPrompt = ctx.Util.Prompt(rec.Root, "Escoltar", name, 0.4, Enum.KeyCode.F, 8)
	rec.EscortPrompt.Name = "PromptEscolta"
	rec.EscortPrompt.Triggered:Connect(function(player)
		if not ctx.Util.OnDuty(player) then return end
		if rec.State == "escorted" then
			if rec.Escort == player then Suspects.Escort(rec, player, false) end
		elseif rec.State == "cuffed" then
			Suspects.Escort(rec, player, true)
		end
	end)
	rec.SearchPrompt = ctx.Util.Prompt(rec.Root, "Revistar", name, cfg().SearchHold, Enum.KeyCode.G, 8)
	rec.SearchPrompt.Name = "PromptRevista"
	rec.SearchPrompt.Triggered:Connect(function(player)
		if rec.Searched or not ctx.Util.OnDuty(player) then return end
		rec.Searched = true
		refresh(rec)
		if rec.Loot then
			pcall(rec.Loot, rec, player)
		else
			ctx.Systems.Radio.Notify("info", "Revista concluída: nada de ilegal com " .. rec.Name .. ".", player)
		end
		ctx.Bus.Fire("SuspectSearched", rec, player)
	end)

	table.insert(list, rec)
	byModel[model] = rec
	refresh(rec)
	task.spawn(ai, rec)
	return rec
end

function Suspects.Init(c)
	ctx = c
end

return Suspects
