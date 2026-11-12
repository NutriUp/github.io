--[[
	OficinaAutoTest — validação automática da oficina TORQUE CUSTOMS (somente Studio).

	COMO USAR
	  1. Insira OFICINA_TorqueCustoms.rbxmx no Workspace (no BATTLE ROYAL ou num place de teste).
	  2. Crie um Script em ServerScriptService com este código e aperte Play (F5) com 1 jogador.
	  3. Leia o Output: "[TESTE OFICINA] PASSOU/FALHOU". Remova o script depois. NÃO salve o place com ele.

	O teste monta um carro simples de VehicleSeat dentro do Box 1, senta o jogador e chama as mesmas funções
	que o prompt e o remote chamam. Se o jogador não tiver leaderstats.Dinheiro, o teste cria um valor
	TEMPORÁRIO só para validar a cobrança e o remove no final (a oficina em si nunca cria leaderstats).
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")

local logs = {}
LogService.MessageOut:Connect(function(msg, kind)
	if (kind == Enum.MessageType.MessageWarning or kind == Enum.MessageType.MessageError) and not msg:find("%[TESTE OFICINA%]") then
		table.insert(logs, msg)
	end
end)
local passou, falhou = 0, 0
local function check(nome, cond, detalhe)
	if cond then passou += 1 else falhou += 1 end
	print(string.format("[TESTE OFICINA] %s  %s%s", cond and "PASSOU" or "FALHOU", nome, detalhe ~= nil and ("  (" .. tostring(detalhe) .. ")") or ""))
end
local function esperar(fn, t)
	local t0 = os.clock()
	while os.clock() - t0 < (t or 8) do if fn() then return true end task.wait(0.2) end
	return fn()
end

local oficina
esperar(function()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "Oficina" and d:IsA("Folder") and d:FindFirstChild("Core") then oficina = d return true end
	end
end, 20)
assert(oficina, "pasta Oficina não encontrada")
local modelo = oficina.Parent
local objetos = modelo:WaitForChild("OficinaObjetos")
local M = oficina.Modules
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
task.wait(3)

local Config = require(M.Config)
local Economia = require(M.Economia)
local Veiculos = require(M.Veiculos)
local Visual = require(M.Visual)
local Desempenho = require(M.Desempenho)
local Sessoes = require(M.Sessoes)
local Portoes = require(M.Portoes)

-- fila: os roteiros movem o jogador e iniciam missões; dois ao mesmo tempo atrapalham um ao outro
while workspace:GetAttribute("TesteAutomaticoEmExecucao") do
	print("[TESTE OFICINA] aguardando outro roteiro terminar: " .. tostring(workspace:GetAttribute("TesteAutomaticoEmExecucao")))
	task.wait(3)
end
workspace:SetAttribute("TesteAutomaticoEmExecucao", "OFICINA")
char = player.Character or player.CharacterAdded:Wait()
print("[TESTE OFICINA] ===== início =====")
-- 1. inicialização
local remotes = RS:FindFirstChild("OficinaRemotes")
check("Init: remotes Sessao e Comprar", remotes and remotes:FindFirstChild("Sessao") and remotes:FindFirstChild("Comprar"))
check("Init: 2 boxes", #Sessoes.Boxes() == 2, #Sessoes.Boxes())
check("Init: 2 portões automáticos", Portoes.Quantidade() == 2, Portoes.Quantidade())
check("Init: interface instalada", esperar(function() return player.PlayerGui:FindFirstChild("OficinaUI") ~= nil end, 10))

-- 2. economia: não cria nada
local ls = player:FindFirstChild("leaderstats")
local tinha = ls and ls:FindFirstChild(Config.Economia.Stat)
if not tinha then
	check("Economia: sem leaderstats o saldo é nil (nada é criado)", Economia.Saldo(player) == nil)
	check("Economia: cobrança recusada sem economia", Economia.Cobrar(player, 10, "teste") == false)
	check("Economia: a oficina não criou leaderstats", not (player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild(Config.Economia.Stat)))
end
-- valor temporário de teste
local criouLs, criouVal
if not ls then ls = Instance.new("Folder") ls.Name = "leaderstats" ls.Parent = player criouLs = true end
local din = ls:FindFirstChild(Config.Economia.Stat)
if not din then din = Instance.new("IntValue") din.Name = Config.Economia.Stat din.Parent = ls criouVal = true end
local saldoOriginal = din.Value
din.Value = 5000

-- 3. portões abrem com o jogador perto
local box = Sessoes.Boxes()[1]
local z = box.zona.Position
-- portão mais próximo do box 1 (não depende da orientação da oficina no mapa)
local portao, dp
for _, d in ipairs(modelo:GetDescendants()) do
	if d:IsA("MeshPart") and d.Name == "Racing_Garage_Rollup_a" then
		local dist = (d.Position - z).Magnitude
		if not dp or dist < dp then portao, dp = d, dist end
	end
end
if portao then
	-- jogador 8 studs para dentro do portão, no caminho do box
	local dir = (z - portao.Position) * Vector3.new(1, 0, 1)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
	char:PivotTo(CFrame.new(Vector3.new(portao.Position.X, z.Y - 3, portao.Position.Z) + dir * 8))
end
local abriu = portao ~= nil and esperar(function() return portao.CanCollide == false and portao.Size.Y < 3 end, 6)
local r = char:FindFirstChild("HumanoidRootPart")
check("Portão do box 1 abre com jogador próximo", abriu, portao and string.format("dist. jogador=%.1f, CanCollide=%s, altura=%.1f",
	r and (r.Position - portao.Position).Magnitude or -1, tostring(portao.CanCollide), portao.Size.Y) or "portão não encontrado")
char:PivotTo(CFrame.new(z + Vector3.new(0, 3, 0)))

-- 4. carro de teste (VehicleSeat clássico) no box
local car = Instance.new("Model")
car.Name = "CarroTesteOficina"
local function p(nome, size, off, cor, mat)
	local part = Instance.new("Part")
	part.Name = nome part.Size = size part.Color = cor part.Material = mat or Enum.Material.SmoothPlastic
	part.Anchored = true part.CFrame = CFrame.new(z.X, 12, z.Z) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(off)
	part.Parent = car
	return part
end
local corpo = p("Carroceria", Vector3.new(7, 2, 14), Vector3.new(0, 0, 0), Color3.fromRGB(200, 30, 30))
p("Teto", Vector3.new(6.4, 1.6, 6), Vector3.new(0, 1.8, 0.5), Color3.fromRGB(200, 30, 30))
p("Friso", Vector3.new(7.1, 0.5, 13), Vector3.new(0, -0.6, 0), Color3.fromRGB(30, 30, 30))
p("Vidro", Vector3.new(6.2, 1.2, 0.2), Vector3.new(0, 1.8, -2.6), Color3.fromRGB(150, 200, 230), Enum.Material.Glass).Transparency = 0.5
local rodas = Instance.new("Model") rodas.Name = "Wheels" rodas.Parent = car
for _, o in ipairs({ Vector3.new(-3.6, -1.2, -4.5), Vector3.new(3.6, -1.2, -4.5), Vector3.new(-3.6, -1.2, 4.5), Vector3.new(3.6, -1.2, 4.5) }) do
	local w = p("Aro", Vector3.new(0.8, 2.4, 2.4), o, Color3.fromRGB(180, 180, 185), Enum.Material.Metal)
	w.Parent = rodas
end
local seat = Instance.new("VehicleSeat")
seat.Name = "DriveSeat" seat.Size = Vector3.new(2, 1, 2) seat.Anchored = true seat.MaxSpeed = 60 seat.Torque = 10
seat.CFrame = corpo.CFrame * CFrame.new(0, 1.2, -1)
seat.Parent = car
car.PrimaryPart = corpo
car.Parent = workspace
seat:Sit(hum)
check("Jogador sentado no carro de teste", esperar(function() return seat.Occupant == hum end, 5))

-- 5. início do atendimento
Sessoes.Iniciar(player, box)
local s = Sessoes.Ativa(player)
check("Atendimento iniciado pelo motorista dentro do box", s ~= nil and s.car == car)
check("Carro marcado em sessão e fixo no box", car:GetAttribute("OfEmSessao") == player.UserId and seat.Anchored)
check("Peças classificadas (pintura, rodas, vidros)", #Visual.Grupo(car, "p") >= 2 and #Visual.Grupo(car, "r") == 4 and #Visual.Grupo(car, "v") == 1)

-- 6. segurança do remote de compra
local function comprar(c) task.wait(Config.Sessao.EsperaEntreCompras + 0.1) return Sessoes.Comprar(player, c) end
local antes = din.Value
check("Recusa pedido que não é tabela", comprar("x").ok == false)
check("Recusa categoria inexistente", comprar({ hack = true }).ok == false)
check("Recusa preço enviado pelo cliente", comprar({ pintura = { preco = 0, cor = Color3.new(1, 0, 0) } }).ok == false)
check("Recusa nível acima do máximo", comprar({ motor = 99 }).ok == false)
check("Recusa nível fracionário/negativo", comprar({ motor = 1.5 }).ok == false and comprar({ motor = -1 }).ok == false)
check("Recusa opção inválida", comprar({ aerofolio = "foguete" }).ok == false)
check("Nada foi cobrado nas tentativas inválidas", din.Value == antes, din.Value)
din.Value = 100
check("Recusa por saldo insuficiente", comprar({ motor = 4 }).ok == false and din.Value == 100)
din.Value = 5000

-- 7. compra válida: preço calculado no servidor
local cor = Config.Paleta[5].cor
local r = comprar({ pintura = cor, aerofolio = "gt", neon = Config.Paleta[12].cor, motor = 2, vidros = "medio" })
local esperado = 350 + 1100 + 500 + (800 + 1400) + 260
check("Compra válida aceita", r.ok == true, r.erro)
check("Total calculado pelo servidor", r.ok and r.total == esperado, r.total)
check("Saldo debitado exatamente uma vez", din.Value == 5000 - esperado, din.Value)
check("Pintura aplicada na carroceria", corpo.Color == cor)
check("Aerofólio e neon criados no carro", car:FindFirstChild("OfAerofolio") ~= nil and car:FindFirstChild("OfNeon") ~= nil)
check("Insulfilm escureceu o vidro", car.Vidro.Transparency < 0.5)
check("Motor nível 2 com efeito real (MaxSpeed/Torque)", Desempenho.Nivel(car, "motor") == 2 and math.abs(seat.MaxSpeed - 60 * 1.16) < 0.01, seat.MaxSpeed)
check("Recusa recomprar item já instalado", comprar({ aerofolio = "gt" }).ok == false)
check("Recusa rebaixar nível já comprado", comprar({ motor = 1 }).ok == false)
local r2 = comprar({ neon = false })
check("Remoção de neon sem custo", r2.ok and r2.total == 0 and car:FindFirstChild("OfNeon") == nil)

-- 8. encerramento
Sessoes.Encerrar(player, "teste")
check("Encerrar libera o box e o carro", Sessoes.Ativa(player) == nil and car:GetAttribute("OfEmSessao") == nil and box.sessao == nil)
check("Compra sem atendimento é recusada", Sessoes.Comprar(player, { motor = 3 }).ok == false)
-- dono registrado diferente do motorista
car:SetAttribute("Dono", 1)
hum.Sit = false task.wait(0.8) seat:Sit(hum) esperar(function() return seat.Occupant == hum end, 5)
Sessoes.Iniciar(player, box)
check("Veículo de outro dono é recusado", Sessoes.Ativa(player) == nil)
car:SetAttribute("Dono", player.UserId)
Sessoes.Iniciar(player, box)
check("Dono registrado é aceito", Sessoes.Ativa(player) ~= nil)
hum.Sit = false
check("Sair do carro encerra o atendimento", esperar(function() return Sessoes.Ativa(player) == nil end, 5))

-- limpeza do teste
car:Destroy()
din.Value = saldoOriginal
if criouVal then din:Destroy() end
if criouLs then ls:Destroy() end
print("[TESTE OFICINA] ===== avisos/erros no Output =====")
for _, l in ipairs(logs) do print("[TESTE OFICINA] Output: " .. l) end
workspace:SetAttribute("TesteAutomaticoEmExecucao", nil)
print(string.format("[TESTE OFICINA] ===== RESULTADO: %d passaram, %d falharam, %d avisos/erros =====", passou, falhou, #logs))
