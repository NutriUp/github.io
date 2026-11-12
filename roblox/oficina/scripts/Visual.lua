-- OFICINA • Personalização visual (módulo compartilhado: servidor aplica de verdade, cliente usa na pré-visualização).
-- Funciona em qualquer modelo de carro: classifica as peças uma vez (carroceria primária/secundária, rodas, vidros)
-- e constrói acessórios (neon, aerofólio, escapamento) medindo o próprio carro. Nada é específico de um modelo.
local RunService = game:GetService("RunService")

local Visual = {}
local Config

function Visual.Init(ctx) Config = ctx.Config end
function Visual.UsarConfig(cfg) Config = cfg end

local PASTAS = { neon = "OfNeon", aerofolio = "OfAerofolio", escape = "OfEscape" }
Visual.Pastas = PASTAS

local function nossa(inst)
	local a = inst
	while a do
		if a:IsA("Folder") and a.Name:sub(1, 2) == "Of" then return true end
		a = a.Parent
	end
	return false
end

local function assento(car)
	local s = car:FindFirstChild("DriveSeat", true)
	if s and s:IsA("VehicleSeat") then return s end
	return car:FindFirstChildWhichIsA("VehicleSeat", true)
end

local function chaveCor(c)
	return math.floor(c.R * 15 + 0.5) * 256 + math.floor(c.G * 15 + 0.5) * 16 + math.floor(c.B * 15 + 0.5)
end

local function area(p)
	local s = p.Size
	return s.X * s.Y + s.Y * s.Z + s.X * s.Z
end

-- ===== classificação (servidor, uma vez por carro) =====
-- Marca cada peça com o atributo OfGrupo: "p" carroceria primária, "s" secundária, "r" rodas, "v" vidros,
-- e guarda cor/transparência de fábrica (OfCor0 / OfTr0).
function Visual.Preparar(car)
	if car:GetAttribute("OfPreparado") then return end
	local rodas = car:FindFirstChild("Wheels") or car:FindFirstChild("Rodas")
	local corpo = {}
	local soma = {}
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") and not nossa(d) and d.Transparency < 0.95 then
			local nome = d.Name:lower()
			local grupo
			if (rodas and d:IsDescendantOf(rodas)) or nome:find("wheel") or nome:find("roda") or nome:find("rim") or nome:find("tire") or nome:find("pneu") then
				-- pneus (muito escuros) ficam de fora: só o aro é pintado
				local _, _, v = d.Color:ToHSV()
				if v > 0.22 or nome:find("rim") or nome:find("aro") then grupo = "r" end
			elseif d.Material == Enum.Material.Glass or nome:find("window") or nome:find("glass") or nome:find("vidro") or nome:find("windshield") then
				grupo = "v"
			elseif d.Material ~= Enum.Material.Neon and not d:IsA("VehicleSeat") and not d:IsA("Seat")
				and not d:FindFirstChildWhichIsA("Light") and d.Transparency < 0.4 then
				table.insert(corpo, d)
				local k = chaveCor(d.Color)
				soma[k] = (soma[k] or 0) + area(d)
			end
			if grupo then
				d:SetAttribute("OfGrupo", grupo)
				d:SetAttribute("OfCor0", d.Color)
				d:SetAttribute("OfTr0", d.Transparency)
			end
		end
	end
	-- cor dominante = pintura primária; segunda cor relevante (≥ 6% da área) = secundária
	local ordem, total = {}, 0
	for k, a in pairs(soma) do
		table.insert(ordem, { k, a })
		total += a
	end
	table.sort(ordem, function(a, b) return a[2] > b[2] end)
	local prim = ordem[1] and ordem[1][1]
	local sec = ordem[2] and ordem[2][2] >= total * 0.06 and ordem[2][1] or nil
	for _, d in ipairs(corpo) do
		local k = chaveCor(d.Color)
		local grupo = (k == prim and "p") or (k == sec and "s") or nil
		if grupo then
			d:SetAttribute("OfGrupo", grupo)
			d:SetAttribute("OfCor0", d.Color)
			d:SetAttribute("OfTr0", d.Transparency)
		end
	end
	car:SetAttribute("OfPreparado", true)
