--[[
	OilRigAutoTest — roteiro de validação automática do sistema de missões da plataforma (somente Studio).

	COMO USAR
	  1. Insira Oil_petrol_Missoes.rbxmx no Workspace de um place de teste.
	  2. Crie um Script em ServerScriptService com este código.
	  3. Play (F5) com 1 jogador. Depois repita em "Start Server + 2 Players" (Test > Clients and Servers).
	  4. Leia o Output: "[TESTE OIL] PASSOU/FALHOU". Remova o script depois.

	Usa somente APIs públicas existentes (Missions, Util, Crane, Fire, Pressure, Cargo, Helicopter, Alarm).
	Renomeia temporariamente alguns marcadores para simular ausência e os restaura em seguida.
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")

local logs = {}
LogService.MessageOut:Connect(function(msg, kind)
	if (kind == Enum.MessageType.MessageWarning or kind == Enum.MessageType.MessageError) and not msg:find("%[TESTE OIL%]") then
		table.insert(logs, msg)
	end
end)

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed += 1 else failed += 1 end
	print(string.format("[TESTE OIL] %s  %s%s", cond and "PASSOU" or "FALHOU", name, detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
end
local function waitUntil(fn, t)
	local t0 = os.clock()
	while os.clock() - t0 < (t or 10) do if fn() then return true end task.wait(0.25) end
	return fn()
end

local rigFolder
waitUntil(function()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "OilRig" and d:IsA("Folder") and d:FindFirstChild("Core") then rigFolder = d return true end
	end
end, 20)
assert(rigFolder, "pasta OilRig não encontrada")
local model = rigFolder.Parent
local objects = model:WaitForChild("RigObjects")
local M = rigFolder.Modules
local state = RS:WaitForChild("OilRigState")
waitUntil(function() return state:GetAttribute("RigCenter") ~= nil end, 20)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local char = player.Character or player.CharacterAdded:Wait()
task.wait(3)

local Config = require(M.Config)
local Util = require(M.Util)
local Missions = require(M.Missions)
local Crane = require(M.Systems.Crane)
local Fire = require(M.Systems.Fire)
local Pressure = require(M.Systems.Pressure)
local Heli = require(M.Systems.Helicopter)
local Alarm = require(M.Systems.Alarm)
local Cargo = require(M.Systems.Cargo)

-- fila: os roteiros movem o jogador e iniciam missões; dois ao mesmo tempo atrapalham um ao outro
while workspace:GetAttribute("TesteAutomaticoEmExecucao") do
	print("[TESTE OIL] aguardando outro roteiro terminar: " .. tostring(workspace:GetAttribute("TesteAutomaticoEmExecucao")))
	task.wait(3)
end
workspace:SetAttribute("TesteAutomaticoEmExecucao", "OIL")
char = player.Character or player.CharacterAdded:Wait()
print("[TESTE OIL] ===== início =====")
-- o sorteio automático de missões fica desligado durante o teste (senão ele inicia missões nas esperas longas)
local autoStartOriginal = Config.Director.AutoStart
Config.Director.AutoStart = false
local function stopActive()
	local a = Missions.Active()
	if a then a:Fail("teste-automatico") task.wait(0.5) end
end
-- jogador perto da plataforma para o diretor/pressão contarem normalmente
char:PivotTo(objects.MissionBoard.CFrame * CFrame.new(0, 2, -6))

-- 1. referência espacial
do
	local center, radius = state:GetAttribute("RigCenter"), state:GetAttribute("RigRadius")
	local d = (center - objects.MissionBoard.Position) * Vector3.new(1, 0, 1)
	check("Centro da plataforma perto dos objetos (não puxado pela origem)", d.Magnitude < 250, math.floor(d.Magnitude))
	check("Raio do HUD compatível com a plataforma", radius < 600, math.floor(radius))
end

-- 2. guindaste gira em torno da própria base
do
	local crane
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("Model") and d.Name == "Crane" then crane = d break end end
	check("Guindaste pronto", Crane.Ready())
	if crane then
		local base, lowest = nil, math.huge
		for _, p in ipairs(crane:GetDescendants()) do
			if p:IsA("BasePart") and p.Position.Y < lowest then base, lowest = p, p.Position.Y end
		end
		local before = base.Position
		local from = Crane.GetAngle()
		Crane.SetAngle(from + 20)
		check("Base do guindaste não se desloca ao girar", (base.Position - before).Magnitude < 0.5, (base.Position - before).Magnitude)
		Crane.SetAngle(from)
		check("Guindaste volta à posição original", (base.Position - before).Magnitude < 0.05)
	end
end

-- 3. economia desativada: nada é pago nem criado
do
	local hadLs = player:FindFirstChild("leaderstats") ~= nil
	check("Economia desativada por padrão", Config.Economy.Enabled == false)
	check("Util.Pay devolve 0 sem integração", Util.Pay(player, 50, "teste") == 0)
	check("Nenhum leaderstats criado pelo OilRig", hadLs or player:FindFirstChild("leaderstats") == nil)
	-- provedor simulado (restaurado em seguida)
	local got = 0
	Util.SetRewardProvider(function(_, v) got += v return v end)
	Config.Economy.Enabled = true
	local r = Util.Pay(player, 30, "teste")
	Config.Economy.Enabled = false
	Util.SetRewardProvider(nil)
	check("Interface de integração entrega valor ao provedor", r == 30 and got == 30, r)
end

-- 4. áudio ausente/inválido não quebra nada
do
	check("PlaySound com ID vazio devolve nil", Util.PlaySound(workspace, "") == nil)
	-- ID numérico sem parent: exercita a conversão sem baixar asset (evita erro de ContentId no Output)
	check("PlaySound com ID numérico não lança erro", pcall(Util.PlaySound, nil, 123))
	check("PlaySound sem parent não lança erro", pcall(Util.PlaySound, nil, "rbxassetid://1"))
end

-- 5. missões concluídas de ponta a ponta sem nenhum SoundId configurado
local function runToEnd(id, drive)
	stopActive()
	local ok = Missions.Start(id)
	check("Missão " .. id .. ": inicia", ok)
	if not ok then return end
	local m = Missions.Active()
	task.wait(0.5)
	drive(m)
	check("Missão " .. id .. ": concluída", waitUntil(function() return m.Ended end, 15), m.Progress .. "/" .. m.Goal)
end
runToEnd("crane", function()
	Crane.SetAngle(state:GetAttribute("CraneTarget"), player)
end)
runToEnd("fires", function()
	Fire.ExtinguishAll()
end)
runToEnd("pressure", function()
	Pressure.Set(Config.Pressure.Safe - 1)
end)
check("Alarme desligado após as missões", waitUntil(function() return not Alarm.Active() end, 15))

-- 6. sem objetivos disponíveis: não inicia (antes concluía sozinha)
local function hideObjects(pattern)
	local renamed = {}
	for _, o in ipairs(objects:GetChildren()) do
		if o.Name:match(pattern) then renamed[o] = o.Name o.Name = "_teste_" .. o.Name end
	end
	return function() for o, n in pairs(renamed) do o.Name = n end end
end
do
	stopActive()
	local restore = hideObjects("^FireSpot_")
	check("fires não inicia sem pontos de incêndio", Missions.Start("fires") == false)
	restore()
	restore = hideObjects("^BarrelSpawn_")
	check("barrels não inicia sem pontos de barril", Missions.Start("barrels") == false)
	restore()
	restore = hideObjects("^HelipadPad$")
	check("airdrop não inicia sem heliponto", Missions.Start("airdrop") == false)
	check("Helicopter.Call devolve false sem heliponto", Heli.Call() == false)
	restore()
end

-- 7. limpeza: barris no mundo e Tools de carga
do
	stopActive()
	check("barrels inicia", Missions.Start("barrels"))
	task.wait(0.5)
	local props = 0
	for _, d in ipairs(workspace:GetChildren()) do if d.Name == "Barril_Prop" then props += 1 end end
	check("Barris criados no mundo", props > 0, props)
	-- Tools carregadas só nascem pelo prompt "Pegar" (cliente): validar no procedimento manual, passo 4
	Missions.Active():Fail("teste-automatico")
	task.wait(0.5)
	local left = 0
	for _, d in ipairs(workspace:GetChildren()) do if d.Name == "Barril_Prop" then left += 1 end end
	check("Barris removidos ao encerrar", left == 0, left)
end

-- 8. helicóptero: cancelamento durante o voo não deixa caixas nem helicóptero preso
do
	stopActive()
	local ok = Missions.Start("airdrop")
	check("airdrop inicia", ok)
	if ok then
		task.wait(3)
		Missions.Active():Fail("teste-automatico") -- cancela antes do pouso (voo leva ~23s)
		local gone = waitUntil(function() return not Heli.Active() end, 70)
		check("Helicóptero vai embora e libera o sistema", gone)
		local crates = 0
		for _, d in ipairs(workspace:GetChildren()) do if d.Name == "Suprimento_Prop" then crates += 1 end end
		check("Nenhuma caixa órfã após cancelamento", crates == 0, crates)
		check("Modelo do helicóptero removido", workspace:FindFirstChild("HelicopteroSuprimentos") == nil)
	end
end

-- 9. todas as missões iniciam e encerram sem travar
for _, id in ipairs({ "pressure", "blackout", "fires", "barrels", "airdrop", "inspection", "crane" }) do
	waitUntil(function() return not Heli.Active() end, 70)
	-- o blackout cancelado só devolve a energia 8 s depois (comportamento original)
	waitUntil(function() return state:GetAttribute("Power") == true end, 12)
	stopActive()
	local ok = Missions.Start(id)
	check("Smoke " .. id .. ": inicia", ok)
	if ok then
		task.wait(1.5)
		local m = Missions.Active()
		if m and not m.Ended then m:Fail("teste-automatico") end
		task.wait(0.5)
		check("Smoke " .. id .. ": estado limpo no HUD", state:GetAttribute("MissionId") == "")
	end
end
-- o blackout restaura a energia 8 s depois de falhar
check("Energia restaurada após blackout cancelado", waitUntil(function() return state:GetAttribute("Power") == true end, 15))

print("[TESTE OIL] ===== avisos/erros no Output =====")
for _, l in ipairs(logs) do print("[TESTE OIL] Output: " .. l) end
Config.Director.AutoStart = autoStartOriginal
workspace:SetAttribute("TesteAutomaticoEmExecucao", nil)
print(string.format("[TESTE OIL] ===== RESULTADO: %d passaram, %d falharam, %d avisos/erros =====", passed, failed, #logs))
