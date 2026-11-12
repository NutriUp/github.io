# Departamento Policial — Auditoria, correção e validação

| Arquivo | Conteúdo |
|---|---|
| `DepartamentoPolicia_Delegacia.ORIGINAL.rbxlx` | cópia intacta do arquivo recebido (sha256 `82f94daa…62ed7`). Use-a para reverter. |
| `DepartamentoPolicia_Delegacia.rbxlx` | versão corrigida (sha256 `cda1dceb…bcf36`) |
| `correcoes.diff` | diff exato dos scripts Lua alterados |
| `testes/DelegaciaAutoTest.server.lua` | roteiro de teste automático para o Studio (Play/F5) |

**Integridade:** fora dos blocos de código-fonte (CDATA), o XML corrigido é idêntico byte a byte ao original.
Somente 8 dos 167 scripts mudaram. Classes, caminhos, referents, `Disabled`, atributos e objetos continuam iguais.

> O relatório do Manus não veio junto com o arquivo. A auditoria seguiu os 5 itens listados no pedido e a leitura direta do código.

---

## 1. Auditoria: defeitos confirmados ou não

| # | Item | Situação | Evidência |
|---|---|---|---|
| 1 | **Custódia**: suspeito destruído antes de chegar à cela | **CONFIRMADO** | `Custody.Book` disparava `SuspectBooked` **antes** de `Custody.Jail`. `Bus.Fire` usa `task.spawn`, então o handler da missão roda na hora: `m:Add(1)` → `Complete` → `Cleanup` → `State ~= "jailed"` (o estado ainda era `"booked"`) → `Suspects.Remove`. Depois disso `Custody.Return` via `rec.Alive == false` e não fazia nada. Afetava **most_wanted, interrogation, hostage e perimeter_breach**. Em **prison_break e riot**, se o tempo acabasse com o preso já a caminho da cela (estado `"booked"`), ele também era destruído. |
| 2 | **Bomba**: o mesmo Humanoid levava vários danos | **CONFIRMADO** | `Explosion.Hit` dispara **uma vez por peça**. A proteção `m.Hurt` nunca recebia valor. Um rig R15 (cerca de 15 peças) levava 40 × N de dano, ou seja, morte certa. |
| 3 | **Blackout**: efeito visual some antes dos 3 geradores | **NÃO CONFIRMADO, sem alteração** | `Power.Set("on")` só acontece no `Cleanup`, que roda quando os 3 geradores são religados (ou quando a missão falha/é cancelada). Depois do 1º gerador o modo passa para `"emergency"`: 1 em cada 3 luzes acesa e o HUD escurecido a 70%. Isso é intencional: o próprio HUD comenta "escurece a tela (energia 'off' ou 'emergency')". Não há caminho de código que devolva `"on"` antes da hora, e não achei condição de corrida no loop de oscilação. |
| 4 | **Frota**: duas FEDERAL CAR e registro duplicado | **NÃO CONFIRMADO, sem alteração** | São 2 modelos diferentes: `CARROS/FEDERAL CAR` e `estações de policia/Model1/FEDERAL CAR`. Ficam em posições distintas (~170 studs), as duas têm `DriveSeat` e `A-Chassis Initialize` ativos, e nenhuma está em storage ou desativada. Nenhuma é template. A cópia da estação é até uma versão ajustada (densidade 0.0001 e 4 scripts de lightbar redundantes desativados). O Fleet registra cada modelo uma única vez, então "Viatura 1" e "Viatura 2" são dois carros reais. |
| 5a | **Robustez**: falha ao criar NPC | **OK, sem alteração** | `Npc.Create` tem `pcall` e um rig de blocos como reserva. Todas as missões checam `if not rec then error("sem NPC")`, e `Missions.Start` captura o erro e encerra com `Cleanup`. `AddPrisoner`, reféns, cúmplices e oficiais tratam `nil`. |
| 5b | **Robustez**: limpeza de temporários | **CONFIRMADO (2 pontos)** | (a) No `Cleanup` do **riot**, a condição `r.Alive and …` deixava o modelo de um amotinado **morto** para sempre em `DelegaciaRuntime`. (b) O laço de liberação da Custódia tirava da lista o preso morto ou sem `HumanoidRootPart`, mas não destruía o modelo, que ficava órfão (corpos de presos mortos pela explosão do item 2, por exemplo). |

## 2. Correções aplicadas (mínimas e localizadas)

| Arquivo (no Studio) | Alteração |
|---|---|
| `Delegacia/Modules/Systems/Custody` → `Book` | Inverti 2 linhas: `Custody.Jail(target)` agora roda **antes** de `Bus.Fire("SuspectBooked")`. O preso entra em `Custody.Prisoners()` antes de qualquer missão reagir. O evento, os argumentos e o efeito continuam os mesmos. |
| `Delegacia/Modules/Systems/Custody` → laço de liberação | +1 linha: `ctx.Systems.Suspects.Remove(rec)` quando o preso está morto ou sem root. A função é idempotente. |
| `MissionDefs/most_wanted`, `interrogation`, `hostage`, `perimeter_breach`, `prison_break` | Condição do `Cleanup`: `State ~= "jailed"` virou `State ~= "jailed" and not table.find(ctx.Systems.Custody.Prisoners(), rec)`. Só **acrescenta** proteção: tudo o que era preservado continua preservado. |
| `MissionDefs/riot` | `r.Alive and r.State ~= "jailed"` virou `r.State ~= "jailed" and not table.find(Custody.Prisoners(), r)`. Protege quem está a caminho da cela e passa a limpar os mortos. |
| `MissionDefs/bomb_threat` → `explode` | Tabela local `hurt[hum]`: cada Humanoid leva os 40 de dano uma única vez por explosão. `m.Hurt` foi mantido. |