end

function Visual.Grupo(car, grupo)
	local out = {}
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("OfGrupo") == grupo then table.insert(out, d) end
	end
	return out
end

-- quais categorias visuais este carro aceita
function Visual.Suporte(car)
	local n = { p = 0, s = 0, r = 0, v = 0 }
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			local g = d:GetAttribute("OfGrupo")
			if g and n[g] then n[g] += 1 end
		end
	end
	local temAssento = assento(car) ~= nil
	return {
		pintura = n.p > 0, pintura2 = n.s > 0, rodas = n.r > 0, vidros = n.v > 0,
		neon = temAssento, aerofolio = temAssento, escape = temAssento,
	}
end

-- ===== pintura / vidros =====
function Visual.Pintar(car, grupo, cor)
	for _, p in ipairs(Visual.Grupo(car, grupo)) do
		p.Color = cor or p:GetAttribute("OfCor0") or p.Color
	end
end

function Visual.Vidros(car, escuro)
	escuro = math.clamp(escuro or 0, 0, 1)
	for _, p in ipairs(Visual.Grupo(car, "v")) do
		local cor0 = p:GetAttribute("OfCor0") or p.Color
		local tr0 = p:GetAttribute("OfTr0") or p.Transparency
		p.Color = cor0:Lerp(Color3.fromRGB(8, 8, 10), escuro)
		p.Transparency = tr0 * (1 - escuro * 0.92)
	end
end

-- ===== medidas do carro (no espaço do assento do motorista: -Z = frente) =====
function Visual.Medidas(car)
	local seat = assento(car)
	if not seat then return nil end
	local ref = seat.CFrame
	local lo, hi
	local loCorpo
	local rodas = car:FindFirstChild("Wheels") or car:FindFirstChild("Rodas")
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") and not nossa(d) and d.Transparency < 0.95 then
			local c = ref:ToObjectSpace(d.CFrame)
			local s = d.Size / 2
			local ex = math.abs(c.RightVector.X) * s.X + math.abs(c.UpVector.X) * s.Y + math.abs(c.LookVector.X) * s.Z
			local ey = math.abs(c.RightVector.Y) * s.X + math.abs(c.UpVector.Y) * s.Y + math.abs(c.LookVector.Y) * s.Z
			local ez = math.abs(c.RightVector.Z) * s.X + math.abs(c.UpVector.Z) * s.Y + math.abs(c.LookVector.Z) * s.Z
			local e = Vector3.new(ex, ey, ez)
			local a, b = c.Position - e, c.Position + e
			lo = lo and lo:Min(a) or a
			hi = hi and hi:Max(b) or b
			if not (rodas and d:IsDescendantOf(rodas)) then
				loCorpo = loCorpo and math.min(loCorpo, a.Y) or a.Y
			end
		end
	end
	if not lo then return nil end
	return {
		ref = ref, seat = seat, lo = lo, hi = hi,
		largura = hi.X - lo.X, comprimento = hi.Z - lo.Z, altura = hi.Y - lo.Y,
		centroX = (lo.X + hi.X) / 2, chao = lo.Y, baseCorpo = loCorpo or lo.Y,
	}
end

local function limpar(car, nome)
	local f = car:FindFirstChild(nome)
	if f then f:Destroy() end
end

local function peca(pasta, m, props, cfLocal, solto)
	local p = Instance.new("Part")
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	p.CFrame = m.ref * cfLocal
	if solto then
		-- pré-visualização no cliente: o carro está fixo no box, basta ancorar
		p.Anchored = true
	else
		p.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0 = p
		w.Part1 = m.seat
		w.Parent = p
	end
	p.Parent = pasta
	return p
end

-- altura da "tampa traseira": raio para baixo sobre a traseira do carro
local function alturaTraseira(car, m)
	local lista = {}
	for _, c in ipairs(car:GetChildren()) do
		if not (c:IsA("Folder") and c.Name:sub(1, 2) == "Of") then table.insert(lista, c) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = lista
	local origem = m.ref * Vector3.new(m.centroX, m.hi.Y + 3, m.hi.Z - math.min(1.6, m.comprimento * 0.1))
	local r = workspace:Raycast(origem, m.ref:VectorToWorldSpace(Vector3.new(0, -(m.altura + 6), 0)), params)
	if r then return m.ref:PointToObjectSpace(r.Position).Y end
	return m.lo.Y + m.altura * 0.62
