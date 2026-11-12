-- OFICINA • Atendimentos (somente servidor). Um box atende um jogador por vez; cada jogador só mexe no
-- veículo que está dirigindo. Toda compra é validada e precificada aqui — o cliente só envia "o que quer".
local Players = game:GetService("Players")

local Sessoes = {}
local ctx, Config, Veiculos, Visual, Desempenho, Economia
local boxes = {}          -- [i] = { zona, console, prompt, sessao }
local porJogador = {}     -- [player] = sessao

local function aviso(player, tipo, texto)
	if player and player.Parent then ctx.Remotes.Sessao:FireClient(player, "aviso", { tipo = tipo, texto = texto }) end
end

local function dentro(zona, pos)
	local p = zona.CFrame:PointToObjectSpace(pos)
	local s = zona.Size / 2
	return math.abs(p.X) <= s.X and math.abs(p.Z) <= s.Z and math.abs(p.Y) <= s.Y + 6
end

local function niveis(car)
	local t = {}
	for _, id in ipairs(Desempenho.Ids) do t[id] = Desempenho.Nivel(car, id) end
	return t
end

local function resumo(car)
	local sup = Visual.Suporte(car)
	for k, v in pairs(Desempenho.Suporte(car)) do sup[k] = v end
	local diag = Veiculos.Diagnostico(car)
	sup.reparo = diag.suportado
	return { suporte = sup, estado = Visual.LerEstado(car), niveis = niveis(car), diagnostico = diag, tipo = Veiculos.Tipo(car) }
end

-- ===== encerrar =====
function Sessoes.Encerrar(player, motivo)
	local s = porJogador[player]
	if not s then return end
	porJogador[player] = nil
	s.box.sessao = nil
	if s.box.prompt then s.box.prompt.Enabled = true end
	local car = s.car
	if car and car.Parent then
		car:SetAttribute("OfEmSessao", nil)
		Veiculos.Fixar(car, false, player)
		if s.mudouMecanica and player.Parent then Veiculos.Reassentar(car, player) end
	end
	if player.Parent then
		ctx.Remotes.Sessao:FireClient(player, "encerrar", { motivo = motivo })
	end
	ctx.Estado(s.box)
end

-- ===== iniciar =====
function Sessoes.Iniciar(player, box)
	if porJogador[player] then return end
	if box.sessao then aviso(player, "aviso", "Este box já está em atendimento.") return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not hum or hum.Health <= 0 or not seat or not seat:IsA("VehicleSeat") then
		aviso(player, "aviso", "Traga seu veículo: dirija até o box e fique no volante.")
		return
	end
	local car = Veiculos.DoAssento(seat)
	if not car then aviso(player, "aviso", "Veículo não reconhecido pela oficina.") return end
	if Veiculos.AssentoMotorista(car) ~= seat then aviso(player, "aviso", "Só o motorista pode iniciar o atendimento.") return end
	if not dentro(box.zona, seat.Position) then aviso(player, "aviso", "Posicione o veículo dentro do box (faixas amarelas).") return end
	if seat.AssemblyLinearVelocity.Magnitude > Config.Sessao.VelocidadeMaxima then aviso(player, "aviso", "Pare o veículo para iniciar.") return end
	if car:GetAttribute("OfEmSessao") then aviso(player, "aviso", "Este veículo já está em atendimento.") return end
	local pode, por = Veiculos.PodeUsar(player, car)
	if not pode then aviso(player, "erro", por) return end

	local okPrep, errPrep = pcall(Visual.Preparar, car)
	if not okPrep then warn("[Oficina] falha ao preparar veículo: " .. tostring(errPrep)) aviso(player, "erro", "Não foi possível analisar este veículo.") return end

	local s = { player = player, car = car, seat = seat, box = box, inicio = os.clock(), ultimaCompra = 0, ocupado = false, mudouMecanica = false }
	box.sessao = s
	porJogador[player] = s
	car:SetAttribute("OfEmSessao", player.UserId)
	Veiculos.Fixar(car, true)
	if box.prompt then box.prompt.Enabled = false end
	local dados = resumo(car)
	dados.car = car
	dados.box = box.indice
	dados.saldo = Economia.Saldo(player)
	ctx.Remotes.Sessao:FireClient(player, "iniciar", dados)
	ctx.Estado(box)
