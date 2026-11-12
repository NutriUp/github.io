-- OFICINA • Configuração central: identidade, preços, categorias, níveis de melhoria e integrações.
-- Tudo que é preço/opção é lido SOMENTE daqui pelo servidor. O cliente usa este módulo apenas para exibir.
local Config = {}

Config.Nome = "TORQUE CUSTOMS"
Config.Slogan = "Pintura • Performance • Reparo"

-- ===== Economia (usa a moeda que já existe no jogo; a oficina nunca cria leaderstats nem DataStore) =====
Config.Economia = {
	Stat = "Dinheiro",   -- leaderstats.Dinheiro (mesma moeda do posto, OilRig e polícia)
}

-- ===== Atendimento =====
Config.Sessao = {
	TempoMaximo = 300,        -- segundos até o atendimento encerrar sozinho
	VelocidadeMaxima = 8,     -- o carro precisa estar praticamente parado no box
	EsperaEntreCompras = 1,   -- antiflood do remote de compra (s)
	MaxItensCarrinho = 12,
}

-- ===== Dono do veículo =====
-- A oficina procura um dono registrado no modelo do carro (atributos / valores abaixo).
-- Se o sistema de veículos do jogo não registrar dono, vale quem está dirigindo ao iniciar o atendimento.
-- (CarSpawning não pôde ser inspecionado: ajuste os nomes aqui se ele usar outro.)
Config.Dono = {
	Atributos = { "Dono", "Owner", "OwnerId", "OwnerUserId", "DonoUserId", "UserId" },
	Valores = { "Dono", "Owner" },          -- ObjectValue (Player), IntValue (UserId) ou StringValue (nome)
	AceitarMotoristaSemDono = true,
}

-- ===== Portões automáticos =====
Config.Portoes = { RaioAbrir = 34, Tempo = 1.3, FecharApos = 3 }

-- ===== Paleta de pintura (qualquer cor fora dela é "personalizada") =====
Config.Paleta = {
	{ nome = "Preto Ônix", cor = Color3.fromRGB(17, 17, 19) },
	{ nome = "Grafite", cor = Color3.fromRGB(58, 60, 66) },
	{ nome = "Prata", cor = Color3.fromRGB(170, 174, 180) },
	{ nome = "Branco Pérola", cor = Color3.fromRGB(240, 240, 236) },
	{ nome = "Vermelho Torque", cor = Color3.fromRGB(196, 28, 32) },
	{ nome = "Vinho", cor = Color3.fromRGB(96, 18, 30) },
	{ nome = "Laranja", cor = Color3.fromRGB(240, 110, 20) },
	{ nome = "Amarelo", cor = Color3.fromRGB(245, 200, 30) },
	{ nome = "Verde Limão", cor = Color3.fromRGB(140, 220, 40) },
	{ nome = "Verde Inglês", cor = Color3.fromRGB(20, 80, 50) },
	{ nome = "Turquesa", cor = Color3.fromRGB(30, 180, 170) },
	{ nome = "Azul Elétrico", cor = Color3.fromRGB(30, 110, 240) },
	{ nome = "Azul Marinho", cor = Color3.fromRGB(18, 34, 80) },
	{ nome = "Roxo", cor = Color3.fromRGB(110, 50, 190) },
	{ nome = "Rosa", cor = Color3.fromRGB(235, 80, 160) },
	{ nome = "Bronze", cor = Color3.fromRGB(150, 100, 60) },
}

