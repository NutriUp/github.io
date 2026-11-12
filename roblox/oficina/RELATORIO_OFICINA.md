# Oficina TORQUE CUSTOMS — reconstrução e sistema de personalização

| Arquivo | Conteúdo |
|---|---|
| `OFICINA.ORIGINAL.rbxmx` | modelo original intacto (sha256 `c0de0553…cb6c47`) |
| `OFICINA_TorqueCustoms.rbxmx` | modelo atualizado: cenário original + `OficinaObjetos` + sistema `Oficina` |
| `scripts/*.lua` | os 9 scripts do sistema, para revisão (iguais aos que estão dentro do modelo) |
| `testes/OficinaAutoTest.server.lua` | roteiro de teste automático para o Studio |

## 0. Limitações desta entrega (leia primeiro)
- **Sem acesso ao Roblox Studio nem ao `BATTLE ROYAL.rbxl`.** O MCP `roblox-studio` não existe nesta sessão. Nada foi alterado no place, e nenhum playtest foi executado.
- **Não pude ler `CarSpawning`, `ReplicatedStorage.Car` nem `VehicleDamage`.** Portanto não sei como os carros do jogo nascem, como registram o dono ou como guardam o dano. O único veículo que inspecionei de verdade foi a viatura **A-Chassis** (FEDERAL CAR) do arquivo da delegacia.
- Em consequência, três pontos ficam atrás de adaptadores com suposições explícitas (seção 4). **A integração com os carros reais do jogo não está validada**, e os critérios de aceite 3, 9 e 11 só podem ser confirmados no Studio.
- Validação feita: estática (XML, sintaxe, revisão de fluxo). Testes de execução: **não realizados**.

## 1. Inspeção do modelo original
- Garagem de corrida (asset Roblox): 972 instâncias, **nenhum script**, 2 portões de enrolar, 2 fossos com elevadores de 2 colunas, bancadas na parede leste.
- **Os dois portões são malhas sólidas fechadas com colisão**: nenhum carro conseguia entrar.
- Salão principal: X −243…−185, Z 138…233, piso em Y = 10. Os boxes ficam sobre os fossos, em (−214, 163) e (−214, 198), com entrada pelo oeste.
- O anexo norte é um bloco único (Union) cujo interior não pude verificar; não coloquei nada lá.

## 2. O que foi construído

### Estrutura física (77 instâncias novas, todas em `OficinaObjetos`; o cenário original não foi tocado)
- **Portões automáticos**: os portões originais enrolam para cima quando alguém se aproxima e fecham depois. É feito por script; as peças originais são as mesmas.
- **2 boxes**: zona de atendimento (`Box_N`), console com tela (`Console_N`), faixas amarelas no piso, linha de parada e luminárias industriais com SpotLight.
- **Identidade visual**: letreiro "TORQUE CUSTOMS" com neon na fachada e painel interno na parede leste.
- **Recepção** (balcão, monitor, placa suspensa), **área de espera** (banco, mesa, tapete, placa) e **compressor**. Todos ficam em áreas livres, conferidas num mapa de ocupação do modelo.

### Arquitetura (`Oficina/`)
| Script | Responsabilidade |
|---|---|
| `Core` (Script) | cria os remotes, carrega os módulos com `pcall`, monta as telas dos consoles, instala a interface |
| `Modules/Config` | **único lugar** de preços, categorias, níveis, paleta, câmeras, sons e nomes de integração |
| `Modules/Economia` | integração com `leaderstats.Dinheiro` existente; nunca cria nada; `DefinirProvedor` para o módulo da T03 |
| `Modules/Veiculos` | adaptador dos veículos reais: descobre o carro pelo assento, o dono e o tipo; fixa no box; reparo |
| `Modules/Visual` | pintura, rodas, vidros, neon, aerofólio, escapamento (compartilhado: o servidor aplica, o cliente pré-visualiza) |
| `Modules/Desempenho` | melhorias mecânicas com efeito real |
| `Modules/Sessoes` | atendimentos, validação e precificação no servidor, vigia de desconexão e saída |
| `Modules/Portoes` | portões automáticos |
| `Client/OficinaCliente` | interface, câmera, pré-visualização local, ajuste do Tune A-Chassis |

