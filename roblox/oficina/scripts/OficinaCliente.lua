-- OFICINA • Cliente: interface, câmera de personalização e pré-visualização.
-- A pré-visualização é 100% local (ninguém mais vê e nada é cobrado). Só o servidor aplica de verdade,
-- depois de validar e cobrar. Cancelar/sair sempre restaura o estado anterior do veículo.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local gui = script.Parent
local oficina = gui:WaitForChild("Raiz").Value
local modules = oficina:WaitForChild("Modules")
local Config = require(modules:WaitForChild("Config"))
local Visual = require(modules:WaitForChild("Visual"))
local Desempenho = require(modules:WaitForChild("Desempenho"))
Visual.UsarConfig(Config)
Desempenho.UsarConfig(Config)
local remotes = RS:WaitForChild("OficinaRemotes")
local rSessao = remotes:WaitForChild("Sessao")
local rComprar = remotes:WaitForChild("Comprar")

-- ===== melhorias mecânicas (A-Chassis): ajusta o Tune local a partir dos atributos definidos pelo servidor =====
local function ligarTune(car)
	local function aplicar() pcall(Desempenho.AplicarTuneCliente, car) end
	aplicar()
	for _, id in ipairs(Desempenho.Ids) do
		car:GetAttributeChangedSignal("OfN_" .. id):Connect(aplicar)
	end
end
CollectionService:GetInstanceAddedSignal(Desempenho.Tag):Connect(ligarTune)
for _, car in ipairs(CollectionService:GetTagged(Desempenho.Tag)) do ligarTune(car) end

-- ===== visual =====
local FUNDO = Color3.fromRGB(12, 14, 18)
local PAINEL = Color3.fromRGB(20, 23, 29)
local LINHA = Color3.fromRGB(44, 49, 60)
local DESTAQUE = Color3.fromRGB(255, 140, 30)
local TEXTO = Color3.fromRGB(235, 238, 244)
local FRACO = Color3.fromRGB(150, 158, 172)
local VERDE = Color3.fromRGB(90, 220, 130)
local VERMELHO = Color3.fromRGB(240, 80, 70)

local function novo(classe, props, pai)
	local o = Instance.new(classe)
	for k, v in pairs(props or {}) do o[k] = v end
	if pai then o.Parent = pai end
	return o
end
local function canto(o, r) novo("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
local function borda(o, cor) novo("UIStroke", { Color = cor or LINHA, Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o) end
local function texto(pai, t, tam, cor, fonte, props)
	local l = novo("TextLabel", {
		BackgroundTransparency = 1, Text = t, TextSize = tam, TextColor3 = cor or TEXTO, Font = fonte or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, tam + 6), TextWrapped = true,
	}, pai)
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end
local function botao(pai, t, cor, props)
	local b = novo("TextButton", {
		Text = t, TextSize = 15, Font = Enum.Font.GothamBold, TextColor3 = TEXTO, AutoButtonColor = true,
		BackgroundColor3 = cor or LINHA, Size = UDim2.new(1, 0, 0, 44), BorderSizePixel = 0,
	}, pai)
	canto(b, 8)
	for k, v in pairs(props or {}) do b[k] = v end
	return b
end
local function dinheiro(n)
	local s = tostring(math.floor((n or 0) + 0.5)):reverse():gsub("(%d%d%d)", "%1."):reverse()
	if s:sub(1, 1) == "." then s = s:sub(2) end
	return "R$ " .. s
end
local function som(id)
	if type(id) ~= "string" or id == "" then return end
	pcall(function()
		local s = novo("Sound", { SoundId = id, Volume = 0.5 })
		SoundService:PlayLocalSound(s)
		s:Destroy()
	end)
end

local raiz = novo("Frame", { Name = "Raiz", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, gui)

-- barra superior
local topo = novo("Frame", { BackgroundColor3 = FUNDO, BackgroundTransparency = 0.1, Size = UDim2.new(1, 0, 0, 58), BorderSizePixel = 0 }, raiz)
novo("Frame", { BackgroundColor3 = DESTAQUE, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -3), BorderSizePixel = 0 }, topo)
texto(topo, Config.Nome, 24, DESTAQUE, Enum.Font.GothamBlack, { Position = UDim2.new(0, 18, 0, 8), Size = UDim2.new(0.6, 0, 0, 26) })
texto(topo, Config.Slogan, 12, FRACO, Enum.Font.Gotham, { Position = UDim2.new(0, 18, 0, 34), Size = UDim2.new(0.6, 0, 0, 16) })
local saldoL = texto(topo, "", 20, VERDE, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 16),
	Size = UDim2.new(0.35, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Right })

