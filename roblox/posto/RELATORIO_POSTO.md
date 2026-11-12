# Gas Station & Convenience — Auditoria, evolução e padronização

| Arquivo | Conteúdo |
|---|---|
| `GasStationArea_Posto.ORIGINAL.rbxmx` | cópia intacta recebida (sha256 `cc3aef68…bc21147`), para reversão |
| `GasStationArea_Posto.rbxmx` | versão corrigida (sha256 `fbb32e2f…2ff3df2`) |
| `correcoes.diff` | diff exato dos 23 scripts alterados |
| `testes/PostoAutoTest.server.lua` | roteiro de teste automático para o Studio |

**Integridade:** fora do código-fonte (CDATA), o XML é idêntico byte a byte ao original. Cenário, instâncias, nomes, referents, propriedades e `Disabled` não mudaram, e **nenhuma instância foi criada ou removida**. Mudaram 23 dos 49 scripts. Bus, State, Alarm, Npc, Props, Sign e Radio não foram tocados, nem os scripts legados (exceto 2 linhas do teclado do caixa).

Referência: DepartamentoPolicia. Segui o mesmo padrão de `pcall` no `CanStart`, de `error()` controlado no `Start` quando falta recurso, de validação de objetos e de aviso de módulo ausente. Nada foi copiado do DP sem necessidade.

---

## 1. Arquitetura encontrada (preservada)
- O `Core` cria `PostoRuntime`, `PostoRemotes` (5 RemoteEvents, todos servidor→cliente) e `PostoState` (atributos replicados), carrega 14 sistemas em ordem e depois `Missions`, e instala a `PostoHUD`.
- O `Bus` interno usa `task.spawn`. `Missions` traz motor, diretor, quadro e `ForceMission`, e encerra tudo por uma rotina única (`finish` → desconecta, `Cleanup`, `OnFail`, recompensa e XP, limpa a HUD).
- Os sistemas são Power, Pumps, Fire, Tools, Shop, Customers, Npc, Props, Reputation (DataStore), Alarm, Radio, Sign, Jukebox e Ambience.
- **Segurança:** não existe `OnServerEvent`. Toda ação do jogador passa por ProximityPrompt ou Tool no servidor, e o cliente não envia dados ao servidor. Nenhuma superfície de ataque nova foi criada.

## 2. Problemas confirmados e correções

### Críticos
| # | Problema | Evidência | Correção |
|---|---|---|---|
| 1 | **O apagão nunca acontecia; a missão `blackout` ficava sempre presa** | `Ambience.Lightning` chama `Power.Flicker`, cujo primeiro passo (síncrono) deixa `mode = "off"`. Logo em seguida `Power.Blackout` faz `if mode == "off" then return end` e o apagão é ignorado. O gerador nunca fica disponível e a missão expira. O relatório de dissecação não detectou isso. | `Blackout` agora verifica o estado real (`breakerTripped`). `Flicker` não roda durante um apagão (antes, um relâmpago posterior também podia cancelar a sequência do apagão pelo token). |
| 2 | **Assalto: falha ao criar o NPC virava vitória** | `if not robber then m:Complete()` | O NPC é criado **antes** de fechar a loja; uma falha gera `error()` controlado e a missão é encerrada e limpa, sem prêmio. |
| 3 | **Estoque: concluía sozinho sem caixas ou prateleiras** | `if n == 0 or #drops == 0 then m:Complete()` | `CanStart` valida as caixas, as prateleiras e os slots da loja; no `Start`, `error()` controlado. Só esvazia as prateleiras depois de validar. |
| 4 | **Economia paralela** | `Core` chamava `Util.Stat` para cada jogador, que **criava** `leaderstats.Dinheiro`; `Pay` e `Charge` mexiam nesse valor. | Economia isolada e **desligada** (seção 3). O posto não cria mais `leaderstats`. |

