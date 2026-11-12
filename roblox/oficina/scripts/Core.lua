-- OFICINA • Núcleo. Cria os remotes, inicia os módulos e instala a interface em cada jogador.
-- Estrutura: <modelo da oficina>/{ ...cenário original..., OficinaObjetos (boxes, consoles, mobília), Oficina/{ Core, Modules, Client } }
-- Não depende de nada fora do modelo; integrações (economia, dono do veículo, reparo) ficam em Modules/Config,
-- Economia.DefinirProvedor e Veiculos.DefinirReparo.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local oficina = script.Parent
local modelo = oficina.Parent
local objetos = modelo:WaitForChild("OficinaObjetos")
local modules = oficina:WaitForChild("Modules")

local Config = require(modules.Config)

local remotes = RS:FindFirstChild("OficinaRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "OficinaRemotes"
	remotes.Parent = RS
end
local function remote(classe, nome)
	local r = remotes:FindFirstChild(nome)
	if not r then
		r = Instance.new(classe)
		r.Name = nome
		r.Parent = remotes
	end
	return r
end

local Util = {}
-- som opcional: ID vazio/inválido nunca gera erro
function Util.Som(parent, id, volume)
	if type(id) == "number" then id = "rbxassetid://" .. id end
	if type(id) ~= "string" or id == "" or not parent then return nil end
	local ok, s = pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume or 0.6
		s.RollOffMaxDistance = 90
		s.Parent = parent
		s:Play()
		Debris:AddItem(s, 15)
		return s
	end)
	return ok and s or nil
end

local ctx = {
	Oficina = oficina, Modelo = modelo, Objetos = objetos, Config = Config, Util = Util,
	Remotes = { Sessao = remote("RemoteEvent", "Sessao"), Comprar = remote("RemoteFunction", "Comprar") },
}

-- telas dos consoles (LIVRE / EM ATENDIMENTO)
local telas = {}
function ctx.Estado(box)
	local t = telas[box.indice]
	if not t then return end
	if box.sessao then
		t.Text = "EM ATENDIMENTO\n" .. box.sessao.player.DisplayName
		t.TextColor3 = Color3.fromRGB(255, 190, 60)
	else
		t.Text = "BOX " .. box.indice .. " LIVRE\nEstacione e segure E"
		t.TextColor3 = Color3.fromRGB(90, 255, 140)
	end
end

local ordem = { "Economia", "Veiculos", "Visual", "Desempenho", "Portoes", "Sessoes" }
for _, nome in ipairs(ordem) do
	local ms = modules:FindFirstChild(nome)
	if ms then
		local ok, mod = pcall(require, ms)
		if ok then ctx[nome] = mod else warn("[Oficina] falha ao carregar " .. nome .. ": " .. tostring(mod)) end
	else
		warn("[Oficina] módulo ausente: " .. nome)
	end
end
for _, nome in ipairs(ordem) do
	local mod = ctx[nome]
	if mod and mod.Init then
		local ok, err = pcall(mod.Init, ctx)
		if not ok then warn("[Oficina] erro em " .. nome .. ".Init: " .. tostring(err)) end
	end
end

-- telas dos consoles
if ctx.Sessoes then
	for _, box in ipairs(ctx.Sessoes.Boxes()) do
		local tela = box.console:FindFirstChild("Tela") or box.console
		local sg = Instance.new("SurfaceGui")
		sg.Name = "TelaOficina"
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.Parent = tela
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.Parent = sg
		telas[box.indice] = l
		ctx.Estado(box)
	end
end

-- interface do cliente
local template = oficina:FindFirstChild("Client") and oficina.Client:FindFirstChild("OficinaCliente")
local function instalar(player)
	task.spawn(function()
		if not template then return end
		local pg = player:WaitForChild("PlayerGui", 30)
		if not pg or pg:FindFirstChild("OficinaUI") then return end
		local gui = Instance.new("ScreenGui")
		gui.Name = "OficinaUI"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 20
		local raiz = Instance.new("ObjectValue")
		raiz.Name = "Raiz"
		raiz.Value = oficina
		raiz.Parent = gui
		template:Clone().Parent = gui
		gui.Parent = pg
	end)
end
if not template then warn("[Oficina] interface ausente: Oficina.Client.OficinaCliente") end
Players.PlayerAdded:Connect(instalar)
for _, p in ipairs(Players:GetPlayers()) do instalar(p) end

print(string.format("[Oficina] %s ativa: %d box(es), %d portão(ões) automático(s)", Config.Nome,
	ctx.Sessoes and #ctx.Sessoes.Boxes() or 0, ctx.Portoes and ctx.Portoes.Quantidade() or 0))
