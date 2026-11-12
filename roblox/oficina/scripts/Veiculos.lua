-- OFICINA • Adaptador dos veículos REAIS do jogo (não cria sistema de veículos paralelo).
-- Descobre o carro a partir do assento do motorista, o dono, o tipo (A-Chassis / VehicleSeat) e cuida de
-- fixar o carro no box e do reparo. Tudo aqui roda no servidor.
local Players = game:GetService("Players")

local Veiculos = {}
local Config
local reparoExterno   -- função registrada por outro sistema (ex.: VehicleDamage): fn(carro) -> bool

function Veiculos.Init(ctx) Config = ctx.Config end

-- ===== identificação =====
local function contaAssentos(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("VehicleSeat") then n += 1 end
	end
	return n
end

-- carro (Model) ao qual o assento pertence
function Veiculos.DoAssento(seat)
	if not seat or not seat:IsA("VehicleSeat") then return nil end
	-- A-Chassis: o modelo do carro tem o módulo "A-Chassis Tune" como filho direto
	local a = seat.Parent
	while a and a ~= workspace do
		if a:IsA("Model") and a:FindFirstChild("A-Chassis Tune") then return a end
		a = a.Parent
	end
	-- genérico: o maior Model ancestral que ainda contém só este assento de motorista e tem tamanho de veículo
	local melhor
	a = seat.Parent
	while a and a ~= workspace do
		if a:IsA("Model") then
			if contaAssentos(a) ~= 1 then break end
			local ok, _, size = pcall(function() return a:GetBoundingBox() end)
			if not ok or size.Magnitude > 90 then break end
			melhor = a
		end
		a = a.Parent
	end
	return melhor
end

function Veiculos.AssentoMotorista(car)
	local s = car:FindFirstChild("DriveSeat", true)
	if s and s:IsA("VehicleSeat") then return s end
	return car:FindFirstChildWhichIsA("VehicleSeat", true)
end

function Veiculos.Tipo(car)
	if car:FindFirstChild("A-Chassis Tune") then return "achassis" end
	if car:FindFirstChildWhichIsA("VehicleSeat", true) then return "vehicleseat" end
	return nil
end

-- ===== dono =====
-- devolve (userId | nil, origem)
function Veiculos.Dono(car)
	for _, nome in ipairs(Config.Dono.Atributos) do
		local v = car:GetAttribute(nome)
		if type(v) == "number" then return v, "atributo " .. nome end
		if type(v) == "string" then
			local p = Players:FindFirstChild(v)
			if p then return p.UserId, "atributo " .. nome end
			if tonumber(v) then return tonumber(v), "atributo " .. nome end
		end
	end
	for _, nome in ipairs(Config.Dono.Valores) do
		local o = car:FindFirstChild(nome)
		if o then
			if o:IsA("ObjectValue") and o.Value and o.Value:IsA("Player") then return o.Value.UserId, "valor " .. nome end
			if (o:IsA("IntValue") or o:IsA("NumberValue")) and o.Value ~= 0 then return o.Value, "valor " .. nome end
			if o:IsA("StringValue") and o.Value ~= "" then
				local p = Players:FindFirstChild(o.Value)
				if p then return p.UserId, "valor " .. nome end
			end
		end
	end
	return nil, "sem dono registrado"
end

-- o jogador pode personalizar este carro? (precisa estar no assento do motorista)
function Veiculos.PodeUsar(player, car)
	local seat = Veiculos.AssentoMotorista(car)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not seat or not hum or seat.Occupant ~= hum then return false, "Entre no assento do motorista." end
	local dono = Veiculos.Dono(car)
	if dono then
		if dono ~= player.UserId then return false, "Este veículo pertence a outro jogador." end
		return true
	end
	if Config.Dono.AceitarMotoristaSemDono then return true end
	return false, "Veículo sem dono registrado."
end

-- ===== fixar no box =====
function Veiculos.Fixar(car, fixo, player)
	local seat = Veiculos.AssentoMotorista(car)
	if not seat then return end
	if fixo then
		car:SetAttribute("OfAncoraOriginal", seat.Anchored)
		seat.AssemblyLinearVelocity = Vector3.zero
		seat.AssemblyAngularVelocity = Vector3.zero
		seat.Anchored = true
	else
		local original = car:GetAttribute("OfAncoraOriginal")
		seat.Anchored = original == true
		car:SetAttribute("OfAncoraOriginal", nil)
		-- ancorar tira a posse de rede; devolve ao motorista para o carro voltar a responder
		if player and not seat.Anchored then
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum and seat.Occupant == hum then pcall(function() seat:SetNetworkOwner(player) end) end
		end
	end
end

-- faz o motorista sentar de novo (o A-Chassis relê o Tune a cada vez que alguém assume o volante)
function Veiculos.Reassentar(car, player)
	local seat = Veiculos.AssentoMotorista(car)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not seat or not hum or seat.Occupant ~= hum then return end
	task.spawn(function()
		hum.Sit = false
		task.wait(0.6)
		if hum.Parent and hum.Health > 0 and seat.Parent and not seat.Occupant then
			seat:Sit(hum)
		end
	end)
end

-- ===== reparo / diagnóstico =====
function Veiculos.DefinirReparo(fn) reparoExterno = fn end

-- devolve { suportado, vida, max, danificado }
function Veiculos.Diagnostico(car)
	for i, nome in ipairs(Config.Reparo.AtributosVida) do
		local v = car:GetAttribute(nome)
		if type(v) == "number" then
			local max
			for _, nm in ipairs(Config.Reparo.AtributosVidaMax) do
				local m = car:GetAttribute(nm)
				if type(m) == "number" then max = m break end
			end
			max = max or car:GetAttribute("OfVidaMax") or math.max(v, 100)
			if not car:GetAttribute("OfVidaMax") then car:SetAttribute("OfVidaMax", max) end
			return { suportado = true, vida = v, max = max, danificado = v < max - 0.5, atributo = nome }
		end
	end
	if reparoExterno then return { suportado = true, danificado = true, externo = true } end
	return { suportado = false }
end

function Veiculos.Reparar(car)
	local d = Veiculos.Diagnostico(car)
	if not d.suportado then return false end
	if reparoExterno then
		local ok, res = pcall(reparoExterno, car)
		if ok and res ~= false then return true end
		if d.externo then return false end
	end
	if d.atributo then
		car:SetAttribute(d.atributo, d.max)
		return true
	end
	return false
end

return Veiculos
