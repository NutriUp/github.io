# Oil Petrol — Padronização técnica e auditoria do sistema de missões

| Arquivo | Conteúdo |
|---|---|
| `Oil_petrol_Missoes.ORIGINAL.rbxmx` | cópia intacta recebida (sha256 `056b777d…af836d`), para reversão |
| `Oil_petrol_Missoes.rbxmx` | versão corrigida (sha256 `c353af5b…16ab7`) |
| `correcoes.diff` | diff exato dos 16 scripts alterados |
| `testes/OilRigAutoTest.server.lua` | roteiro de teste automático para o Studio |

**Integridade:** fora do código-fonte dos scripts, o XML corrigido é idêntico byte a byte ao original. Isso inclui instâncias, referents, propriedades e `Disabled`. **Nenhuma instância foi criada ou removida.** Mudaram 16 dos 27 scripts. HUD, Bus, State, Alarm, Pressure, Power, Inspection e os 3 scripts legados não foram tocados.

Referência de padrão: DepartamentoPolicia. Segui o mesmo uso de `pcall` em `CanStart`/`Init`, a mesma checagem de objetos no `CanStart` (como `#ObjList >= N`), o mesmo `error()` no `Start` quando falta recurso, o mesmo `Util.Init(ctx)` e o mesmo aviso de módulo ausente.

> O relatório técnico com os nove problemas não veio junto. Cada item foi conferido diretamente no código.

---

## 1. Auditoria (9 itens)

| # | Item | Situação | Evidência no código original |
|---|---|---|---|
| 1 | Guindaste: coordenadas e referência espacial | **CONFIRMADO (2 defeitos)** | (a) `Config.Crane.Pivot` é uma coordenada **absoluta de mundo** (`-1102.4, 58.5, 1247.5`). Se o modelo for inserido ou movido para outro lugar (é um `.rbxmx`), o guindaste passa a orbitar um ponto distante e "voa" pelo mapa. (b) O `Core` calcula `ctx.Center` e `RigRadius` com `model:GetBoundingBox()`, que inclui os `Handle` das Tools-modelo em `OilRig/Tools`, todos em **(0,0,0)**. O centro caía cerca de 800 studs fora da plataforma e o raio ia para cerca de 870 studs. Isso distorcia a visibilidade do HUD, o diretor, a deriva de pressão e a direção de chegada do helicóptero. |
| 2 | Conclusão automática sem objetivos | **CONFIRMADO** | `fires` e `barrels` faziam `if n == 0 then m:Complete()`: anunciavam "MISSÃO CUMPRIDA" sem objetivo nenhum. Outras missões ficavam presas até o tempo acabar quando faltavam recursos: `crane` sem guindaste, `inspection` com menos de 4 checkpoints, `airdrop` sem heliponto. O `blackout` sem gerador ou disjuntor dava erro no meio e deixava o estado `Power=false`. |
| 3 | Falha na chamada do helicóptero | **CONFIRMADO** | O `airdrop` ignorava o `false` devolvido por `Helicopter.Call()` e a missão ficava sem objetivo até o tempo acabar. Um erro durante o voo deixava `running = true` para sempre, o que travava o `airdrop` e o console até reiniciar o servidor, e deixava o modelo e a conexão `Heartbeat` vivos. Se a missão terminasse durante a aproximação, as caixas nasciam **depois** do `Cleanup` e ficavam órfãs. |
| 4 | Limpeza de Tools, barris e caixas | **CONFIRMADO** | `Cargo.Clear` removia só as peças no chão. As Tools "Barril" e "Caixa de Suprimentos" na mochila, na mão ou largadas no chão continuavam existindo. Depois da missão ainda podiam ser entregues (pagando de novo) e contavam para a missão seguinte do mesmo tipo. |
| 5 | Recompensa entre colaboradores | **CONFIRMADO** | Cada colaborador recebia o prêmio **integral**; não existia política configurável. A variável `n` era contada e nunca usada. |
| 6 | IDs de áudio | **PARCIAL** | Já havia `Config.Sounds`, mas faltavam campos para sirene, música, carga, guindaste e fogo. `Util.PlaySound` sem proteção dava erro com ID numérico ou parent `nil`. O campo `Radio` existia e não era usado. |
| 7 | `leaderstats.Dinheiro` | **CONFIRMADO** | `Util.Pay` **criava** `leaderstats` e `Dinheiro`: uma economia paralela, contrária à diretriz do jogo. |
| 8 | Scripts antigos | **SEM CONFLITO, preservados** | São 3 scripts legados: `Top Platform/Door/Main` e duas cópias de `Functions/Light/Function`. Os 3 estão `Disabled = true`, então não rodam e não disputam eventos. O `Light/Function` mexe na peça `Light`; o sistema novo controla `Lightbulb` e `RigLamp`, sem sobreposição. A porta legada (ClickDetector) não tem equivalente no sistema novo. Mantidos intactos e desativados. |
| 9 | Validação em runtime | **CONFIRMADO** | `Missions.Init` rodava sem `pcall`: um erro derrubava o `Core` antes de instalar o HUD. `CanStart` também rodava sem `pcall` dentro do diretor, e um erro matava o laço para sempre. Objetos ausentes falhavam em silêncio. `template:Clone()` dava erro se o HUD faltasse. |