end

-- ===== compra =====
-- devolve (preço, valorNormalizado) ou (nil, motivo)
local function avaliar(car, cat, valor, info)
	if not info.suporte[cat.id] then return nil, cat.nome .. " não está disponível para este veículo." end
	if cat.tipo == "cor" then
		if valor == false then
			if not cat.remover then return nil, "opção inválida" end
			if not info.estado[cat.id] then return nil, cat.nome .. ": nada para remover." end
			return 0, false
		end
		if typeof(valor) ~= "Color3" then return nil, "cor inválida" end
		local cor = Color3.new(math.clamp(valor.R, 0, 1), math.clamp(valor.G, 0, 1), math.clamp(valor.B, 0, 1))
		return Config.NaPaleta(cor) and cat.preco or cat.precoPersonalizada, cor
	elseif cat.tipo == "opcao" then
		if type(valor) ~= "string" then return nil, "opção inválida" end
		local op = Config.Opcao(cat, valor)
		if not op then return nil, "opção inválida" end
		if info.estado[cat.id] == op.id then return nil, cat.nome .. ": já instalado." end
		return op.preco, op.id
	elseif cat.tipo == "nivel" then
		if type(valor) ~= "number" or valor % 1 ~= 0 then return nil, "nível inválido" end
		local atual = info.niveis[cat.id] or 0
		if valor <= atual or valor > #cat.niveis then return nil, cat.nome .. ": nível indisponível." end
		local total = 0
		for n = atual + 1, valor do total += cat.niveis[n].preco end
		return total, valor
	elseif cat.tipo == "servico" then
		if valor ~= true then return nil, "opção inválida" end
		if not info.diagnostico.suportado then return nil, "Reparo indisponível para este veículo." end
		if not info.diagnostico.danificado then return nil, "O veículo não precisa de reparo." end
		return cat.preco, true
	end
	return nil, "categoria inválida"
end

local ATRIBUTO = { pintura = "OfPintura", pintura2 = "OfPintura2", rodas = "OfRodas", neon = "OfNeon",
	vidros = "OfVidros", aerofolio = "OfAerofolio", escape = "OfEscape" }

local function aplicar(s, cat, valor)
	local car = s.car
	if cat.tipo == "nivel" then
		car:SetAttribute("OfN_" .. cat.id, valor)
		Desempenho.AplicarServidor(car)
		s.mudouMecanica = true
	elseif cat.tipo == "servico" then
		Veiculos.Reparar(car)
	else
		car:SetAttribute(ATRIBUTO[cat.id], valor ~= false and valor or nil)
		Visual.AplicarCategoria(car, cat.id, valor ~= false and valor or nil)
	end
end