Remotes em `ReplicatedStorage.OficinaRemotes`: `Sessao` (RemoteEvent) e `Comprar` (RemoteFunction).

### Fluxo do jogador
1. Dirige até a oficina; o portão abre.
2. Para dentro das faixas do box e segura **E** no console.
3. O servidor valida (seção 3), fixa o carro e abre a interface, com a câmera girando em volta do veículo.
4. O jogador escolhe categorias e **vê cada alteração no próprio carro**. A pré-visualização é local: ninguém mais vê e nada é cobrado.
5. "Voltar" desfaz a categoria aberta; "Cancelar alterações" restaura tudo; "Aplicar e pagar" pede confirmação.
6. O servidor recalcula o preço, cobra e aplica; a alteração replica para todos.
7. Sair do carro, morrer, desconectar ou passar de 5 minutos encerra o atendimento e libera o carro.

## 3. Segurança e multiplayer
- O cliente envia só `{ categoria = valor }`. **Preço, saldo, dono e disponibilidade são decididos no servidor**, a partir da `Config`.
- Validações ao iniciar: está no assento do motorista, é o dono (ou o motorista, se não houver dono registrado), o carro está dentro da zona e parado, o box está livre e o carro não está em outra sessão.
- Validações na compra: sessão ativa, carro ainda no box, tipos estritos, categoria e opção existentes, nível inteiro maior que o atual e até o máximo, limite de itens, antiflood de 1 s e trava contra compra simultânea (sem cobrança dupla).
- Um box atende um jogador por vez; um jogador tem uma sessão; um carro tem uma sessão.
- Cancelar, sair ou desconectar não deixa nada aplicado: a pré-visualização só existe no cliente.
- Nenhuma moeda, `leaderstats` ou DataStore é criado.

## 4. O que é realmente funcional, por tipo de veículo

| Categoria | A-Chassis (verificado no código da viatura) | VehicleSeat clássico | Outros (ex.: `ReplicatedStorage.Car`) |
|---|---|---|---|
| Pintura primária / secundária | Sim: muda `Color` das peças da cor dominante e da segunda cor | Sim | Sim, se as peças aceitarem `Color` |
| Rodas e aros | Sim (peças claras dentro de `Wheels`; pneus ficam pretos) | Sim | Sim, se houver peças de roda identificáveis |
| Insulfilm | Sim, se houver peças de vidro | Sim | Sim |
| Neon, aerofólio, escapamento | Sim: peças construídas medindo o carro e soldadas nele | Sim | Sim (precisa de um `VehicleSeat`) |
| Motor | **Real**: `Horsepower`, `E_Horsepower`, `E_Torque` | **Real**: `MaxSpeed` e `Torque` | **Não suportado** (aparece como indisponível) |
| Turbo | **Real**: `T_Boost`, `Turbochargers` | Real: `MaxSpeed` | Não suportado |
| Transmissão | **Real**: `FinalDrive` | Real: `Torque` | Não suportado |
| Freios | **Real**: `BrakeForce`, `PBrakeForce` | Não suportado | Não suportado |
| Suspensão | **Real**: `Stiffness` e `Damping` das molas (`SpringConstraint`) | Só se houver molas | Só se houver molas |
| Reparo | Só com integração (ver abaixo) | idem | idem |

**Como as melhorias do A-Chassis têm efeito:** a física do A-Chassis roda no cliente do motorista, que lê o módulo `A-Chassis Tune` toda vez que alguém assume o volante (confirmado em `Drive`, linha 22, e em `Initialize`, linhas 660–664). O servidor grava os níveis como atributos do carro; cada cliente ajusta a própria cópia do Tune a partir deles; ao sair da oficina o servidor faz o motorista sentar de novo, para o chassi reler os valores.