**Segurança server-side:** os 3 RemoteEvents são somente servidor→cliente (não há `OnServerEvent`). Todas as ações passam por ProximityPrompt e Tool no servidor, e o extintor valida alcance e direção no servidor. Nenhuma superfície de ataque nova foi criada.

## 2. Correções (mínimas e localizadas)

| Script | Alteração |
|---|---|
| `Core` | O centro e o raio agora vêm da caixa envolvente **sem** a pasta `OilRig`. Chama `Util.Init(ctx)`. Valida em runtime os objetos e Tools necessários, com um único aviso listando o que falta. `Missions.Init` fica dentro de `pcall`. Guarda para HUD ausente e aviso de módulo ausente. |
| `Config` | `Crane.PivotLocal`: o eixo passa a ser **relativo ao pivot do modelo Crane**, recalculado para dar exatamente o mesmo ponto na posição atual. `Crane.Pivot` fica como fallback legado. Novos blocos `Economy` e `Sounds` (ver seções 3 e 4). Nenhum valor de jogo foi alterado. |
| `Util` | `PlaySound` blindado: aceita número, ignora vazio, aceita parent `nil` e usa `pcall`. `Pay` virou a **interface de integração** (seção 3) e não cria mais `leaderstats`. Novo `CountObjects(padrão)` para os `CanStart`. |
| `Missions` | `CanStart` dentro de `pcall`. Política de divisão do prêmio configurável. O aviso "+X" só aparece quando algo foi pago de fato. Som de início e música da missão, destruída em qualquer encerramento. |
| `Systems/Crane` | Usa o eixo relativo. `Crane.Ready()`. `SetAngle` e `Flourish` não dão erro sem guindaste (antes, entregar carga sem guindaste gerava erro e deixava `busy` preso). Som opcional do motor. |
| `Systems/Helicopter` | O voo roda dentro de `pcall`, com **limpeza garantida**: desconecta o Heartbeat, destrói o modelo e zera `running`/`Landed`. Não cria caixas se a missão já foi encerrada (`Dismiss`). |
| `Systems/Cargo` | Rastreia as Tools de carga entregues. `Clear(kind)` também as destrói (mochila, personagem ou chão), e o evento `Destroying` restaura a velocidade. Não entrega a Tool se o jogador não tiver Backpack. Sons de coleta e entrega. Mostra o valor efetivamente pago. |
| `Systems/Fire` | Loop sonoro opcional em cada foco, removido junto com o fogo. Motivo informado no `Pay`. |
| `Systems/Radio` | Bipe opcional (`Sounds.Radio`, campo que já existia e não era usado) nas mensagens gerais. |
| `MissionDefs/fires`, `barrels` | `CanStart` verifica pontos livres. Sem objetivo, a missão faz `error()` no `Start` em vez de se concluir sozinha (o motor encerra e limpa). |
| `MissionDefs/airdrop` | `CanStart` exige heliponto, doca e pontos de caixa. A meta passa a ser `min(CrateCount, pontos)`. Se `Call()` falhar, `error()` em vez de missão presa. |
| `MissionDefs/inspection`, `crane`, `blackout`, `pressure` | `CanStart` verifica checkpoints 1 a 4, `Crane.Ready()`, gerador e disjuntor, e válvulas com roda. Não iniciam missões impossíveis de concluir. |