### Missões
| Missão | Situação | Correção |
|---|---|---|
| **blackout** | Defeito crítico nº 1. A sequência gerador → disjuntor → terminal está correta no `Power` (prompts liberados na ordem certa e `ForceOnline` na limpeza). | Correção do nº 1. `CanStart` exige Generator, BreakerPanel e PumpTerminal e energia sem desarme. |
| **fuel_leak** | Podia escolher uma bomba sem válvula associada: a explosão seria inevitável. O resto (válvula → poça → fogo, explosão = falha, limpeza fecha, limpa e apaga) está correto. Os focos que se espalham mantêm a tag, então são contados e limpos. | Sorteia só bombas saudáveis, **com válvula** e sem defeito. `error()` se `StartLeak` falhar. |
| **inspection** | Abstrata: o defeito era só texto, sem efeito em sistema nenhum. `SetTarget(points[1])` ficava fixo. | **Diagnóstico e reparo reais** (seção 2.1). O alvo acompanha o próximo ponto pendente. |
| **robbery** | O alarme não era obrigatório. Se o ladrão fosse detido antes de chegar ao caixa, ele **ainda roubava** depois de 12 s, e devolver a sacola criava dinheiro (a sacola valia o saque sorteado, não o valor tirado). Se quem levava a sacola morresse, a missão travava. A morte do ladrão era tratada como fuga. | Alarme silencioso virou **objetivo obrigatório** (meta 4). O ladrão só rouba se não estiver detido, e a sacola devolve **exatamente** o que foi tirado do caixa. A sacola perdida volta ao chão. A morte do NPC gera falha controlada. Ponto de integração com a polícia: `Bus "PoliceAlert"`, sem criar uma polícia própria. A reação do NPC ao alarme (fuga acelerada) foi mantida. |
| **rush** | Uma falha de pathfinding contava como **cliente irritado**. Ao fim da missão, os clientes continuavam esperando e disparando callbacks. Havia um laço morto (`open`). | `onLeft(reason)`: `"nav"` não conta e libera outra vaga. `Customers.Dismiss` dispensa os clientes da missão na limpeza. Callbacks são ignorados depois do fim. Laço morto removido. |
| **stock** | Defeito crítico nº 3. A caixa carregada **ficava com o jogador** (e a lentidão) depois da missão. Uma caixa perdida (morte ou saída) travava a missão, porque nascem exatamente N caixas. | Limpeza remove todas as caixas carregadas. A caixa perdida volta à calçada. |
| **stranded** | Fluxo correto (comprar, encher, consumir 10 L, entregar). Porém o carro era destruído 1 s depois da entrega, no meio da animação de saída, e um galão `nil` no evento podia gerar erro. | O carro só é removido depois de sair de cena. Checagem de `can`. `error()` se o carro não for criado. |
| **tanker** | O temporizador de um surto antigo podia penalizar um surto novo se `SurgeEvery < SurgeWindow`. O alarme podia ficar ligado ao fim da transferência. Finalizar e depois esperar 7 s podia fazer a missão **falhar por tempo depois de concluída**, e o caminhão sumia no meio da saída. | Token de surto (`surgeId`). A transferência termina limpando surto e alarme. Conclui ao finalizar e remove o caminhão só depois da saída. O regulador é ignorado depois do fim. `error()` se o caminhão não for criado. |

### 2.1 Inspeção com diagnóstico e reparo reais
Cada equipamento tem um defeito associado e um efeito **no sistema que já existia**, aplicado pelo atributo `Defeito`. Nenhuma mecânica nova e solta foi inventada:

| Equipamento | Defeito | Efeito real até o reparo |
|---|---|---|
| BreakerPanel | fiação aquecida no disjuntor | disjuntor não rearma (`Power`) |
| Generator | óleo do gerador baixo | gerador não parte (`Power`) |
| FireLocker_1 | lacre do extintor vencido | armário não entrega nem recarrega extintor (`Tools`) |
| PumpAnchor_1/3 | mangueira ressecada | bomba "MANUTENÇÃO": não enche nem vende galão (`Pumps`) |
| ShutoffValve_2 | vedação com desgaste | válvula emperrada (`Pumps`) |
| Jukebox | fiação do rádio solta | rádio da loja não troca de estação (`Jukebox`) |
| TankerPort | engate com desgaste | sinalizado (só é usado na missão do caminhão, que não roda ao mesmo tempo) |

Fluxo: a missão aplica os defeitos (40% dos pontos, como no original) → o jogador **vistoria** (G) e recebe o diagnóstico (defeito e sistema afetado) → **corrige** (R) e o equipamento volta a funcionar. A limpeza remove qualquer defeito restante, mesmo em falha ou cancelamento.

