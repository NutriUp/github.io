--[[
	DelegaciaAutoTest — roteiro de validação automática (somente para o Studio).

	COMO USAR
	  1. Abra DepartamentoPolicia_Delegacia.rbxlx no Roblox Studio.
	  2. Crie um Script em ServerScriptService e cole este código (ou importe este arquivo).
	  3. Aperte Play (F5) — é preciso um jogador real para os testes de ficha/custódia.
	  4. Acompanhe o Output: cada verificação imprime "[TESTE] PASSOU" ou "[TESTE] FALHOU".
	  5. APAGUE o script antes de publicar. Ele inicia/encerra missões e cria bonecos de teste.

	Este script NÃO altera nenhum módulo: apenas chama as APIs públicas já existentes
	(Missions, Custody, Suspects, Power, Alarm, Fleet, Duty).
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local LogService = game:GetService("LogService")

local area = workspace:WaitForChild("DepartamentoPolicia")
local delegacia = area:WaitForChild("Delegacia")
local objects = area:WaitForChild("DelegaciaObjects")
local sys = delegacia:WaitForChild("Modules"):WaitForChild("Systems")

-- coleta avisos/erros do Output durante a execução
local logs = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageWarning or kind == Enum.MessageType.MessageError then
		if not msg:find("%[TESTE%]") then table.insert(logs, msg) end
	end
end)

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed += 1 else failed += 1 end
	print(string.format("[TESTE] %s  %s%s", cond and "PASSOU" or "FALHOU", name, detail and ("  (" .. tostring(detail) .. ")") or ""))
end

local function waitUntil(fn, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 10) do
		if fn() then return true end
		task.wait(0.25)
	end
	return fn()
end

-- ===== espera a delegacia e um jogador =====
local state = RS:WaitForChild("DelegaciaState", 30)
waitUntil(function() return state and state:GetAttribute("CellsTotal") ~= nil end, 30)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local char = player.Character or player.CharacterAdded:Wait()
char:WaitForChild("HumanoidRootPart")
task.wait(8) -- presos de ambiente (4s) + coleta de luzes do Power (2s)

local Missions = require(delegacia.Modules.Missions)
local Custody = require(sys.Custody)
local Suspects = require(sys.Suspects)
local Power = require(sys.Power)
local Alarm = require(sys.Alarm)
local Fleet = require(sys.Fleet)
local Duty = require(sys.Duty)
local Npc = require(sys.Npc)
local runtime = workspace:WaitForChild("DelegaciaRuntime")

print("[TESTE] ===== início =====")
Duty.Set(player, true)
task.wait(0.5)

local function stopActive()
	local a = Missions.Active()
	if a then a:Fail("teste-automatico") task.wait(1) end
end

-- ===== 1. inicialização =====
do
	local remotes = RS:FindFirstChild("DelegaciaRemotes")
	check("Init: pasta DelegaciaRemotes", remotes ~= nil)
	check("Init: 13 RemoteEvents", remotes and #remotes:GetChildren() == 13, remotes and #remotes:GetChildren())
	local list = Missions.List()
	check("Init: 13 missões carregadas", #list == 13, table.concat(list, ","))
	check("Init: 4 celas", #Custody.Cells() == 4, #Custody.Cells())
	check("Init: presos de ambiente criados", #Custody.Prisoners() >= 1, #Custody.Prisoners())
	check("Init: jogador em serviço", player:GetAttribute("EmServico") == true)
end

-- ===== 2. frota =====
do
	local cars = Fleet.Cars()
	local seen, dup = {}, false
	for _, e in ipairs(cars) do
		if seen[e.Model] then dup = true end
		seen[e.Model] = true
		print("[TESTE] frota: viatura " .. e.Index .. " = " .. e.Model:GetFullName())
	end
	check("Frota: nenhum modelo registrado duas vezes", not dup)
	check("Frota: 2 FEDERAL CAR registradas (uma em CARROS, outra na estação)", #cars == 2, #cars)
end

-- ===== 3. custódia: o suspeito não pode ser destruído antes de chegar à cela =====
local function custodyFlow(id)
	stopActive()
	local started = Missions.Start(id, player)
	check("Custódia/" .. id .. ": missão iniciou", started)
	if not started then return end
	task.wait(1)
	local m = Missions.Active()
	local rec = m and m.Rec
	if not rec then check("Custódia/" .. id .. ": suspeito criado", false) return end
	local desk = objects:FindFirstChild("BookingDesk")
	local top = desk.Position + Vector3.new(0, desk.Size.Y / 2 + 3, 0)
	char:PivotTo(CFrame.new(top + Vector3.new(2, 0, 0)))
	rec.Model:PivotTo(CFrame.new(top + Vector3.new(-2, 0, 0)))
	task.wait(0.3)
	Suspects.Cuff(rec, player)
	task.wait(0.3)
	Suspects.Escort(rec, player, true)
	task.wait(0.3)
	check("Custódia/" .. id .. ": suspeito em escolta", rec.State == "escorted", rec.State)
	local booked = Custody.Book(player)
	check("Custódia/" .. id .. ": ficha aceita no balcão", booked)
	task.wait(1)
	check("Custódia/" .. id .. ": missão concluída após a ficha", m.Ended == true)
	check("Custódia/" .. id .. ": modelo NÃO destruído pelo Cleanup", rec.Model.Parent ~= nil)
	check("Custódia/" .. id .. ": suspeito registrado em Custody.Prisoners()", table.find(Custody.Prisoners(), rec) ~= nil)
	local jailed = waitUntil(function() return rec.State == "jailed" end, 40)
	check("Custódia/" .. id .. ": suspeito chegou à cela (estado jailed)", jailed, rec.State)
	check("Custódia/" .. id .. ": atributo Preso = true", rec.Model:GetAttribute("Preso") == true)
end
custodyFlow("perimeter_breach")
custodyFlow("most_wanted")

-- ===== 4. bomba: um Humanoid recebe dano uma única vez por explosão =====
do
	stopActive()
	local started = Missions.Start("bomb_threat", player)
	check("Bomba: missão iniciou", started)
	if started then
		task.wait(1)
		local m = Missions.Active()
		local pos = m.Package.Position
		-- afasta o jogador da explosão
		char:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 80)))
		local dummies = {}
		for i = 1, 2 do
			local d = Npc.Create("BonecoTeste" .. i, CFrame.new(pos + Vector3.new(i * 3, 3, 0)), { role = false })
			if d then
				local h = d:FindFirstChildOfClass("Humanoid")
				h.MaxHealth, h.Health = 100, 100
				table.insert(dummies, d)
			end
		end
		task.wait(0.5)
		m:Fail("teste-automatico") -- OnFail -> explode()
		task.wait(1)
		for _, d in ipairs(dummies) do
			local h = d:FindFirstChildOfClass("Humanoid")
			check("Bomba: " .. d.Name .. " recebeu exatamente 40 de dano", h and math.abs(h.Health - 60) < 0.01, h and h.Health)
			d:Destroy()
		end
		check("Bomba: pacote removido", runtime:FindFirstChild("PacoteSuspeito") == nil)
	end
end

-- ===== 5. apagão (parte automática) =====
do
	stopActive()
	local started = Missions.Start("blackout", player)
	check("Apagão: missão iniciou", started)
	if started then
		task.wait(1)
		check("Apagão: energia em 'off' no início", Power.Mode() == "off" and state:GetAttribute("Power") == "off", Power.Mode())
		task.wait(10) -- deixa o loop de oscilação rodar algumas vezes
		check("Apagão: sem gerador religado a energia não volta para 'on'", Power.Mode() ~= "on", Power.Mode())
		Missions.Active():Fail("teste-automatico")
		task.wait(0.5)
		check("Apagão: Cleanup devolve energia 'on'", Power.Mode() == "on")
		print("[TESTE] Apagão: religar os 3 geradores exige o prompt (E) — ver procedimento manual.")
	end
end

-- ===== 6. rebelião: presos mortos fora da cela também são limpos =====
do
	stopActive()
	local started = Missions.Start("riot", player)
	check("Rebelião: missão iniciou", started)
	if started then
		task.wait(1)
		local m = Missions.Active()
		local victim = m.Rioters[1]
		if victim then
			victim.Hum.Health = 0
			task.wait(0.5)
		end
		m:Fail("teste-automatico")
		task.wait(1)
		check("Rebelião: preso morto removido no Cleanup", victim and victim.Model.Parent == nil)
	end
end

-- ===== 7. smoke test das 13 missões: inicia, encerra e confere a limpeza =====
local function promptCount()
	local n = 0
	for _, d in ipairs(objects:GetDescendants()) do
		if d:IsA("ProximityPrompt") then n += 1 end
	end
	return n
end
for _, id in ipairs(Missions.List()) do
	stopActive()
	task.wait(1)
	local markers0 = #CollectionService:GetTagged("DelegaciaMarker")
	local prompts0 = promptCount()
	local before = {}
	for _, r in ipairs(Suspects.All()) do before[r] = true end
	local started = Missions.Start(id, player)
	check("Missão " .. id .. ": inicia sem erro", started)
	if started then
		task.wait(2)
		local m = Missions.Active()
		if m and not m.Ended then m:Fail("teste-automatico") end
		task.wait(1.5)
		local leaked = 0
		for _, r in ipairs(Suspects.All()) do
			if not before[r] and not table.find(Custody.Prisoners(), r) then leaked += 1 end
		end
		check("Missão " .. id .. ": nenhum NPC temporário restante", leaked == 0, leaked)
		check("Missão " .. id .. ": marcadores limpos", #CollectionService:GetTagged("DelegaciaMarker") <= markers0,
			#CollectionService:GetTagged("DelegaciaMarker") .. "/" .. markers0)
		check("Missão " .. id .. ": prompts temporários removidos", promptCount() <= prompts0, promptCount() .. "/" .. prompts0)
		check("Missão " .. id .. ": alarme desligado", not Alarm.Active())
		check("Missão " .. id .. ": energia normal", Power.Mode() == "on")
		check("Missão " .. id .. ": HUD sem missão ativa", state:GetAttribute("MissionId") == "")
	end
end

-- ===== 8. custódia: preso morto é retirado da lista e o modelo destruído =====
do
	local rec = Custody.Prisoners()[1]
	if rec then
		rec.Hum.Health = 0
		local gone = waitUntil(function() return rec.Model.Parent == nil and not table.find(Custody.Prisoners(), rec) end, 15)
		check("Custódia: preso morto removido da lista e do Workspace", gone)
	end
end

-- ===== resumo =====
print("[TESTE] ===== avisos/erros capturados no Output =====")
for _, l in ipairs(logs) do print("[TESTE] Output: " .. l) end
print(string.format("[TESTE] ===== RESULTADO: %d passaram, %d falharam, %d avisos/erros no Output =====", passed, failed, #logs))