end

-- ===== neon =====
-- cor = Color3 ou nil (remove). nome/solto servem à pré-visualização do cliente.
function Visual.Neon(car, cor, nome, solto)
	nome = nome or PASTAS.neon
	limpar(car, nome)
	if not cor then return nil end
	local m = Visual.Medidas(car)
	if not m then return nil end
	local pasta = Instance.new("Folder")
	pasta.Name = nome
	local y = m.baseCorpo + 0.12
	local L, W = m.comprimento * 0.72, m.largura * 0.78
	local cz = (m.lo.Z + m.hi.Z) / 2
	local props = { Material = Enum.Material.Neon, Color = cor, Name = "Neon" }
	local function tira(size, pos)
		local p = peca(pasta, m, props, CFrame.new(pos), solto)
		p.Size = size
		return p
	end
	tira(Vector3.new(0.18, 0.18, L), Vector3.new(m.centroX - W / 2, y, cz))
	tira(Vector3.new(0.18, 0.18, L), Vector3.new(m.centroX + W / 2, y, cz))
	tira(Vector3.new(W, 0.18, 0.18), Vector3.new(m.centroX, y, cz - L / 2))
	local centro = tira(Vector3.new(W, 0.18, 0.18), Vector3.new(m.centroX, y, cz + L / 2))
	local luz = Instance.new("PointLight")
	luz.Color = cor
	luz.Range = math.clamp(m.comprimento * 0.9, 10, 22)
	luz.Brightness = 2.2
	luz.Shadows = false
	luz.Parent = centro
	local luz2 = luz:Clone()
	luz2.Parent = pasta:GetChildren()[3]
	pasta.Parent = car
	return pasta
end

-- ===== aerofólio =====
function Visual.Aerofolio(car, id, nome, solto)
	nome = nome or PASTAS.aerofolio
	limpar(car, nome)
	if not id or id == "nenhum" then return nil end
	local m = Visual.Medidas(car)
	if not m then return nil end
	local pasta = Instance.new("Folder")
	pasta.Name = nome
	local deck = alturaTraseira(car, m)
	local z = m.hi.Z - math.min(1.4, m.comprimento * 0.09)
	local W = m.largura
	local preto = { Color = Color3.fromRGB(22, 22, 24), Material = Enum.Material.SmoothPlastic, Name = "Aerofolio" }
	local function bloco(size, pos, ang)
		local p = peca(pasta, m, preto, CFrame.new(pos) * CFrame.Angles(math.rad(ang or 0), 0, 0), solto)
		p.Size = size
		return p
	end
	if id == "lip" then
		bloco(Vector3.new(W * 0.82, 0.16, 0.7), Vector3.new(m.centroX, deck + 0.12, z), -8)
	elseif id == "esportivo" then
		local h = 0.75
		for _, s in ipairs({ -1, 1 }) do
			bloco(Vector3.new(0.14, h, 0.5), Vector3.new(m.centroX + s * W * 0.28, deck + h / 2, z))
		end
		bloco(Vector3.new(W * 0.86, 0.14, 1.05), Vector3.new(m.centroX, deck + h + 0.05, z + 0.05), -6)
	elseif id == "gt" then
		local h = 1.35
		for _, s in ipairs({ -1, 1 }) do
			bloco(Vector3.new(0.16, h, 0.7), Vector3.new(m.centroX + s * W * 0.24, deck + h / 2, z))
			bloco(Vector3.new(0.1, 0.75, 1.5), Vector3.new(m.centroX + s * W * 0.5, deck + h + 0.1, z + 0.1))
		end
		bloco(Vector3.new(W, 0.16, 1.35), Vector3.new(m.centroX, deck + h + 0.05, z + 0.1), -5)
	else
		pasta:Destroy()
		return nil
	end
	pasta.Parent = car
	return pasta
end