### Sistemas e robustez
| Sistema | Problema | Correção |
|---|---|---|
| Reputation | Se o `GetAsync` falhasse, o jogador era marcado como carregado e o próximo `SetAsync` **apagava o XP salvo** (0 + sessão). | Com falha de leitura, não salva nesta sessão (evita perda de dados). Persistência única preservada. |
| Tools (binóculos) | Guardar os binóculos **zerava o zoom de todos os jogadores**. | Desliga só o zoom de quem estava usando. |
| Missions | `CanStart` rodava sem `pcall`: um erro derrubava o diretor e o quadro. | `eligible()` com `pcall`. |
| Core | Sem validação de objetos; um HUD ausente gerava erro por jogador. | Aviso único com os objetos ausentes, guarda para o HUD e aviso de módulo ausente. |
| Util.PlaySound | Erro com ID numérico ou parent `nil`. | Blindado com `pcall`; aceita número. |
| Jukebox | Criava `Sound` sem proteção. | Usa `Util.PlaySound`. |
| KeypadScript (legado) | `table.remove(input, 0)` dava erro no Output ao digitar "0" primeiro; `tonumber(".")` dava erro aritmético. | Índice 1 e `or 0`. São as únicas 2 linhas alteradas em scripts legados. |
| HUD | Painéis com tamanho fixo em pixels. Em celular, o rádio (canto inferior esquerdo) ficava **por cima** da reputação. | `UIScale` por painel, com posições proporcionais e um limite de escala calculado para não haver sobreposição (até cerca de 320 px de altura). O visual original é mantido em telas grandes. |

## 3. Economia: desativada, interface isolada
- `Config.Economy.Enabled = false`: **nenhum saldo é criado, lido ou alterado**, e não existe `leaderstats` do posto.
- Todos os pagamentos passam por `Util.Pay(player, valor, motivo)` e `Util.Reward(...)`, que aplica o bônus de reputação e só mostra popup se algo foi pago. Ambos disparam `Bus "RewardEarned"` e devolvem 0 enquanto desligado.
- Cobranças passam por `Util.Charge(player, valor, motivo)`, que devolve `(ok, cobrado)`. Com a economia desligada vale `PurchasesWhenDisabled`: `"free"` (padrão) entrega o item sem cobrar, para que galão, combustível e loja continuem jogáveis; `"blocked"` recusa a compra.
- Integração futura sem reescrever nada: `Util.SetEconomyProvider({ Pay, Charge, Balance })`, ou `Provider = "leaderstats"`, que usa `leaderstats[Stat]` só se já existir.
- Divisão do prêmio entre colaboradores: `MissionPayout = "full"` (regra original, cada um recebe o integral), `"split"` ou `"none"`. O XP de reputação continua indo para todos os colaboradores.
- **Caixa do posto** (`Cash`): é dinheiro do cenário (vendas e assalto), não saldo de jogador. Foi mantido e continua recebendo as vendas mesmo com compras gratuitas.
- Os valores de `Config.Rewards` e as recompensas das missões estão preservados.
- **Reputação e XP:** implementação mantida (DataStore `PostoReputacao_v1`, desconto, bônus), sem persistência duplicada.

## 4. Áudio: estrutura pronta, nenhum ID inventado
`Config.Sounds`, todos os campos vazios:

| Grupo | Campos |
|---|---|
| Bombas e abastecimento | `Fuel`, `PumpBeep`, `Valve` |
| Alarmes | `Alarm`, `Siren` (reservado para a polícia) |
| Incêndios | `FireLoop`, `Extinguisher`, `Explosion` |
| Energia | `Generator`, `GeneratorLoop`, `Breaker`, `Spark`, `Blackout`, `Thunder` |
| Caixa e loja | `Register`, `Purchase`, `Chime`, `Drink`, `Gift` |
| Clientes e NPCs | `CustomerServed`, `CustomerAngry` |
| Assalto | `RobberyStart`, `Tackle`, `Cuff` |
| Veículos | `Truck` (caminhão-tanque), `CarStart` (carro do motorista) |
| Rádio e alertas | `Radio`, `Alert` |
| Missões | `MissionStart`, `Complete`, `Fail` |
| Música da loja | `Config.Jukebox.Stations` (já existia) |

Todos os campos novos já estão ligados aos pontos de uso, exceto `Siren` e `Alert`, que ficam reservados. Um ID ausente ou inválido nunca bloqueia uma mecânica.

## 5. Scripts legados: examinados e preservados
| Script | Função | Situação |
|---|---|---|
| `StoreFridgeDoorScript` ×6, freezer ×2, `CashDrawerScript` | portas e gaveta por ClickDetector | cosméticos, sem conflito com os prompts da Shop. Mantidos. |
| `KeypadScript` (KeyPadTEST) | teclado do caixa | mantido, com 2 correções de erro. |
| `Doorway/Door/Script` | porta física (BodyGyro) | mantido. |
| `GasPump/Script` ×4 (+ `PlayerDamageScript`) | explosão antiga das bombas | já `Disabled = true` no arquivo, e o `Core` também os desativa. O sistema `Pumps` os substitui. Mantidos. |
| Scripts `Give*` e `IceCreamScript` | entregavam itens via InsertService | **não existem neste arquivo**; o laço do `Core` não remove nada (contador 0). |

