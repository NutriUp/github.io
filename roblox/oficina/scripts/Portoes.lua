-- OFICINA • Portões de enrolar automáticos. No modelo original os portões são malhas sólidas e fechadas
-- (nenhum carro entrava). Aqui eles "enrolam" para cima quando alguém se aproxima e fecham depois.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Portoes = {}
local ctx
local lista = {}

local function mover(p, abrir)
	if p.aberto == abrir then return end
	p.aberto = abrir
	local cfg = ctx.Config.Portoes
	local info = TweenInfo.new(cfg.Tempo, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	ctx.Util.Som(p.part, ctx.Config.Sons.Portao, 0.6)
	if abrir then
		p.part.CanCollide = false
		local alvo = Vector3.new(p.size.X, 1.6, p.size.Z)
		TweenService:Create(p.part, info, { Size = alvo, CFrame = p.cf * CFrame.new(0, (p.size.Y - 1.6) / 2, 0) }):Play()
	else
		local tw = TweenService:Create(p.part, info, { Size = p.size, CFrame = p.cf })
		tw:Play()
		tw.Completed:Once(function()
			if not p.aberto then p.part.CanCollide = true end
		end)
	end
end

function Portoes.Init(c)
	ctx = c
	for _, d in ipairs(ctx.Modelo:GetDescendants()) do
		if d:IsA("MeshPart") and d.Name == "Racing_Garage_Rollup_a" then
			table.insert(lista, { part = d, cf = d.CFrame, size = d.Size, aberto = false, vazio = 0 })
		end
	end
	if #lista == 0 then
		warn("[Oficina] portões (Racing_Garage_Rollup_a) não encontrados; a entrada fica como está no modelo")
		return
	end
	task.spawn(function()
		local cfg = ctx.Config.Portoes
		while true do
			task.wait(0.4)
			for _, p in ipairs(lista) do
				local perto = false
				for _, pl in ipairs(Players:GetPlayers()) do
					local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
					if r and (r.Position - p.cf.Position).Magnitude <= cfg.RaioAbrir then perto = true break end
				end
				if perto then
					p.vazio = 0
					mover(p, true)
				else
					p.vazio += 0.4
					if p.vazio >= cfg.FecharApos then mover(p, false) end
				end
			end
		end
	end)
end

function Portoes.Quantidade() return #lista end

return Portoes