-- categorias (esquerda)
local esquerda = novo("Frame", { BackgroundColor3 = PAINEL, BackgroundTransparency = 0.06, Position = UDim2.new(0, 14, 0, 72), Size = UDim2.new(0, 230, 1, -86), BorderSizePixel = 0 }, raiz)
canto(esquerda, 10) borda(esquerda)
local listaCat = novo("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6),
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0 }, esquerda)
novo("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, listaCat)

-- carrinho (direita)
local direita = novo("Frame", { BackgroundColor3 = PAINEL, BackgroundTransparency = 0.06, AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 72), Size = UDim2.new(0, 250, 1, -86), BorderSizePixel = 0 }, raiz)
canto(direita, 10) borda(direita)
texto(direita, "PEDIDO", 13, DESTAQUE, Enum.Font.GothamBold, { Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 18) })
local listaCarrinho = novo("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.new(0, 8, 0, 30), Size = UDim2.new(1, -16, 1, -232),
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0 }, direita)
novo("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listaCarrinho)
local rodape = novo("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0, 190) }, direita)
local totalL = texto(rodape, "Total: R$ 0", 18, TEXTO, Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 0, 26) })
local bComprar = botao(rodape, "APLICAR E PAGAR", DESTAQUE, { Position = UDim2.new(0, 0, 0, 34), TextColor3 = Color3.fromRGB(20, 14, 6) })
local bLimpar = botao(rodape, "CANCELAR ALTERAÇÕES", LINHA, { Position = UDim2.new(0, 0, 0, 84) })
local bSair = botao(rodape, "SAIR DA OFICINA", Color3.fromRGB(90, 34, 34), { Position = UDim2.new(0, 0, 0, 134) })

-- opções (embaixo, no centro)
local centro = novo("Frame", { BackgroundColor3 = PAINEL, BackgroundTransparency = 0.06, AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -540, 0, 214), BorderSizePixel = 0 }, raiz)
canto(centro, 10) borda(centro)
local tituloCat = texto(centro, "", 17, TEXTO, Enum.Font.GothamBlack, { Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(1, -150, 0, 22) })
local descCat = texto(centro, "", 12, FRACO, Enum.Font.Gotham, { Position = UDim2.new(0, 14, 0, 30), Size = UDim2.new(1, -150, 0, 16) })
local bVoltar = botao(centro, "VOLTAR", LINHA, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.new(0, 110, 0, 36), TextSize = 13 })
local areaOp = novo("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 52), Size = UDim2.new(1, -20, 1, -60),
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0 }, centro)

-- girar câmera
local bEsq = botao(raiz, "◀", FUNDO, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 258, 0.42, 0), Size = UDim2.new(0, 48, 0, 48), TextSize = 20 })
local bDir = botao(raiz, "▶", FUNDO, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -278, 0.42, 0), Size = UDim2.new(0, 48, 0, 48), TextSize = 20 })

-- aviso (toast) e confirmação
local toast = texto(gui, "", 15, TEXTO, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.new(0, 460, 0, 40), BackgroundTransparency = 0.1, BackgroundColor3 = FUNDO, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 30 })
canto(toast, 8) borda(toast, DESTAQUE)
local toastN = 0
local function avisar(t, cor)
	toastN += 1
	local meu = toastN
	toast.Text = t
	toast.TextColor3 = cor or TEXTO
	toast.Visible = true
	task.delay(3.5, function() if meu == toastN then toast.Visible = false end end)
end

local modal = novo("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 40, Active = true }, raiz)
local caixa = novo("Frame", { BackgroundColor3 = PAINEL, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 380, 0, 200), ZIndex = 41 }, modal)
canto(caixa, 12) borda(caixa, DESTAQUE)
local modalT = texto(caixa, "", 16, TEXTO, Enum.Font.GothamBold, { Position = UDim2.new(0, 20, 0, 18), Size = UDim2.new(1, -40, 0, 96), ZIndex = 42, TextYAlignment = Enum.TextYAlignment.Top })
local bSim = botao(caixa, "CONFIRMAR", DESTAQUE, { Position = UDim2.new(0, 20, 1, -64), Size = UDim2.new(0.5, -26, 0, 46), ZIndex = 42, TextColor3 = Color3.fromRGB(20, 14, 6) })
local bNao = botao(caixa, "VOLTAR", LINHA, { Position = UDim2.new(0.5, 6, 1, -64), Size = UDim2.new(0.5, -26, 0, 46), ZIndex = 42 })