function Sessoes.Comprar(player, carrinho)
	local s = porJogador[player]
	if not s then return { ok = false, erro = "Nenhum atendimento em andamento." } end
	if s.ocupado then return { ok = false, erro = "Compra em processamento." } end
	if os.clock() - s.ultimaCompra < Config.Sessao.EsperaEntreCompras then return { ok = false, erro = "Aguarde um instante." } end
	if type(carrinho) ~= "table" then return { ok = false, erro = "Pedido inválido." } end
	local car = s.car
	if not car.Parent or s.seat.Occupant == nil or not dentro(s.box.zona, s.seat.Position) then
		Sessoes.Encerrar(player, "veículo fora do box")
		return { ok = false, erro = "Atendimento encerrado." }
	end
	s.ocupado = true
	local resposta
	local okExec, errExec = pcall(function()
		local info = resumo(car)
		local itens, total, n = {}, 0, 0
		for id, valor in pairs(carrinho) do
			n += 1
			if n > Config.Sessao.MaxItensCarrinho then resposta = { ok = false, erro = "Itens demais no pedido." } return end
			local cat = type(id) == "string" and Config.Categoria(id) or nil
			if not cat then resposta = { ok = false, erro = "Item desconhecido." } return end
			local preco, norm = avaliar(car, cat, valor, info)
			if not preco then resposta = { ok = false, erro = norm } return end
			table.insert(itens, { cat = cat, valor = norm })
			total += preco
		end
		if #itens == 0 then resposta = { ok = false, erro = "Carrinho vazio." } return end
		local saldo = Economia.Saldo(player)
		if total > 0 then
			if saldo == nil then resposta = { ok = false, erro = "Economia indisponível no momento." } return end
			if saldo < total then resposta = { ok = false, erro = "Saldo insuficiente." } return end
			local pago, motivo = Economia.Cobrar(player, total, "oficina")
			if not pago then resposta = { ok = false, erro = "Pagamento recusado: " .. tostring(motivo) } return end
		end
		for _, it in ipairs(itens) do
			local okA, errA = pcall(aplicar, s, it.cat, it.valor)
			if not okA then warn("[Oficina] erro ao aplicar " .. it.cat.id .. ": " .. tostring(errA)) end
		end
		s.ultimaCompra = os.clock()
		local novo = resumo(car)
		novo.ok = true
		novo.total = total
		novo.saldo = Economia.Saldo(player)
		resposta = novo
		ctx.Util.Som(s.box.console, Config.Sons.Compra, 0.7)
	end)
	s.ocupado = false
	if not okExec then
		warn("[Oficina] erro na compra: " .. tostring(errExec))
		return { ok = false, erro = "Erro interno ao processar o pedido." }
	end
	return resposta
end

-- ===== inicialização =====
function Sessoes.Ativa(player) return porJogador[player] end
function Sessoes.Boxes() return boxes end

function Sessoes.Init(c)
	ctx = c
	Config, Veiculos, Visual, Desempenho, Economia = c.Config, c.Veiculos, c.Visual, c.Desempenho, c.Economia
	local i = 1
	while true do
		local zona = ctx.Objetos:FindFirstChild("Box_" .. i)
		local console = ctx.Objetos:FindFirstChild("Console_" .. i)
		if not zona or not console then break end
		local box = { indice = i, zona = zona, console = console }
		zona.Transparency = 1
		zona.CanCollide = false
		zona.CanQuery = false
		zona.CanTouch = false
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Iniciar atendimento"
		pp.ObjectText = Config.Nome .. " • Box " .. i
		pp.HoldDuration = 0.5
		pp.MaxActivationDistance = 22
		pp.RequiresLineOfSight = false
		pp.Parent = console
		pp.Triggered:Connect(function(player) Sessoes.Iniciar(player, box) end)
		box.prompt = pp
		boxes[i] = box
		i += 1
	end
	if #boxes == 0 then warn("[Oficina] nenhum box encontrado (OficinaObjetos.Box_N + Console_N)") end

	ctx.Remotes.Sessao.OnServerEvent:Connect(function(player, acao)
		if acao == "sair" then Sessoes.Encerrar(player, "encerrado pelo cliente") end
	end)
	ctx.Remotes.Comprar.OnServerInvoke = function(player, carrinho)
		local ok, res = pcall(Sessoes.Comprar, player, carrinho)
		if ok then return res end
		warn("[Oficina] erro no remote Comprar: " .. tostring(res))
		return { ok = false, erro = "Erro interno." }
	end
	Players.PlayerRemoving:Connect(function(player) Sessoes.Encerrar(player, "jogador saiu") end)

	-- vigia: encerra se o motorista sair do carro, morrer, o carro sumir/sair do box ou o tempo acabar
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, s in pairs(table.clone(porJogador)) do
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				local motivo
				if not player.Parent then motivo = "jogador saiu"
				elseif not s.car.Parent or not s.seat.Parent then motivo = "veículo removido"
				elseif not hum or hum.Health <= 0 or s.seat.Occupant ~= hum then motivo = "motorista saiu do veículo"
				elseif os.clock() - s.inicio > Config.Sessao.TempoMaximo then motivo = "tempo esgotado"
				end
				if motivo and not s.ocupado then Sessoes.Encerrar(player, motivo) end
			end
		end
	end)
end

return Sessoes
