-- Frota: central de viaturas. Traz a FEDERAL CAR para a baia, devolve para a garagem e recolhe viaturas abandonadas.
-- Peças: FleetTerminal, Vehicle_Spawn_N (orientação da baia = CFrame da peça)
local Fleet = {}
local ctx
local cars = {}

local function occupied(car)
	for _, d in ipairs(car:GetDescendants()) do
		if (d:IsA("Seat") or d:IsA("VehicleSeat")) and d.Occupant then return true end
	end
	return false
end

-- Referência real do carro: o DriveSeat (acompanha a física). Model:GetPivot() NÃO serve aqui: sem
-- PrimaryPart, o WorldPivot fica parado onde o carro estava no Studio e não acompanha o carro quando ele
-- anda ou quando o A-Chassis o inicializa. Mover pelo pivô velho deslocava a viatura para fora da baia,
-- inclusive para baixo do piso.
local function seatOf(car)
	local s = car:FindFirstChild("DriveSeat", true)
	if s and s:IsA("BasePart") then return s end
	return car:FindFirstChildWhichIsA("VehicleSeat", true) or car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart", true)
end

local function carPos(car)
	local s = seatOf(car)
	return s and s.Position or car:GetPivot().Position
end

-- move o carro inteiro (todas as peças, mantendo a forma) para que o assento fique em "seatCF"
local function moveCar(car, seatCF)
	local seat = seatOf(car)
	if not seat then return end
	local t = seatCF * seat.CFrame:Inverse()
	local parts, cfs = {}, {}
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(cfs, t * d.CFrame)
		end
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	pcall(function() car.WorldPivot = t * car:GetPivot() end)
end

-- ponto mais baixo do carro no espaço do assento (y negativo = abaixo do assento)
local function bottomBelowSeat(car)
	local seat = seatOf(car)
	local ref = seat.CFrame
	local minY = 0
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.CanCollide then
			local c = ref:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			local ey = math.abs(c.RightVector.Y) * h.X + math.abs(c.UpVector.Y) * h.Y + math.abs(c.LookVector.Y) * h.Z
			minY = math.min(minY, c.Position.Y - ey)
		end
	end
	return minY
end

-- chão real sob a baia (ignora o próprio carro, os jogadores e o que foi criado em jogo)
local function groundY(pos, car)
	local ignore = { car, ctx.Runtime }
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local r = workspace:Raycast(pos + Vector3.new(0, 25, 0), Vector3.new(0, -120, 0), params)
	return r and r.Position.Y or pos.Y
end

local function resetMotion(car)
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function bayFree(cf)
	for _, entry in ipairs(cars) do
		if (carPos(entry.Model) - cf.Position).Magnitude < 9 then return false end
	end
	return true
end

function Fleet.Cars() return cars end

function Fleet.Bring(entry, player)
	if occupied(entry.Model) then
		ctx.Systems.Radio.Notify("warn", "Esta viatura está em uso.", player)
		return false
	end
	local bays = ctx.Util.ObjList("Vehicle_Spawn")
	local chosen
	for _, b in ipairs(bays) do
		if bayFree(b.CFrame) then chosen = b break end
	end
	if not chosen then
		ctx.Systems.Radio.Notify("warn", "Todas as baias estão ocupadas.", player)
		return false
	end
	-- assento alinhado com a direção da baia, carro em pé e com as rodas logo acima do chão real
	local bay = chosen.CFrame.LookVector * Vector3.new(1, 0, 1)
	if bay.Magnitude < 0.1 then bay = Vector3.new(0, 0, -1) end
	local drop = -bottomBelowSeat(entry.Model)
	local y = groundY(chosen.Position, entry.Model) + drop + 0.4
	local alvo = Vector3.new(chosen.Position.X, y, chosen.Position.Z)
	-- mantém a orientação original do assento (inclinação de fábrica) e só gira no eixo vertical
	local base = entry.HomeSeat.Rotation
	local f = base.LookVector * Vector3.new(1, 0, 1)
	local yaw = math.atan2(-bay.X, -bay.Z) - math.atan2(-f.X, -f.Z)
	moveCar(entry.Model, CFrame.new(alvo) * CFrame.Angles(0, yaw, 0) * base)
	resetMotion(entry.Model)
	entry.LastUsed = os.clock()
	entry.Owner = player and player.UserId or nil
	ctx.Systems.Radio.Notify("success", "Viatura " .. entry.Index .. " liberada na baia.", player)
	ctx.Util.PlaySound(chosen, ctx.Config.Sounds.Door, { Volume = 0.5, Range = 80 })
	ctx.Bus.Fire("VehicleBrought", entry, player)
	return true