**Mecânicas preservadas:** pressão e deriva, válvulas, sobrepressão, apagão (disjuntor e depois gerador), fogo e dano, extintor, barris, caixas, doca, helicóptero (rota, tempos, permanência), guindaste (passo, limite, tween), inspeção, diretor, quadro de missões, `ForceMission`, HUD, bônus de tempo de 25%, valores de `Rewards` e multiplayer (colaboradores por ação).

## 3. Economia: preparada, desligada

- `Config.Economy.Enabled = false`. **Nenhum pagamento é feito e nenhum saldo é criado ou alterado.**
- Toda recompensa (missão, válvula, fogo, inspeção, carga) passa por um único ponto, `Util.Pay(player, valor, motivo)`, que:
  - sempre dispara `Bus "RewardEarned"(player, valor, motivo)`, para auditoria ou para a integração futura;
  - devolve o valor efetivamente pago (0 enquanto estiver desativado).
- Integração futura sem reescrever nada:
  - `Provider = "custom"` com `Util.SetRewardProvider(function(player, valor, motivo) return valorPago end)`, chamando a API da economia global;
  - ou `Provider = "leaderstats"`, que soma em `leaderstats[Currency]` **somente se esse valor já existir**; nunca cria.
- Política de divisão: `Config.Economy.MissionPayout = "full" | "split" | "none"`. O padrão `"full"` mantém a regra original e fica como decisão de design pendente, sem regra econômica imposta.
- **Dependência:** é preciso uma API autorizada da economia principal e a decisão sobre a política de divisão.

## 4. Áudio: estrutura pronta, nenhum ID inventado

`Config.Sounds` traz todos os campos vazios (`""` significa sem som):

| Grupo | Campos |
|---|---|
| Alarmes e sirenes | `Alarm` |
| Efeitos | `Explosion`, `Valve`, `Generator`, `Blackout`, `Extinguisher`, `FireLoop`, `CargoPickup`, `CargoDeliver`, `CraneMotor`, `Radio` |
| Veículos | `Heli` |
| Missão | `MissionStart`, `Complete`, `Fail` |
| Música | `Music.Default` e uma entrada por missão: `pressure`, `blackout`, `fires`, `barrels`, `airdrop`, `inspection`, `crane` |

Aceita `"rbxassetid://123"` ou só o número. Um ID ausente, inválido ou que falhe ao carregar nunca interrompe a missão: `PlaySound` devolve `nil` e emite no máximo um `warn`.

## 5. Testes

### Executados aqui (estáticos), todos aprovados
- O XML corrigido é lido sem erro; a estrutura (classes, caminhos, referents, `Disabled`) é idêntica e só os `Source` diferem (16/27).
- Os 16 fontes reinjetados conferem byte a byte com os editados, e cada segmento substituído foi comparado com o original antes da troca.
- Verificador léxico próprio em todos os scripts, originais e novos: blocos `function`/`if`/`do` contra `end`, parênteses e strings balanceados. O verificador foi validado com um caso negativo.
- Busca por identificadores globais não definidos nos 16 scripts: nenhum. Encontrei e corrigi um placeholder durante a revisão.
- Conta do `PivotLocal`: `origin:PointToWorldSpace(PivotLocal)` dá `(-1102.4, 58.5, 1247.5)`, exatamente o eixo original.

