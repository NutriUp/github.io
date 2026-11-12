-- OFICINA • Camada de integração com a economia do jogo (somente servidor).
-- Usa leaderstats.Dinheiro que JÁ existe. Nunca cria leaderstats, moeda ou DataStore.
-- Quando o módulo central de dados (tarefa T03) existir, registre-o aqui sem mexer no resto da oficina:
--   Economia.DefinirProvedor({ Saldo = function(player) return n end, Cobrar = function(player, valor, motivo) return true/false end })
local Economia = {}
local Config
local provedor

function Economia.Init(ctx) Config = ctx.Config end
function Economia.DefinirProvedor(p) provedor = p end

local function valor(player)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(Config.Economia.Stat)
	if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return v end
	return nil
end

-- saldo atual ou nil se a economia não estiver disponível para este jogador
function Economia.Saldo(player)
	if provedor and provedor.Saldo then
		local ok, n = pcall(provedor.Saldo, player)
		if ok and type(n) == "number" then return n end
		return nil
	end
	local v = valor(player)
	return v and v.Value or nil
end

-- debita no servidor. Devolve (true) ou (false, motivo).
function Economia.Cobrar(player, quantia, motivo)
	if type(quantia) ~= "number" or quantia ~= quantia or quantia < 0 then return false, "valor inválido" end
	quantia = math.ceil(quantia)
	if quantia == 0 then return true end
	if provedor and provedor.Cobrar then
		local ok, res = pcall(provedor.Cobrar, player, quantia, motivo)
		if ok and res then return true end
		return false, "pagamento recusado"
	end
	local v = valor(player)
	if not v then return false, "economia indisponível" end
	if v.Value < quantia then return false, "saldo insuficiente" end
	v.Value -= quantia
	return true
end

return Economia
