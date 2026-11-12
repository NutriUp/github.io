-- OFICINA • Melhorias mecânicas com efeito REAL (módulo compartilhado).
-- Os níveis ficam em atributos do carro (OfN_motor, OfN_turbo, OfN_transmissao, OfN_freios, OfN_suspensao),
-- definidos somente pelo servidor.
--   • A-Chassis: a física roda no cliente do motorista, que lê o módulo "A-Chassis Tune" toda vez que assume o
--     volante. Por isso cada cliente ajusta a própria cópia do Tune a partir dos atributos (AplicarTuneCliente)
--     e o servidor faz o motorista sentar de novo ao sair da oficina. A suspensão (molas) é ajustada no servidor.
--   • VehicleSeat clássico: o servidor ajusta MaxSpeed/Torque do assento.
local CollectionService = game:GetService("CollectionService")

local Desempenho = {}
local Config

Desempenho.Ids = { "motor", "turbo", "transmissao", "freios", "suspensao" }
Desempenho.Tag = "OficinaTunado"

function Desempenho.Init(ctx) Config = ctx.Config end
function Desempenho.UsarConfig(cfg) Config = cfg end

function Desempenho.Nivel(car, id)
	local n = car:GetAttribute("OfN_" .. id)
	return type(n) == "number" and n or 0
end

local function dado(id, nivel)
	local cat = Config.Categoria(id)
	return cat and cat.niveis and cat.niveis[nivel] or nil
end

local function mult(car, id)
	local d = dado(id, Desempenho.Nivel(car, id))
	return d and d.mult or 1
end

local function molas(car)
	local out = {}
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("SpringConstraint") then table.insert(out, d) end
	end
	return out
end

local function tipo(car)
	if car:FindFirstChild("A-Chassis Tune") then return "achassis" end
	if car:FindFirstChildWhichIsA("VehicleSeat", true) then return "vehicleseat" end
	return nil
end
Desempenho.Tipo = tipo

-- quais melhorias este veículo realmente suporta
function Desempenho.Suporte(car)
	local t = tipo(car)
	local temMolas = #molas(car) > 0
	if t == "achassis" then
		return { motor = true, turbo = true, transmissao = true, freios = true, suspensao = temMolas }
	elseif t == "vehicleseat" then
		local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
		local classico = seat ~= nil and seat.MaxSpeed > 0 and seat.Torque > 0
		return { motor = classico, turbo = classico, transmissao = classico, freios = false, suspensao = temMolas }
	end
	return { motor = false, turbo = false, transmissao = false, freios = false, suspensao = false }
end

-- ===== servidor =====
function Desempenho.AplicarServidor(car)
	-- suspensão: molas reais do carro
	local ms = mult(car, "suspensao")
	for _, sp in ipairs(molas(car)) do
		if sp:GetAttribute("OfK0") == nil then
			sp:SetAttribute("OfK0", sp.Stiffness)
			sp:SetAttribute("OfD0", sp.Damping)
		end
		sp.Stiffness = sp:GetAttribute("OfK0") * ms
		sp.Damping = sp:GetAttribute("OfD0") * ms
	end
	local t = tipo(car)
	if t == "vehicleseat" then
		local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat then
			if seat:GetAttribute("OfVel0") == nil then
				seat:SetAttribute("OfVel0", seat.MaxSpeed)
				seat:SetAttribute("OfTq0", seat.Torque)
			end
			seat.MaxSpeed = seat:GetAttribute("OfVel0") * mult(car, "motor") * mult(car, "turbo")
			seat.Torque = seat:GetAttribute("OfTq0") * mult(car, "motor") * mult(car, "transmissao")
		end
	elseif t == "achassis" then
		-- os clientes escutam esta tag e ajustam o Tune local
		CollectionService:AddTag(car, Desempenho.Tag)
	end
end

-- ===== cliente (A-Chassis) =====
local CAMPOS_BASE = { "Horsepower", "E_Horsepower", "E_Torque", "BrakeForce", "PBrakeForce", "FBrakeForce", "RBrakeForce", "FinalDrive", "T_Boost", "Turbochargers" }

function Desempenho.AplicarTuneCliente(car)
	local ms = car:FindFirstChild("A-Chassis Tune")
	if not ms or not ms:IsA("ModuleScript") then return false end
	local ok, tune = pcall(require, ms)
	if not ok or type(tune) ~= "table" then return false end
	if not tune._OfBase then
		local base = {}
		for _, k in ipairs(CAMPOS_BASE) do
			if type(tune[k]) == "number" then base[k] = tune[k] end
		end
		tune._OfBase = base
	end
	local b = tune._OfBase
	local function set(k, v) if b[k] then tune[k] = v end end
	local m = mult(car, "motor")
	set("Horsepower", (b.Horsepower or 0) * m)
	set("E_Horsepower", (b.E_Horsepower or 0) * m)
	set("E_Torque", (b.E_Torque or 0) * m)
	local f = mult(car, "freios")
	for _, k in ipairs({ "BrakeForce", "PBrakeForce", "FBrakeForce", "RBrakeForce" }) do set(k, (b[k] or 0) * f) end
	set("FinalDrive", (b.FinalDrive or 0) * mult(car, "transmissao"))
	local nt = Desempenho.Nivel(car, "turbo")
	local dt = dado("turbo", nt)
	if b.T_Boost then
		tune.T_Boost = b.T_Boost + (dt and dt.boost or 0)
		if b.Turbochargers then tune.Turbochargers = (nt > 0) and math.max(b.Turbochargers, 1) or b.Turbochargers end
	elseif dt and b.Horsepower then
		-- chassi sem turbo configurável: o ganho entra como potência
		tune.Horsepower = tune.Horsepower * (dt.mult or 1)
	end
	return true
end

return Desempenho