-- escala responsiva: celular e tablet usam a mesma interface, proporcional à tela
local escalas = {}
for _, f in ipairs({ topo, esquerda, direita, centro, bEsq, bDir, caixa, toast }) do
	escalas[f] = novo("UIScale", {}, f)
end
local function layout()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if vp.X < 1 then return end
	local k = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.5, 1)
	for f, s in pairs(escalas) do s.Scale = k end
	esquerda.Position = UDim2.new(0, 14 * k, 0, 72 * k)
	esquerda.Size = UDim2.new(0, 230, 1 / k, -86)
	direita.Position = UDim2.new(1, -14 * k, 0, 72 * k)
	direita.Size = UDim2.new(0, 250, 1 / k, -86)
	centro.Position = UDim2.new(0.5, 0, 1, -14 * k)
	centro.Size = UDim2.new(1 / k, -540, 0, 214)
	topo.Size = UDim2.new(1 / k, 0, 0, 58)
	bEsq.Position = UDim2.new(0, 258 * k, 0.42, 0)
	bDir.Position = UDim2.new(1, -278 * k, 0.42, 0)
end

-- ===== estado da sessão =====
local sessao            -- { car, suporte, estado, niveis, diagnostico }
local carrinho = {}     -- [idCategoria] = valor
local catAtual
local fotos             -- [part] = { Color, Transparency } (estado do servidor antes da pré-visualização)
local angulo, anguloAlvo, camCfg = 35, 35, Config.Cameras.frente
local camAntes

local VISUAIS = { pintura = true, pintura2 = true, rodas = true, vidros = true, neon = true, aerofolio = true, escape = true }