Não foram alterados: a arquitetura, o `Core`, o `Bus`, o `Util`, o `Suspects`, o `Power`, o `Fleet`, o HUD, as interfaces, a configuração, nomes, eventos, atributos, objetos, viaturas e NPCs.

## 3. Testes

### Executados neste ambiente (estáticos e estruturais), todos aprovados
- O XML corrigido é lido sem erro, e o original e o corrigido batem fora do CDATA (8/167 fontes alteradas).
- Os 164 scripts foram extraídos e comparados com o original (ver `correcoes.diff`).
- Cada substituição foi feita contra um texto que aparece **exatamente uma vez** dentro do script-alvo, com asserção automática.
- Levantamento dos marcadores de `DelegaciaObjects` contra o `CanStart` das 13 missões: todos os requisitos existem (Hide 6, Check 5, Scene 6, Bomb 3, Generator 3, Server 3, Ambush 3, Exit 2, RangeTarget 8, Cell 4, Crisis_*, TransferPoint, BookingDesk, EvidenceLocker, LabTerminal, RangeStart, FleetTerminal, Vehicle_Spawn 3).
- Rastreio manual do fluxo corrigido: Book → Jail (`prisoners`) → `SuspectBooked` → `Cleanup` preserva → `WalkTo` → `jailed` → liberação após `HoldSeconds`.

### Não executados: limitação
**Não havia Roblox Studio nem um interpretador Luau neste ambiente.** Por isso **nenhum teste de execução foi declarado aprovado.**
Para validar, rode `testes/DelegaciaAutoTest.server.lua` (instruções no cabeçalho do arquivo). Ele verifica automaticamente:
- inicialização (remotes, 13 missões, celas, presos de ambiente, serviço);
- frota (2 viaturas, sem duplicata);
- custódia ponta a ponta em `perimeter_breach` e `most_wanted`: a missão conclui, o modelo continua existindo, entra em `Prisoners()` e chega a `jailed`;
- bomba: 2 bonecos ao lado do pacote devem ficar com **exatamente 60 de vida**;
- apagão: começa em `off`, não volta para `on` sem os geradores, e o `Cleanup` restaura;
- rebelião: o amotinado morto é removido;
- smoke test das 13 missões: inicia, encerra e não deixa NPC, marcador, prompt, alarme ou energia alterada para trás;
- preso morto na custódia é removido;
- resumo de avisos e erros do Output.

### Procedimento manual (o que não dá para automatizar no servidor)
Faça com 1 jogador no Play (F5) e com 2 jogadores em "Start Server + 2 Players" quando indicado:
1. **Serviço e patentes**: bata o ponto em `Ponto`, confira o HUD ("EM SERVIÇO") e o XP ao algemar ou fichar.
2. **Armaria**: pegue os itens em `Armaria` e confira a restrição por patente.
3. **Algemas e escolta**: algeme (E) com as ALGEMAS equipadas, escolte (F), revise (G) e solte.
4. **Ficha e cela**: em `most_wanted`, `interrogation`, `hostage` e `perimeter_breach`, fiche no balcão e **veja o suspeito andar até a cela e a grade fechar**. Ele não pode sumir.
5. **Evidências e perícia**: `crime_scene` completa (coleta, cofre e as duas análises no `LabTerminal`).
6. **CCTV, alarme e energia**: `CCTVConsole` (entrar e sair); `blackout`: religue os 3 geradores e confirme que a tela fica escura em "FALHA" e depois em "GERADOR", e só volta ao normal depois do 3º.
7. **Frota**: `FleetTerminal` → Viatura 1 e Viatura 2 vão para a baia, depois devolva. Dirija as duas para confirmar que o chassi funciona.
8. **Bomba**: erre o minigame 2 vezes perto de um colega. Ele deve perder 40 de vida, não morrer.
9. **As 13 missões jogadas até o fim**: blackout, bomb_threat, crime_scene, hack_intrusion, hostage, interrogation, most_wanted, patrol, perimeter_breach, prison_break, prisoner_transfer, riot, shooting_exam.
10. **Mobile**: Device Emulator (celular). Confira prompts tocáveis, HUD sem cortes, diálogos e minigames.
11. **Output**: nenhum `[Delegacia] erro …` nem stack trace.

## 4. Riscos de regressão
- **Ordem do evento em `Custody.Book`**: os ouvintes de `SuspectBooked` agora recebem o preso já com `rec.Cell` definido e já em `Prisoners()`. Os 4 ouvintes existentes só somam progresso ou bônus, então não há impacto. Missões novas que dependam da ordem antiga precisam levar isso em conta.
- **Suspeito fichado em missão encerrada**: agora ele continua existindo até ser preso e é liberado depois de `HoldSeconds` (240 s), como qualquer preso fichado por um jogador. É o comportamento pretendido.
- **Lotação**: se as 4 celas estiverem cheias (3 por cela), `Custody.Jail` falha e o suspeito é removido pelo `Cleanup`, exatamente como antes.
- **Observações fora do escopo (não alteradas)**: `bomb_threat.OnFail` também explode quando a missão é cancelada (`ForceMission`) ou dá erro interno. Em `prisoner_transfer`, fichar o detento no balcão trava a missão até o tempo acabar.