-- ===== Categorias =====
-- tipo "cor": valor = Color3 (preco para cor da paleta, precoPersonalizada para cor livre; remover = false quando permitido)
-- tipo "opcao": valor = id de uma das opcoes
-- tipo "nivel": valor = nível desejado (paga-se a soma dos níveis que faltam)
-- tipo "servico": valor = true
Config.Categorias = {
	{ id = "pintura", nome = "Pintura", grupo = "Visual", tipo = "cor", preco = 350, precoPersonalizada = 600, camera = "frente" },
	{ id = "pintura2", nome = "Pintura secundária", grupo = "Visual", tipo = "cor", preco = 250, precoPersonalizada = 450, camera = "lado" },
	{ id = "rodas", nome = "Rodas e aros", grupo = "Visual", tipo = "cor", preco = 220, precoPersonalizada = 380, camera = "roda" },
	{ id = "vidros", nome = "Insulfilm", grupo = "Visual", tipo = "opcao", camera = "lado", opcoes = {
		{ id = "original", nome = "Original", preco = 0, escuro = 0 },
		{ id = "leve", nome = "Leve", preco = 150, escuro = 0.35 },
		{ id = "medio", nome = "Médio", preco = 260, escuro = 0.6 },
		{ id = "limusine", nome = "Limusine", preco = 400, escuro = 0.88 },
	} },
	{ id = "neon", nome = "Neon inferior", grupo = "Visual", tipo = "cor", preco = 500, precoPersonalizada = 700, remover = true, camera = "baixo" },
	{ id = "aerofolio", nome = "Aerofólio", grupo = "Visual", tipo = "opcao", camera = "tras", opcoes = {
		{ id = "nenhum", nome = "Sem aerofólio", preco = 0 },
		{ id = "lip", nome = "Lip discreto", preco = 300 },
		{ id = "esportivo", nome = "Esportivo", preco = 650 },
		{ id = "gt", nome = "GT de pista", preco = 1100 },
	} },
	{ id = "escape", nome = "Escapamento", grupo = "Visual", tipo = "opcao", camera = "tras", opcoes = {
		{ id = "original", nome = "Original", preco = 0 },
		{ id = "duplo", nome = "Ponteira dupla", preco = 280 },
		{ id = "quadruplo", nome = "Quádruplo esportivo", preco = 520 },
	} },
	-- mecânica: efeito real (ver módulo Desempenho). "campo" descreve o que muda em cada tipo de veículo.
	{ id = "motor", nome = "Motor", grupo = "Mecânica", tipo = "nivel", camera = "frente", descricao = "Mais potência",
		niveis = { { preco = 800, mult = 1.08 }, { preco = 1400, mult = 1.16 }, { preco = 2200, mult = 1.25 }, { preco = 3400, mult = 1.35 } } },
	{ id = "turbo", nome = "Turbo", grupo = "Mecânica", tipo = "nivel", camera = "frente", descricao = "Pressão extra de turbo",
		niveis = { { preco = 1200, boost = 4, mult = 1.06 }, { preco = 2000, boost = 8, mult = 1.12 }, { preco = 3200, boost = 12, mult = 1.18 } } },
	{ id = "transmissao", nome = "Transmissão", grupo = "Mecânica", tipo = "nivel", camera = "lado", descricao = "Relação final mais curta: acelera mais",
		niveis = { { preco = 600, mult = 1.05 }, { preco = 1000, mult = 1.10 }, { preco = 1600, mult = 1.16 } } },
	{ id = "freios", nome = "Freios", grupo = "Mecânica", tipo = "nivel", camera = "roda", descricao = "Mais força de frenagem",
		niveis = { { preco = 500, mult = 1.15 }, { preco = 900, mult = 1.30 }, { preco = 1500, mult = 1.50 } } },
	{ id = "suspensao", nome = "Suspensão", grupo = "Mecânica", tipo = "nivel", camera = "roda", descricao = "Molas e amortecedores mais firmes",
		niveis = { { preco = 450, mult = 1.15 }, { preco = 800, mult = 1.30 }, { preco = 1300, mult = 1.45 } } },
	{ id = "reparo", nome = "Reparo completo", grupo = "Serviços", tipo = "servico", preco = 300, camera = "frente",
		descricao = "Restaura a integridade do veículo" },
}

-- ===== Reparo / diagnóstico =====
-- VehicleDamage não pôde ser inspecionado. A oficina só oferece reparo quando encontra a vida do veículo
-- em um destes atributos (no modelo) ou quando um sistema registra a função com Veiculos.DefinirReparo(...).
Config.Reparo = {
	AtributosVida = { "Vida", "Health", "Saude", "Durabilidade", "VehicleHealth" },
	AtributosVidaMax = { "VidaMax", "MaxHealth", "SaudeMax", "DurabilidadeMax", "VehicleMaxHealth" },
}

-- ===== Câmeras (ângulo em graus ao redor do carro, altura e distância em relação ao tamanho do carro) =====
Config.Cameras = {
	frente = { angulo = 35, altura = 0.55, dist = 1.55 },
	lado = { angulo = 90, altura = 0.45, dist = 1.5 },
	tras = { angulo = 205, altura = 0.6, dist = 1.45 },
	roda = { angulo = 70, altura = 0.18, dist = 1.15 },
	baixo = { angulo = 120, altura = 0.12, dist = 1.4 },
}

-- ===== Sons (cole IDs autorizados "rbxassetid://123"; vazio = sem som; nunca bloqueia nada) =====
Config.Sons = {
	Abrir = "", Navegar = "", Previa = "", Compra = "", Erro = "", Fechar = "",
	Portao = "", Pintura = "", Ferramenta = "",
}

function Config.Categoria(id)
	for _, c in ipairs(Config.Categorias) do
		if c.id == id then return c end
	end
	return nil
end

function Config.Opcao(cat, id)
	for _, o in ipairs(cat.opcoes or {}) do
		if o.id == id then return o end
	end
	return nil
end

-- cor da paleta? (tolerância pequena por causa do arredondamento na rede)
function Config.NaPaleta(cor)
	for _, p in ipairs(Config.Paleta) do
		local c = p.cor
		if math.abs(c.R - cor.R) < 0.012 and math.abs(c.G - cor.G) < 0.012 and math.abs(c.B - cor.B) < 0.012 then return true end
	end
	return false
end

return Config
