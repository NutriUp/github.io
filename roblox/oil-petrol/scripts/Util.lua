local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Util = {}
local ctx
local rewardProvider

function Util.Init(c) ctx = c end

-- Nunca lança erro: ID vazio, inválido ou numérico é tratado aqui.
function Util.PlaySound(parent, id, opts)
	if type(id) == "number" then id = "rbxassetid://" .. id end
	if type(id) ~= "string" or id == "" or not parent then return nil end
	opts = opts or {}
	local ok, s = pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = opts.Volume or 0.6
		s.Looped = opts.Looped or false
		s.RollOffMaxDistance = opts.Range or 140
		s.PlaybackSpeed = opts.Pitch or 1
		s.Parent = parent
		s:Play()
		if not s.Looped then Debris:AddItem(s, 20) end
		return s
	end)
	if ok then return s end
	warn("[OilRig] som não pôde tocar (" .. tostring(id) .. "): " .. tostring(s))
	return nil
end

-- ===== recompensas: interface de integração com a economia principal =====
-- Registra a função da economia global: fn(player, valor, motivo) -> valor efetivamente pago
function Util.SetRewardProvider(fn) rewardProvider = fn end

-- Devolve o valor efetivamente pago (0 enquanto a economia não estiver integrada/autorizada).
function Util.Pay(player, amount, reason)
	if not player or not player.Parent or type(amount) ~= "number" or amount <= 0 then return 0 end
	amount = math.floor(amount)
	local eco = ctx and ctx.Config.Economy
	if ctx then ctx.Bus.Fire("RewardEarned", player, amount, reason) end
	if not eco or not eco.Enabled then return 0 end
	if eco.Provider == "custom" then
		if not rewardProvider then return 0 end
		local ok, paid = pcall(rewardProvider, player, amount, reason)
		if not ok then warn("[OilRig] erro no provedor de recompensa: " .. tostring(paid)) return 0 end
		return tonumber(paid) or 0
	elseif eco.Provider == "leaderstats" then
		local ls = player:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild(eco.Currency or "Dinheiro")
		if cash and (cash:IsA("IntValue") or cash:IsA("NumberValue")) then
			cash.Value += amount
			return amount
		end
	end
	return 0
end

function Util.Tween(inst, time, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function Util.Root(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

function Util.Humanoid(player)
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

function Util.PlayersNear(pos, radius)
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local r = Util.Root(p)
		if r and (r.Position - pos).Magnitude <= radius then table.insert(out, p) end
	end
	return out
end

-- Prepara a cópia de uma Tool-modelo para ir à mão do jogador. Os modelos em OilRig/Tools ficam ANCORADOS
-- (senão cairiam do mapa); uma cópia ancorada prende o personagem na posição da peça (0,0,0) ao equipar.
function Util.PrepareTool(tool)
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	return tool
end

-- conta filhos de RigObjects cujo nome casa com o padrão (usado pelos CanStart das missões)
function Util.CountObjects(pattern, pred)
	local n = 0
	if not ctx then return 0 end
	for _, o in ipairs(ctx.Objects:GetChildren()) do
		if o.Name:match(pattern) and (not pred or pred(o)) then n += 1 end
	end
	return n
end

function Util.Prompt(parent, action, object, hold, key)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object or ""
	pp.HoldDuration = hold or 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	if key then pp.KeyboardKeyCode = key end
	pp.Parent = parent
	return pp
end

-- Cria um painel (SurfaceGui + 2 textos) numa face de uma peça
function Util.Screen(part, face, title)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Screen"
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Brightness = 1.4
	sg.AlwaysOnTop = false
	sg.Parent = part
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 14, 18)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 0.24)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 150, 30)
	t.Text = title or ""
	t.Parent = bg
	local v = Instance.new("TextLabel")
	v.Name = "Value"
	v.BackgroundTransparency = 1
	v.Position = UDim2.fromScale(0, 0.24)
	v.Size = UDim2.fromScale(1, 0.76)
	v.Font = Enum.Font.GothamBlack
	v.TextScaled = true
	v.TextColor3 = Color3.fromRGB(90, 255, 140)
	v.Text = "--"
	v.Parent = bg
	return v
end

return Util