**Não implementado, por não haver base verificável:** para-choques, capôs e troca de pneus. Exigem malhas específicas de cada modelo de carro, que não pude inspecionar; oferecer isso seria protótipo visual. Categorias que o carro não suporta aparecem desabilitadas, com explicação.

**Limitações conhecidas dos veículos:**
- Peças com `SurfaceAppearance` ou textura podem não mudar de cor com a pintura.
- A classificação de carroceria é por cor dominante; modelos com muitas cores podem pintar menos peças do que o esperado.
- O carro fica ancorado pelo `DriveSeat` durante o atendimento.

## 5. Dependências e integrações pendentes
| Dependência | Situação | Onde ligar |
|---|---|---|
| **Dono do veículo** (`CarSpawning`) | Suposição: a oficina procura os atributos `Dono/Owner/OwnerId/OwnerUserId/…` ou valores `Dono/Owner` no modelo. Sem dono registrado, **vale quem está dirigindo**. | `Config.Dono` (nomes e `AceitarMotoristaSemDono`) |
| **Dano e reparo** (`VehicleDamage`) | Suposição: vida em atributo do modelo (`Vida/Health/…`). Se não encontrar, o reparo fica indisponível. | `Config.Reparo` ou `Veiculos.DefinirReparo(fn)` |
| **Carros de `ReplicatedStorage.Car`** | Não inspecionados. O visual deve funcionar; as melhorias mecânicas dependem de saber como o sistema lê potência e freio. | novo ramo em `Desempenho` |
| **Economia / T03** | Usa `leaderstats.Dinheiro` direto. Se o jogador não tiver esse valor, as compras são recusadas ("economia indisponível"). | `Economia.DefinirProvedor({ Saldo, Cobrar })` quando o módulo central existir |
| **Persistência das personalizações** | **Não existe.** Não encontrei estrutura de persistência de veículos, e não criei uma paralela. O estado fica em atributos do carro (`OfPintura`, `OfN_motor`, …) e some quando o carro é destruído. | `Visual.LerEstado(car)` e `Visual.AplicarEstado(car)` + `Desempenho.AplicarServidor(car)` já servem para salvar e restaurar |
| **Sons** | `Config.Sons` com campos vazios; nenhum ID inventado. | `Config.Sons` |

## 6. Testes
- **Estáticos (feitos):** o XML do modelo é lido sem erro; o conteúdo original está preservado byte a byte, com os 77 itens novos inseridos antes do fechamento do modelo; referents únicos; verificador léxico aprovado nos 9 scripts e no teste; mapa de ocupação para o posicionamento da mobília.
- **Execução (não feita):** rode `testes/OficinaAutoTest.server.lua`. Ele monta um carro de teste no Box 1 e verifica:
  - inicialização e portão;
  - economia sem criar nada;
  - classificação das peças;
  - 8 tentativas de exploração do remote (preço enviado pelo cliente, nível inválido, categoria falsa, saldo insuficiente…);
  - compra válida com total calculado pelo servidor e débito único;
  - efeito real do motor;
  - recompra e rebaixamento recusados;
  - remoção de neon;
  - dono diferente recusado;
  - saída do carro encerrando a sessão.
- **Manual, obrigatório antes de aceitar:**
  1. Entrar com um carro real do `CarSpawning` e com uma viatura A-Chassis.
  2. Pré-visualizar, cancelar e conferir que o carro voltou ao estado anterior.
  3. Comprar motor e freios num A-Chassis e sentir a diferença ao sair.
  4. Dois jogadores: um em cada box; um tentando usar o carro do outro; sair do jogo no meio do atendimento.
  5. Mobile (Device Emulator): interface, botões e seletor de cor por toque.
  6. Conferir se os portões não prendem veículos.

## 7. Riscos
- O ajuste de `Size` dos portões (MeshPart) em tempo de execução deve ser observado no Studio; se a malha não escalar bem, basta trocar por transparência em `Portoes`.
- O reassento automático após melhorias mecânicas depende de o A-Chassis recriar a interface ao sentar (comportamento lido no `Initialize`).
- Carros destruídos e recriados pelo `CarSpawning` perdem as personalizações (ver persistência).