end

function Fleet.Return(entry, player)
	if occupied(entry.Model) then
		if player then ctx.Systems.Radio.Notify("warn", "Desça da viatura antes de devolvê-la.", player) end
		return false
	end
	moveCar(entry.Model, entry.HomeSeat)
	resetMotion(entry.Model)
	entry.Owner = nil
	if player then ctx.Systems.Radio.Notify("info", "Viatura " .. entry.Index .. " devolvida à garagem.", player) end
	return true
end

function Fleet.Init(c)
	ctx = c
	for _, d in ipairs(ctx.Area:GetDescendants()) do
		if d:IsA("Model") and d.Name == ctx.Config.Fleet.CarName and not d:FindFirstAncestor("DelegaciaRuntime") then
			local seat = seatOf(d)
			if seat then
				table.insert(cars, { Model = d, Home = d:GetPivot(), HomeSeat = seat.CFrame, Index = #cars + 1, LastUsed = os.clock() })
			end
		end
	end
	local term = ctx.Util.Obj("FleetTerminal")
	if term then
		local sv = ctx.Util.Screen(term, Enum.NormalId.Front, "CENTRAL DE FROTA")
		sv.Text = #cars .. " VIATURAS"
		sv.TextColor3 = Color3.fromRGB(255, 200, 70)
		local pp = ctx.Util.Prompt(term, "Solicitar viatura", "Central de frota", 0.6, Enum.KeyCode.E, 10)
		pp.Triggered:Connect(function(player)
			if not ctx.Util.Ready("fleet" .. player.UserId, ctx.Config.Fleet.Cooldown) then
				ctx.Systems.Radio.Notify("warn", "Aguarde para solicitar outra viatura.", player)
				return
			end
			if not ctx.Util.CanUse(player, "Fleet") then
				ctx.Util.ClearCooldowns("fleet" .. player.UserId)
				return
			end
			if #cars == 0 then
				ctx.Systems.Radio.Notify("warn", "Nenhuma viatura cadastrada na frota.", player)
				return
			end
			task.spawn(function()
				local opts = {}
				for i, e in ipairs(cars) do
					if i > 4 then break end
					opts[i] = "Viatura " .. i .. (occupied(e.Model) and " (em uso)" or "")
				end
				local idx = ctx.Systems.Dialog.Ask(player, "FROTA", "Qual viatura você quer na baia?", opts, 20)
				if idx and cars[idx] then Fleet.Bring(cars[idx], player) end
			end)
		end)
		local rt = ctx.Util.Prompt(term, "Devolver viatura próxima", "Central de frota", 0.8, Enum.KeyCode.F, 10)
		rt.UIOffset = Vector2.new(0, 70)
		rt.Triggered:Connect(function(player)
			if not ctx.Util.OnDuty(player) then return end
			local best, bd = nil, 45
			for _, e in ipairs(cars) do
				local d = (carPos(e.Model) - term.Position).Magnitude
				if d < bd and (carPos(e.Model) - e.HomeSeat.Position).Magnitude > 10 then best, bd = e, d end
			end
			if best then Fleet.Return(best, player) else ctx.Systems.Radio.Notify("info", "Nenhuma viatura fora da garagem por perto.", player) end
		end)
	end

	-- recolhe viaturas abandonadas
	task.spawn(function()
		while true do
			task.wait(20)
			for _, e in ipairs(cars) do
				if occupied(e.Model) then
					e.LastUsed = os.clock()
				elseif (carPos(e.Model) - e.HomeSeat.Position).Magnitude > 12
					and os.clock() - e.LastUsed > ctx.Config.Fleet.UnoccupiedReturn then
					Fleet.Return(e, nil)
				end
			end
		end
	end)
end

return Fleet