## 6. NPCs e multiplayer
- **NPCs:** `Npc` é idêntico ao do DP (pcall e rig de blocos de reserva). Clientes que não chegam à fila são removidos. Clientes de missão são dispensados na limpeza. A morte do assaltante é tratada. O cliente servido por um jogador que sai é tratado (`Pay` e `Popup` verificam `Parent`).
- **Multiplayer:** os colaboradores contam por ação. Os prompts concorrentes são protegidos por flags (alarme, algemar, sacola, autorizar, mangote, válvula, regulador, entrega). O pedido em mãos é por jogador. O zoom agora é por jogador.

## 7. Testes

### Estáticos (executados aqui), aprovados
- O XML é lido sem erro; a estrutura é idêntica e só os CDATA diferem (23/49). Os 23 fontes reinjetados conferem byte a byte, e cada segmento foi comparado com o original antes da troca.
- Verificador léxico (blocos, parênteses e strings) aprovado em todos os scripts, originais e novos. Busca por globais indefinidas: nenhuma nova.
- O traçado de execução do `Lightning` + `Blackout` confirmou o defeito crítico nº 1 e a correção.

### Execução: **não realizada**
**Não havia Roblox Studio nem interpretador Luau neste ambiente; nenhum teste de execução foi declarado aprovado.** Também não há testes simulados.
Rode `testes/PostoAutoTest.server.lua`. Ele cobre:
- inicialização;
- economia desligada e provedor simulado;
- áudio ausente;
- **regressão do apagão** (relâmpago + blackout);
- blackout com limpeza;
- `fuel_leak` concluído por válvula + limpeza;
- inspeção com defeitos reais (incluindo bomba fora de serviço) e limpeza;
- assalto (meta 4, loja fechada e reaberta, **falha de NPC não vira vitória**);
- estoque (não inicia sem prateleiras, Tool recolhida);
- stranded (galão pronto conta, carro removido);
- smoke test das 8 missões com checagem de alarme, energia, defeitos, Tools, veículos e marcadores;
- resumo do Output.

### Procedimento manual (prompts, multiplayer e mobile)
1. **blackout**: gerador (G/E), disjuntor e terminal, na ordem; tente o disjuntor antes do gerador (deve soltar faíscas e recusar).
2. **fuel_leak**: deixe pegar fogo (55 s), use o extintor e feche a válvula; deixe explodir numa segunda rodada (falha esperada).
3. **inspection**: vistorie (G), confirme o efeito (bomba em "MANUTENÇÃO", armário recusando) e corrija (R).
4. **robbery**: (a) alarme e depois captura; (b) captura sem alarme (a missão só conclui depois do alarme); (c) deixe fugir; (d) morra carregando a sacola (ela deve voltar ao chão); (e) caixa com saldo 0.
5. **rush**: 6 atendimentos; deixe 3 irritarem; dois jogadores atendendo ao mesmo tempo.
6. **stock**: morra carregando uma caixa (ela volta à calçada).
7. **stranded**: compra, enchimento e entrega por jogadores diferentes.
8. **tanker**: perca surtos de propósito (fogo, pausa e falha ao 3º); finalize perto do limite de tempo.
9. **Desconexão**: um jogador sai no meio de cada missão (Test > Clients and Servers, 2 jogadores).
10. **Mobile**: Device Emulator (iPhone SE, iPhone 14, iPad). Confira a HUD sem sobreposição, os prompts tocáveis (E/F/G/R aparecem como botões), o pedido em mãos e os avisos.
11. **Desempenho**: MicroProfiler com 4 ou mais jogadores e clientes ativos.

## 8. Pendências e riscos
- **Economia:** com `Enabled = false` ninguém ganha dinheiro, e as compras são gratuitas por padrão. Isso é intencional até a integração; a decisão de `PurchasesWhenDisabled` e `MissionPayout` é de design.
- **Polícia:** apenas o evento `PoliceAlert`. A ligação com o DepartamentoPolicia depende de os dois modelos estarem no mesmo place e de um script escutar o Bus do Posto.
- **Hierarquia:** o `Core` exige `GasStationArea/{Convenience Store, Gas Station, PostoObjects, Posto}` com esses nomes (comportamento original).
- **Desempenho:** não alterei o cenário de cerca de 2.000 peças. Os laços contínuos (câmeras a 20 Hz, fogo, alarme, preço) são leves, mas devem ser medidos no MicroProfiler.
- **Ajustes adiados (fora do escopo):**
  - **Velocidade:** a lentidão da caixa e da sacola é revertida somando de volta o valor e pode conflitar com outros sistemas de velocidade.
  - **TankerPort:** o defeito de inspeção nesse ponto só é sinalizado.
  - **Caixa do posto:** recebe as vendas mesmo quando a compra é gratuita.
