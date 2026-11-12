--[[
	PostoAutoTest — validação automática do GasStationArea/Posto (somente Studio).

	COMO USAR
	  1. Insira GasStationArea_Posto.rbxmx no Workspace (a hierarquia GasStationArea/Posto precisa ficar intacta).
	  2. Crie um Script em ServerScriptService com este código e aperte Play (F5) com 1 jogador.
	  3. Leia o Output: "[TESTE POSTO] PASSOU/FALHOU". Remova o script depois.

	Usa somente APIs públicas existentes. ProximityPrompts não podem ser acionados pelo servidor, então as
	etapas que dependem de prompt chamam a mesma função do sistema que o prompt chamaria (ex.: Pumps.CloseValve)
	ou ficam para o procedimento manual.
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local CollectionService = game:GetService("CollectionService")

local logs = {}
LogService.MessageOut:Connect(function(msg, kind)
	if (kind == Enum.MessageType.MessageWarning or kind == Enum.MessageType.MessageError) and not msg:find("%[TESTE POSTO%]") then
		table.insert(logs, msg)
	end
end)
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed += 1 else failed += 1 end
	print(string.format("[TESTE POSTO] %s  %s%s", cond and "PASSOU" or "FALHOU", name, detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
end
local function waitUntil(fn, t)
	local t0 = os.clock()
	while os.clock() - t0 < (t or 10) do if fn() then return true end task.wait(0.25) end
	return fn()
end

local area = workspace:WaitForChild("GasStationArea", 30)
local posto = area:WaitForChild("Posto")
local objects = area:WaitForChild("PostoObjects")
local M = posto.Modules
local S = M.Systems
local state = RS:WaitForChild("PostoState", 30)
waitUntil(function() return state:GetAttribute("FuelReserve") ~= nil end, 20)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local char = player.Character or player.CharacterAdded:Wait()
task.wait(4)

local Config = require(M.Config)
local Util = require(M.Util)
local Missions = require(M.Missions)
local Power = require(S.Power)
local Pumps = require(S.Pumps)
local Ambience = require(S.Ambience)
local Alarm = require(S.Alarm)
local Shop = require(S.Shop)
local Tools = require(S.Tools)
local Npc = require(S.Npc)
local Customers = require(S.Customers)
local runtime = workspace:WaitForChild("PostoRuntime")

-- fila: os roteiros movem o jogador e iniciam missões; dois ao mesmo tempo atrapalham um ao outro
while workspace:GetAttribute("TesteAutomaticoEmExecucao") do
	print("[TESTE POSTO] aguardando outro roteiro terminar: " .. tostring(workspace:GetAttribute("TesteAutomaticoEmExecucao")))
	task.wait(3)
end
workspace:SetAttribute("TesteAutomaticoEmExecucao", "POSTO")
char = player.Character or player.CharacterAdded:Wait()
print("[TESTE POSTO] ===== início =====")
-- o sorteio automático de missões fica desligado durante o teste
local autoStartOriginal = Config.Director.AutoStart
Config.Director.AutoStart = false
local function stopActive()
	local a = Missions.Active()
	if a then a:Fail("teste-automatico") task.wait(1) end
end
char:PivotTo(CFrame.new(state:GetAttribute("PostoCenter") + Vector3.new(0, 6, 0)))

-- 1. inicialização
do
	check("Init: 8 missões carregadas", #Missions.List() == 8, table.concat(Missions.List(), ","))
	local r = RS:FindFirstChild("PostoRemotes")
	check("Init: 5 RemoteEvents", r and #r:GetChildren() == 5)
	check("Init: energia normal", Power.Mode() == "on" and not Power.Tripped())
	check("Init: HUD instalada", waitUntil(function() return player.PlayerGui:FindFirstChild("PostoHUD") ~= nil end, 10))
end

-- 2. economia desativada: nada é criado nem pago
do
	check("Economia desativada por padrão", Config.Economy.Enabled == false)
	local ls = player:FindFirstChild("leaderstats")
	-- (num place de teste vazio nenhum outro sistema cria leaderstats; se o seu jogo cria, ignore este item)
	check("Posto não criou leaderstats." .. Config.Economy.Stat, not (ls and ls:FindFirstChild(Config.Economy.Stat)))
	check("Util.Pay devolve 0", Util.Pay(player, 50, "teste") == 0)
	local ok, charged = Util.Charge(player, 30, "teste")
	check("Compra com economia desligada: entregue sem cobrar (PurchasesWhenDisabled=free)", ok == true and charged == 0)
	local got = 0
	Util.SetEconomyProvider({ Pay = function(_, v) got += v return v end, Charge = function() return true end, Balance = function() return 999 end })
	Config.Economy.Enabled = true
	local r = Util.Pay(player, 20, "teste")
	local ok2, ch2 = Util.Charge(player, 10, "teste")
	Config.Economy.Enabled = false
	Util.SetEconomyProvider(nil)
	check("Interface de integração: Pay/Charge chegam ao provedor", r == 20 and got == 20 and ok2 and ch2 == 10)
end

-- 3. áudio ausente não quebra
check("PlaySound com ID vazio devolve nil", Util.PlaySound(workspace, "") == nil)
check("PlaySound com ID numérico/sem parent não lança erro", pcall(Util.PlaySound, nil, 123) and pcall(Util.PlaySound, nil, "rbxassetid://1"))

-- 4. apagão: relâmpago + blackout (regressão do defeito que ignorava o apagão)
do
	stopActive()
	Ambience.Lightning(3)
	Power.Blackout(true)
	check("Relâmpago + Blackout: posto realmente apaga", waitUntil(function() return Power.Mode() == "off" and Power.Tripped() end, 4), Power.Mode())
	task.wait(3) -- novos relâmpagos não podem religar as luzes
	check("Relâmpagos seguintes não interrompem o apagão", Power.Mode() == "off")
	Power.ForceOnline()
	check("ForceOnline restaura energia e bombas", Power.Mode() == "on" and state:GetAttribute("PumpsOnline") == true)
end
do
	stopActive()
	check("blackout: inicia", Missions.Start("blackout"))
	local apagou = waitUntil(function() return Power.Mode() == "off" end, 5)
	check("blackout: energia cai (gerador fica disponível)", apagou, Power.Mode())
	local m = Missions.Active()
	if m then m:Fail("teste-automatico") end
	task.wait(0.5)
	check("blackout: limpeza devolve energia", Power.Mode() == "on" and not Power.Tripped())
end

-- 5. vazamento: válvula -> limpeza conclui sem fogo
do
	stopActive()
	check("fuel_leak: inicia", Missions.Start("fuel_leak"))
	local m = Missions.Active()
	if m then
		local i = m.pump
		check("fuel_leak: bomba em vazamento", Pumps.State(i) == "leak")
		Pumps.CloseValve(i, player)
		task.wait(0.3)
		Pumps.CleanPuddle(i, player)
		check("fuel_leak: concluída após válvula + limpeza", waitUntil(function() return m.Ended end, 5), m.Progress .. "/" .. m.Goal)
		check("fuel_leak: bomba volta ao normal", Pumps.State(i) == "ok")
	end
end

-- 6. inspeção: defeitos reais e limpeza
do
	stopActive()
	local tries, faulted = 0, 0
	repeat
		tries += 1
		stopActive()
		Missions.Start("inspection")
		task.wait(0.5)
		faulted = 0
		for _, o in ipairs(objects:GetChildren()) do if o:GetAttribute("Defeito") then faulted += 1 end end
	until faulted > 0 or tries >= 6
	check("inspection: equipamentos recebem defeito real (atributo Defeito)", faulted > 0, faulted .. " em " .. tries .. " tentativa(s)")
	for i, p in ipairs(Pumps.List()) do
		if p.anchor:GetAttribute("Defeito") then
			check("inspection: bomba com defeito fica fora de serviço", p.fill.Enabled == false, "bomba " .. i)
		end
	end
	local m = Missions.Active()
	if m then m:Fail("teste-automatico") end
	task.wait(0.5)
	local left = 0
	for _, o in ipairs(objects:GetChildren()) do if o:GetAttribute("Defeito") then left += 1 end end
	check("inspection: nenhum defeito sobra após encerrar", left == 0, left)
end

-- 7. assalto: estrutura, alarme obrigatório e falha de NPC
do
	stopActive()
	check("robbery: inicia", Missions.Start("robbery"))
	local m = Missions.Active()
	if m then
		check("robbery: 4 objetivos (alarme é obrigatório)", m.Goal == 4, m.Goal)
		check("robbery: assaltante criado", m.robber ~= nil and m.robber.Parent ~= nil)
		check("robbery: loja fechada durante o assalto", Shop.IsOpen() == false)
		m:Fail("teste-automatico")
		task.wait(0.5)
		check("robbery: assaltante removido", m.robber.Parent == nil)
		check("robbery: loja reaberta", Shop.IsOpen() == true)
	end
	-- simula falha na criação do NPC
	local orig = Npc.Create
	Npc.Create = function() return nil end
	local ok = Missions.Start("robbery")
	Npc.Create = orig
	check("robbery: falha ao criar NPC não vira vitória (missão não inicia)", ok == false and Missions.Active() == nil)
	check("robbery: loja continua aberta após a falha", Shop.IsOpen() == true)
end

-- 8. estoque: sem marcadores não inicia; Tools carregadas são recolhidas
do
	stopActive()
	local renamed = {}
	for _, o in ipairs(objects:GetChildren()) do
		if o.Name:match("^ShelfDrop_") then renamed[o] = o.Name o.Name = "_teste_" .. o.Name end
	end
	check("stock: não inicia sem prateleiras (antes concluía sozinha)", Missions.Start("stock") == false)
	for o, n in pairs(renamed) do o.Name = n end
	check("stock: inicia com marcadores", Missions.Start("stock"))
	local m = Missions.Active()
	if m then
		Tools.Give(player, "crate")
		task.wait(0.3)
		m:Fail("teste-automatico")
		task.wait(0.5)
		check("stock: caixa carregada removida do jogador", Tools.Find(player, "crate") == nil)
		check("stock: caixas do chão removidas", runtime:FindFirstChild("CaixaEstoque") == nil)
	end
end

-- 9. carro sem combustível: galão pronto conta e a limpeza remove o carro
do
	stopActive()
	Tools.Remove(player, "jerrycan")
	Tools.Give(player, "jerrycan", { Liters = 12 })
	check("stranded: inicia", Missions.Start("stranded"))
	local m = Missions.Active()
	if m then
		check("stranded: galão com ≥10 L já conta como etapa 1", m.Progress == 1, m.Progress)
		local car = m.car
		m:Fail("teste-automatico")
		check("stranded: carro removido após encerrar", waitUntil(function() return car.Parent == nil end, 5))
	end
	Tools.Remove(player, "jerrycan")
end

-- 10. caminhão-tanque e smoke das 8 missões
for _, id in ipairs(Missions.List()) do
	stopActive()
	task.wait(1)
	local ok = Missions.Start(id)
	check("Smoke " .. id .. ": inicia", ok)
	if ok then
		task.wait(2)
		local m = Missions.Active()
		if m and not m.Ended then m:Fail("teste-automatico") end
		task.wait(9) -- caminhão/carro e clientes têm saída com atraso
		check("Smoke " .. id .. ": HUD sem missão", state:GetAttribute("MissionId") == "")
		check("Smoke " .. id .. ": alarme desligado", not Alarm.Active())
		check("Smoke " .. id .. ": energia normal", Power.Mode() == "on")
		local d = 0
		for _, o in ipairs(objects:GetChildren()) do if o:GetAttribute("Defeito") then d += 1 end end
		check("Smoke " .. id .. ": sem defeitos pendentes", d == 0)
		check("Smoke " .. id .. ": sem sacola/caixa com o jogador", not Tools.Find(player, "moneybag") and not Tools.Find(player, "crate"))
	end
end
check("Sem caminhão/carro esquecido no Runtime", waitUntil(function()
	for _, c in ipairs(runtime:GetChildren()) do
		if c:IsA("Model") and (c:FindFirstChild("Cab") or c:FindFirstChild("Cabin")) then return false end
	end
	return true
end, 12))
check("Marcadores de missão limpos", #CollectionService:GetTagged("PostoMarker") == 0, #CollectionService:GetTagged("PostoMarker"))

print("[TESTE POSTO] ===== avisos/erros no Output =====")
for _, l in ipairs(logs) do print("[TESTE POSTO] Output: " .. l) end
Config.Director.AutoStart = autoStartOriginal
workspace:SetAttribute("TesteAutomaticoEmExecucao", nil)
print(string.format("[TESTE POSTO] ===== RESULTADO: %d passaram, %d falharam, %d avisos/erros =====", passed, failed, #logs))