### Não executados: limitação
**Não havia Roblox Studio nem interpretador Luau neste ambiente.** Nenhum teste de execução foi declarado aprovado.
Rode `testes/OilRigAutoTest.server.lua`. Ele verifica:
- referência espacial;
- base do guindaste fixa ao girar;
- economia desligada e provedor simulado;
- `PlaySound` com ID vazio, numérico ou sem parent;
- `crane`, `fires` e `pressure` concluídas sem nenhum SoundId;
- missões que não iniciam quando faltam objetivos;
- limpeza de barris;
- cancelamento do helicóptero em voo (sem caixas órfãs e sistema liberado);
- smoke test das 7 missões;
- energia restaurada após o blackout.

Avisos **esperados** no Output durante o teste: `HelipadPad ausente` (simulação do passo 6) e as falhas forçadas `teste-automatico`.

### Procedimento manual
1. **Inicialização**: o Output deve mostrar `[OilRig] sistemas ativos…` e nenhum `objetos ausentes`.
2. **Mover a plataforma**: arraste o modelo `Oil petrol` 500 studs no Studio, dê Play e gire o guindaste (E/F no console). Ele deve girar em torno da própria base. O HUD deve aparecer só perto da plataforma.
3. **Cada missão até o fim** (use `OilRigState:SetAttribute("ForceMission","<id>")`): pressure (válvulas), blackout (disjuntor e depois gerador), fires (extintor), barrels (5 entregas), airdrop (3 caixas), inspection (4 pontos), crane (ângulo-alvo).
4. **Tools**: na `barrels`, pegue um barril e **não entregue**. Force o fim (`ForceMission` de outra missão). A Tool deve sumir da mão e da mochila e a velocidade voltar a 16. Repita largando a Tool no chão (Backspace).
5. **Helicóptero**: chame pelo console e pelo `airdrop`; cancele a missão durante a aproximação.
6. **Multiplayer** (2 jogadores): os dois contribuem; o carregamento é independente; um jogador sai no meio da missão; nenhum erro.
7. **Mobile**: no Device Emulator, os prompts tocáveis (os dois do console do guindaste, separados por `UIOffset`), o HUD e as notificações.
8. **Economia**: confirme que nenhum `leaderstats` é criado pelo OilRig.

## 6. Riscos e pendências
- **Economia**: com `Enabled = false`, os jogadores não recebem nada; os avisos não mostram mais "+X". Isso é intencional até a integração autorizada.
- **`PivotLocal`**: se alguém editar o *pivot* do modelo `Crane` no Studio, é preciso medir o valor de novo (o comentário na Config explica). Mover ou girar a plataforma inteira não exige nada.
- **Helicóptero pelo console, fora de missão**: as caixas que ele deixa só são recolhidas por um `airdrop` posterior. É o comportamento original, mantido; com a economia ligada, o console permitiria repetir entregas a cada cerca de 95 s.
- **Velocidade ao carregar**: `NormalSpeed = 16` sobrescreve a velocidade do personagem ao soltar ou destruir a Tool (original). Se o jogo tiver outro sistema de velocidade, conflita.
- **Scripts legados** continuam desativados; a porta da Top Platform não abre. Reativar só depois de testar, porque usa API antiga (`:connect`, `wait`).

## 7. Correção posterior ao playtest (Studio do dono)
| Defeito confirmado em execução | Causa | Correção |
|---|---|---|
| Ao pegar extintor, barril ou caixa de suprimentos, o personagem ia para o meio do mapa, ficava preso e nada aparecia na mão. | Os modelos em `OilRig/Tools` têm o `Handle` **ancorado** e em (0,0,0) (necessário para não caírem do mapa). A cópia entregue ao jogador continuava ancorada; ao equipar, a mão era soldada a uma peça presa na origem. Defeito do modelo original, sem relação com mudar a plataforma de lugar. | `Util.PrepareTool` solta as peças da **cópia** (`Anchored = false`, sem colisão, `Massless`) antes de entregar. Usado em `Cargo.giveTool` e `Fire.giveExtinguisher`. Os modelos continuam ancorados. Scripts avulsos em `scripts/`. |