-- ===== escapamento =====
function Visual.Escape(car, id, nome, solto)
	nome = nome or PASTAS.escape
	limpar(car, nome)
	if not id or id == "original" then return nil end
	local m = Visual.Medidas(car)
	if not m then return nil end
	local pasta = Instance.new("Folder")
	pasta.Name = nome
	local y = m.baseCorpo + 0.38
	local z = m.hi.Z + 0.05
	local cromado = { Color = Color3.fromRGB(190, 192, 198), Material = Enum.Material.Metal, Reflectance = 0.25, Shape = Enum.PartType.Cylinder, Name = "Ponteira" }
	local function ponteira(x, d)
		local p = peca(pasta, m, cromado, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(90), 0), solto)
		p.Size = Vector3.new(0.9, d, d)
		local miolo = peca(pasta, m, { Color = Color3.fromRGB(12, 12, 12), Shape = Enum.PartType.Cylinder, Name = "Miolo" },
			CFrame.new(x, y, z + 0.06) * CFrame.Angles(0, math.rad(90), 0), solto)
		miolo.Size = Vector3.new(0.82, d * 0.72, d * 0.72)
	end
	local W = m.largura
	if id == "duplo" then
		ponteira(m.centroX - W * 0.3, 0.42)
		ponteira(m.centroX + W * 0.3, 0.42)
	elseif id == "quadruplo" then
		for _, s in ipairs({ -1, 1 }) do
			ponteira(m.centroX + s * W * 0.34, 0.46)
			ponteira(m.centroX + s * (W * 0.34 - 0.55), 0.46)
		end
	else
		pasta:Destroy()
		return nil
	end
	pasta.Parent = car
	return pasta
end

-- ===== estado salvo no carro (atributos) =====
-- OfPintura / OfPintura2 / OfRodas / OfNeon : Color3   OfVidros / OfAerofolio / OfEscape : id da opção
function Visual.LerEstado(car)
	return {
		pintura = car:GetAttribute("OfPintura"), pintura2 = car:GetAttribute("OfPintura2"),
		rodas = car:GetAttribute("OfRodas"), neon = car:GetAttribute("OfNeon"),
		vidros = car:GetAttribute("OfVidros") or "original",
		aerofolio = car:GetAttribute("OfAerofolio") or "nenhum",
		escape = car:GetAttribute("OfEscape") or "original",
	}
end

-- aplica uma categoria. solto/sufixo = pré-visualização local (não toca nos acessórios reais).
function Visual.AplicarCategoria(car, id, valor, previa)
	local sufixo = previa and "_Previa" or ""
	if id == "pintura" then
		Visual.Pintar(car, "p", valor)
	elseif id == "pintura2" then
		Visual.Pintar(car, "s", valor)
	elseif id == "rodas" then
		Visual.Pintar(car, "r", valor)
	elseif id == "vidros" then
		local cat = Config.Categoria("vidros")
		local op = cat and Config.Opcao(cat, valor)
		Visual.Vidros(car, op and op.escuro or 0)
	elseif id == "neon" then
		Visual.Neon(car, typeof(valor) == "Color3" and valor or nil, PASTAS.neon .. sufixo, previa)
	elseif id == "aerofolio" then
		Visual.Aerofolio(car, valor, PASTAS.aerofolio .. sufixo, previa)
	elseif id == "escape" then
		Visual.Escape(car, valor, PASTAS.escape .. sufixo, previa)
	end
end

-- reaplica tudo a partir dos atributos (servidor; também serve para restaurar um carro salvo no futuro)
function Visual.AplicarEstado(car)
	local e = Visual.LerEstado(car)
	if e.pintura then Visual.Pintar(car, "p", e.pintura) end
	if e.pintura2 then Visual.Pintar(car, "s", e.pintura2) end
	if e.rodas then Visual.Pintar(car, "r", e.rodas) end
	Visual.AplicarCategoria(car, "vidros", e.vidros)
	Visual.Neon(car, e.neon)
	Visual.Aerofolio(car, e.aerofolio)
	Visual.Escape(car, e.escape)
end

Visual.EhServidor = RunService:IsServer()

return Visual