local function fotografar()
	fotos = {}
	for _, d in ipairs(sessao.car:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("OfGrupo") then
			fotos[d] = { d.Color, d.Transparency }
		end
	end
end

local function esconderReal(nome, esconder)
	local f = sessao.car:FindFirstChild(nome)
	if not f then return end
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = esconder and 1 or 0
		elseif d:IsA("Light") then d.Enabled = not esconder end
	end
end

-- volta o carro exatamente ao estado do servidor
local function restaurar()
	if not sessao or not sessao.car.Parent then return end
	for p, f in pairs(fotos or {}) do
		if p.Parent then
			p.Color = f[1]
			p.Transparency = f[2]
		end
	end
	for _, nome in pairs(Visual.Pastas) do
		local prev = sessao.car:FindFirstChild(nome .. "_Previa")
		if prev then prev:Destroy() end
		esconderReal(nome, false)
	end
end

local function previsualizar()
	restaurar()
	for id, valor in pairs(carrinho) do
		if VISUAIS[id] then
			local pasta = Visual.Pastas[id]
			if pasta then esconderReal(pasta, true) end
			pcall(Visual.AplicarCategoria, sessao.car, id, valor ~= false and valor or nil, true)
		end
	end
end

local function precoDe(cat, valor)
	if cat.tipo == "cor" then
		if valor == false then return 0 end
		return Config.NaPaleta(valor) and cat.preco or cat.precoPersonalizada
	elseif cat.tipo == "opcao" then
		local op = Config.Opcao(cat, valor)
		return op and op.preco or 0
	elseif cat.tipo == "nivel" then
		local t = 0
		for n = (sessao.niveis[cat.id] or 0) + 1, valor do t += cat.niveis[n].preco end
		return t
	end
	return cat.preco or 0
end

local function total()
	local t = 0
	for id, valor in pairs(carrinho) do
		local cat = Config.Categoria(id)
		if cat then t += precoDe(cat, valor) end
	end
	return t
end

local function rotulo(cat, valor)
	if cat.tipo == "cor" then
		if valor == false then return "remover" end
		for _, p in ipairs(Config.Paleta) do
			if Config.NaPaleta(valor) and math.abs(p.cor.R - valor.R) < 0.012 and math.abs(p.cor.G - valor.G) < 0.012 and math.abs(p.cor.B - valor.B) < 0.012 then return p.nome end
		end
		return "cor personalizada"
	elseif cat.tipo == "opcao" then
		local op = Config.Opcao(cat, valor)
		return op and op.nome or tostring(valor)
	elseif cat.tipo == "nivel" then
		return "nível " .. valor
	end
	return "serviço"
end

local mostrarCategoria

local function atualizarCarrinho()
	for _, c in ipairs(listaCarrinho:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	local n = 0
	for _, cat in ipairs(Config.Categorias) do
		local valor = carrinho[cat.id]
		if valor ~= nil then
			n += 1
			local b = botao(listaCarrinho, "", FUNDO, { Size = UDim2.new(1, -4, 0, 46), LayoutOrder = n })
			texto(b, cat.nome, 13, TEXTO, Enum.Font.GothamBold, { Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(1, -40, 0, 16) })
			texto(b, rotulo(cat, valor) .. " • " .. dinheiro(precoDe(cat, valor)), 12, FRACO, Enum.Font.Gotham, { Position = UDim2.new(0, 8, 0, 22), Size = UDim2.new(1, -40, 0, 16) })
			texto(b, "✕", 16, VERMELHO, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 20, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
			b.MouseButton1Click:Connect(function()
				carrinho[cat.id] = nil
				previsualizar()
				atualizarCarrinho()
				if catAtual then mostrarCategoria(catAtual) end
			end)
		end
	end
	if n == 0 then
		texto(listaCarrinho, "Escolha uma categoria e experimente. Nada é cobrado até você confirmar.", 12, FRACO, Enum.Font.Gotham, { Size = UDim2.new(1, -4, 0, 60) })
	end
	totalL.Text = "Total: " .. dinheiro(total())
	bComprar.BackgroundColor3 = n > 0 and DESTAQUE or LINHA
end

local function escolher(cat, valor)
	carrinho[cat.id] = valor
	som(Config.Sons.Previa)
	previsualizar()
	atualizarCarrinho()
	mostrarCategoria(cat)
end

local function limparOpcoes()
	for _, c in ipairs(areaOp:GetChildren()) do c:Destroy() end
end

-- seletor de cor livre (matiz, saturação, brilho)
local arrastando
UserInputService.InputChanged:Connect(function(input)
	if arrastando and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		arrastando(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then arrastando = nil end
end)

local function seletorCor(pai, cat, y)
	local h, s, v = 0.05, 0.9, 0.95
	local quadro = novo("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, y), Size = UDim2.new(1, -8, 0, 132) }, pai)
	texto(quadro, "Cor personalizada • " .. dinheiro(cat.precoPersonalizada), 12, FRACO, Enum.Font.GothamBold, { Size = UDim2.new(1, 0, 0, 16) })
	local amostra = novo("Frame", { BackgroundColor3 = Color3.fromHSV(h, s, v), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 22), Size = UDim2.new(0, 96, 0, 54), BorderSizePixel = 0 }, quadro)
	canto(amostra, 8)
	local usar = botao(quadro, "USAR COR", DESTAQUE, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 82), Size = UDim2.new(0, 96, 0, 44), TextSize = 13, TextColor3 = Color3.fromRGB(20, 14, 6) })
	local function barra(i, nome, ini, aoMudar)
		local linha = novo("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = FUNDO, Position = UDim2.new(0, 0, 0, 22 + (i - 1) * 36), Size = UDim2.new(1, -110, 0, 30), BorderSizePixel = 0 }, quadro)
		canto(linha, 6)
		local fill = novo("Frame", { BackgroundColor3 = DESTAQUE, Size = UDim2.fromScale(ini, 1), BorderSizePixel = 0 }, linha)
		canto(fill, 6)
		texto(linha, nome, 12, TEXTO, Enum.Font.GothamBold, { Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(1, -8, 1, 0), ZIndex = 2 })
		local function mover(x)
			local k = math.clamp((x - linha.AbsolutePosition.X) / math.max(linha.AbsoluteSize.X, 1), 0, 1)
			fill.Size = UDim2.fromScale(k, 1)
			aoMudar(k)
			amostra.BackgroundColor3 = Color3.fromHSV(h, s, v)
		end
		linha.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				arrastando = mover
				mover(input.Position.X)
			end
		end)
	end
	barra(1, "Matiz", h, function(k) h = k end)
	barra(2, "Saturação", s, function(k) s = k end)
	barra(3, "Brilho", v, function(k) v = k end)
	usar.MouseButton1Click:Connect(function() escolher(cat, Color3.fromHSV(h, s, v)) end)
	return 132
end

function mostrarCategoria(cat)
	catAtual = cat
	limparOpcoes()
	tituloCat.Text = string.upper(cat.nome)
	descCat.Text = cat.descricao or ""
	camCfg = Config.Cameras[cat.camera or "frente"] or Config.Cameras.frente
	anguloAlvo = camCfg.angulo
	if not sessao.suporte[cat.id] then
		descCat.Text = "Indisponível para este veículo."
		texto(areaOp, cat.tipo == "servico" and "Este veículo não informa danos à oficina (integração com o sistema de dano pendente)."
			or "O modelo deste veículo não tem as peças necessárias para esta personalização.", 13, FRACO, Enum.Font.Gotham, { Size = UDim2.new(1, -8, 0, 40) })
		return
	end
	local escolhido = carrinho[cat.id]
	if cat.tipo == "cor" then
		local grade = novo("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, areaOp)
		novo("UIGridLayout", { CellSize = UDim2.new(0, 54, 0, 46), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grade)
		for i, p in ipairs(Config.Paleta) do
			local b = novo("TextButton", { Text = "", BackgroundColor3 = p.cor, LayoutOrder = i, BorderSizePixel = 0 }, grade)
			canto(b, 8)
			if typeof(escolhido) == "Color3" and math.abs(escolhido.R - p.cor.R) < 0.012 and math.abs(escolhido.G - p.cor.G) < 0.012 and math.abs(escolhido.B - p.cor.B) < 0.012 then
				novo("UIStroke", { Color = DESTAQUE, Thickness = 3 }, b)
			end
			b.MouseButton1Click:Connect(function() escolher(cat, p.cor) end)
		end
		if cat.remover and sessao.estado[cat.id] then
			local b = botao(grade, "REMOVER", Color3.fromRGB(90, 34, 34), { LayoutOrder = 99, TextSize = 10 })
			b.MouseButton1Click:Connect(function() escolher(cat, false) end)
		end
		local linhas = math.ceil((#Config.Paleta + 1) / math.max(1, math.floor((areaOp.AbsoluteSize.X / math.max(escalas[centro].Scale, 0.01)) / 60)))
		descCat.Text = "Paleta • " .. dinheiro(cat.preco) .. "   (toque numa cor para ver no carro)"
		seletorCor(areaOp, cat, linhas * 52 + 8)
	elseif cat.tipo == "opcao" then
		novo("UIGridLayout", { CellSize = UDim2.new(0, 178, 0, 62), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, areaOp)
		for i, op in ipairs(cat.opcoes) do
			local instalado = sessao.estado[cat.id] == op.id
			local b = botao(areaOp, "", escolhido == op.id and Color3.fromRGB(70, 48, 20) or FUNDO, { LayoutOrder = i })
			if escolhido == op.id then borda(b, DESTAQUE) end
			texto(b, op.nome, 14, TEXTO, Enum.Font.GothamBold, { Position = UDim2.new(0, 10, 0, 8), Size = UDim2.new(1, -16, 0, 18) })
			texto(b, instalado and "INSTALADO" or dinheiro(op.preco), 12, instalado and VERDE or FRACO, Enum.Font.GothamBold, { Position = UDim2.new(0, 10, 0, 32), Size = UDim2.new(1, -16, 0, 16) })
			b.MouseButton1Click:Connect(function()
				if instalado then
					carrinho[cat.id] = nil
					previsualizar() atualizarCarrinho() mostrarCategoria(cat)
				else
					escolher(cat, op.id)
				end
			end)
		end
	elseif cat.tipo == "nivel" then
		novo("UIGridLayout", { CellSize = UDim2.new(0, 178, 0, 62), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, areaOp)
		local atual = sessao.niveis[cat.id] or 0
		descCat.Text = (cat.descricao or "") .. " • nível atual: " .. atual .. "/" .. #cat.niveis
		local acumulado = 0
		for n, d in ipairs(cat.niveis) do
			local tem = n <= atual
			if not tem then acumulado += d.preco end
			local b = botao(areaOp, "", escolhido == n and Color3.fromRGB(70, 48, 20) or FUNDO, { LayoutOrder = n, AutoButtonColor = not tem })
			if escolhido == n then borda(b, DESTAQUE) end
			local ganho = d.boost and ("+" .. d.boost .. " psi") or ("+" .. math.floor((d.mult - 1) * 100 + 0.5) .. "%")
			texto(b, "Nível " .. n .. "  " .. ganho, 14, tem and FRACO or TEXTO, Enum.Font.GothamBold, { Position = UDim2.new(0, 10, 0, 8), Size = UDim2.new(1, -16, 0, 18) })
			texto(b, tem and "INSTALADO" or dinheiro(acumulado), 12, tem and VERDE or FRACO, Enum.Font.GothamBold, { Position = UDim2.new(0, 10, 0, 32), Size = UDim2.new(1, -16, 0, 16) })
			if not tem then b.MouseButton1Click:Connect(function() escolher(cat, n) end) end
		end
	elseif cat.tipo == "servico" then
		local d = sessao.diagnostico
		local linha = d.vida and string.format("Diagnóstico: integridade %d / %d", math.floor(d.vida), math.floor(d.max)) or "Diagnóstico: veículo com avarias"
		if not d.danificado then linha = "Diagnóstico: veículo em perfeito estado. Nenhum reparo necessário." end
		texto(areaOp, linha, 14, d.danificado and DESTAQUE or VERDE, Enum.Font.GothamBold, { Size = UDim2.new(1, -8, 0, 24) })
		if d.danificado then
			local b = botao(areaOp, (escolhido and "✓ " or "") .. "REPARO COMPLETO • " .. dinheiro(cat.preco), escolhido and Color3.fromRGB(70, 48, 20) or FUNDO,
				{ Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(0, 300, 0, 48) })
			b.MouseButton1Click:Connect(function()
				if escolhido then carrinho[cat.id] = nil previsualizar() atualizarCarrinho() mostrarCategoria(cat) else escolher(cat, true) end
			end)
		end
	end
end

local function montarCategorias()
	for _, c in ipairs(listaCat:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	local grupo, ordem = nil, 0
	for _, cat in ipairs(Config.Categorias) do
		if cat.grupo ~= grupo then
			grupo = cat.grupo
			ordem += 1
			texto(listaCat, string.upper(grupo), 11, DESTAQUE, Enum.Font.GothamBold, { LayoutOrder = ordem, Size = UDim2.new(1, -6, 0, 20) })
		end
		ordem += 1
		local ok = sessao.suporte[cat.id]
		local b = botao(listaCat, "   " .. cat.nome, FUNDO, { LayoutOrder = ordem, Size = UDim2.new(1, -6, 0, 44), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = ok and TEXTO or Color3.fromRGB(95, 100, 112), TextSize = 14 })
		b.MouseButton1Click:Connect(function()
			som(Config.Sons.Navegar)
			mostrarCategoria(cat)
		end)
	end
end

-- ===== câmera =====
local function atualizarSaldo()
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(Config.Economia.Stat)
	saldoL.Text = v and dinheiro(v.Value) or "Saldo indisponível"
end

local function camera(dt)
	if not sessao or not sessao.car.Parent then return end
	local cam = workspace.CurrentCamera
	local cf, size = sessao.car:GetBoundingBox()
	local raio = math.max(size.X, size.Z)
	local dif = (anguloAlvo - angulo + 540) % 360 - 180
	angulo += dif * math.clamp(dt * 5, 0, 1)
	local a = math.rad(angulo)
	local frente = cf.LookVector * Vector3.new(1, 0, 1)
	if frente.Magnitude < 0.1 then frente = Vector3.new(0, 0, -1) end
	local base = CFrame.lookAt(Vector3.zero, frente.Unit)
	local dir = (base * CFrame.Angles(0, -a, 0)).LookVector
	local alvo = cf.Position + Vector3.new(0, size.Y * 0.05, 0)
	local pos = alvo + dir * raio * camCfg.dist + Vector3.new(0, size.Y * (0.3 + camCfg.altura * 2), 0)
	cam.CFrame = CFrame.lookAt(pos, alvo)
end

local function abrir(dados)
	sessao = dados
	carrinho = {}
	catAtual = nil
	fotografar()
	local cam = workspace.CurrentCamera
	camAntes = { cam.CameraType, cam.CameraSubject, cam.FieldOfView }
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 55
	angulo, anguloAlvo, camCfg = 35, 35, Config.Cameras.frente
	RunService:BindToRenderStep("OficinaCamera", Enum.RenderPriority.Camera.Value + 2, camera)
	layout()
	montarCategorias()
	atualizarCarrinho()
	atualizarSaldo()
	mostrarCategoria(Config.Categorias[1])
	raiz.Visible = true
	modal.Visible = false
	som(Config.Sons.Abrir)
end

local function fechar()
	if not sessao then return end
	pcall(restaurar)
	RunService:UnbindFromRenderStep("OficinaCamera")
	local cam = workspace.CurrentCamera
	if camAntes then
		cam.CameraType = camAntes[1]
		cam.FieldOfView = camAntes[3]
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		cam.CameraSubject = hum or camAntes[2]
	end
	sessao = nil
	carrinho = {}
	raiz.Visible = false
	som(Config.Sons.Fechar)
end

-- ===== ações =====
bEsq.MouseButton1Click:Connect(function() anguloAlvo = (anguloAlvo - 35) % 360 end)
bDir.MouseButton1Click:Connect(function() anguloAlvo = (anguloAlvo + 35) % 360 end)
bVoltar.MouseButton1Click:Connect(function()
	-- volta = desfaz a escolha da categoria aberta
	if catAtual and carrinho[catAtual.id] ~= nil then
		carrinho[catAtual.id] = nil
		previsualizar() atualizarCarrinho() mostrarCategoria(catAtual)
	end
end)
bLimpar.MouseButton1Click:Connect(function()
	carrinho = {}
	previsualizar() atualizarCarrinho()
	if catAtual then mostrarCategoria(catAtual) end
	avisar("Alterações canceladas. O veículo voltou ao estado anterior.")
end)
bSair.MouseButton1Click:Connect(function() rSessao:FireServer("sair") end)
bNao.MouseButton1Click:Connect(function() modal.Visible = false end)
bComprar.MouseButton1Click:Connect(function()
	if next(carrinho) == nil then avisar("Seu pedido está vazio.", FRACO) return end
	modalT.Text = "Confirmar a compra?\n\nTotal: " .. dinheiro(total()) .. "\nAs alterações serão aplicadas ao veículo."
	modal.Visible = true
end)

local comprando = false
bSim.MouseButton1Click:Connect(function()
	if comprando or not sessao then return end
	comprando = true
	modal.Visible = false
	local pedido = table.clone(carrinho)
	-- tira a pré-visualização ANTES de pedir: o que aparecer depois é o estado real vindo do servidor
	restaurar()
	local ok, res = pcall(function() return rComprar:InvokeServer(pedido) end)
	comprando = false
	if not sessao then return end
	if ok and type(res) == "table" and res.ok then
		carrinho = {}
		sessao.suporte, sessao.estado, sessao.niveis, sessao.diagnostico = res.suporte, res.estado, res.niveis, res.diagnostico
		som(Config.Sons.Compra)
		avisar("Compra concluída: " .. dinheiro(res.total) .. ". Alterações aplicadas!", VERDE)
		task.wait(0.35)
		if sessao then
			fotografar()
			atualizarCarrinho()
			atualizarSaldo()
			if catAtual then mostrarCategoria(catAtual) end
		end
	else
		som(Config.Sons.Erro)
		avisar((ok and type(res) == "table" and res.erro) or "Não foi possível concluir a compra.", VERMELHO)
		previsualizar()
	end
end)

rSessao.OnClientEvent:Connect(function(acao, dados)
	if acao == "iniciar" and type(dados) == "table" and dados.car then
		if sessao then fechar() end
		abrir(dados)
	elseif acao == "encerrar" then
		fechar()
	elseif acao == "aviso" and type(dados) == "table" then
		avisar(tostring(dados.texto), dados.tipo == "erro" and VERMELHO or TEXTO)
	end
end)

local vpConn
local function vigiarCamera()
	if vpConn then vpConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if cam then vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
	layout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(vigiarCamera)
vigiarCamera()
task.spawn(function()
	while true do
		task.wait(1)
		if sessao then atualizarSaldo() end
	end
end)
