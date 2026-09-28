# Refatoração em módulos: design

Data: 28/09/2026. Branch: `refatoracao-modulos`.

## Objetivo

Dividir o código para que cada ajuste futuro mexa num arquivo pequeno, **sem mudar o comportamento do voo**. Hoje o `voo.lua` tem 1406 linhas, e a função `voo()` sozinha tem ~590, organizadas como um único `while` com um `if/elseif` por fase.

**Critérios de sucesso**
1. Todos os cenários do simulador produzem **a mesma sequência** de trocas de fase, comandos aos periféricos, linhas de log e estado final no código antigo e no novo. As exceções estão listadas mais abaixo.
2. O `config.lua` e o `estado.txt` que o jogador já tem continuam funcionando sem rodar `setup` e sem `voo reset`. Um voo em andamento é retomado depois da atualização.
3. Os comandos digitados no jogo continuam com os mesmos nomes e argumentos.
4. O `sputnik_guiagem.lua` não muda de comportamento, então não é preciso colar de novo na Sputnik.
5. Nenhum módulo passa de ~250 linhas.

**Fora do escopo:** mudar ganhos, fórmulas, tempos ou mensagens do voo; novos recursos; mudar o script da Sputnik.

## Decisões tomadas com o dono

| Tema | Decisão |
|---|---|
| Objetivo | Facilitar mudanças: módulos pequenos, comportamento igual |
| Gyrodyne | **Removido.** O bloco não existe na 26.08.307. |
| RCS | Vira o módulo `rcs.lua`, que só age com `rcs_enabled = true` (como hoje) |
| Validação | Um simulador unificado + comparação com uma referência gravada do código antigo |
| Organização | Comandos na raiz; partes internas em `/lib/foguete/`; o `atualizar` lê a lista do GitHub |
| Arquitetura | Uma fase por arquivo, todas com a mesma interface; o laço principal fica separado |

## 1. Mapa de arquivos

**Raiz** (comandos digitados no jogo, arquivos finos):

| Arquivo | Função |
|---|---|
| `voo.lua` | Lê os argumentos (`teste`, `reset`, `descer [Y]`, `rcs`, nenhum) e chama `laco`, `checagem` ou `rcs` |
| `setup.lua` | Assistente do `config.lua` (mesmo formato de saída de hoje) |
| `logs.lua` | Leitor de logs, igual ao de hoje (lê os arquivos de `/logs` direto) |
| `diagnostico.lua` | Igual ao de hoje e independente de `/lib`, para funcionar mesmo com a instalação incompleta |
| `parar.lua` | Corta os motores. Continua independente de `/lib`, para funcionar mesmo com a instalação incompleta. |
| `atualizar.lua` | Baixa usando `arquivos.txt` (ver seção 4) |
| `startup.lua` | Retoma o voo |
| `sputnik_guiagem.lua` | Script da Sputnik. Não é dividido em módulos; ganha só `-- versao: N` |
| `arquivos.txt` | Lista de arquivos que o `atualizar` baixa, mais a seção `remover:` |

**`/lib/foguete/`:**

| Módulo | Responsabilidade | Origem no `voo.lua` atual |
|---|---|---|
| `config.lua` | Tabela de padrões comentada (todas as ~53 chaves), carrega o config do jogador por cima, remove motores repetidos, avisa de chaves desconhecidas | topo do arquivo + os ~30 `CFG.x or ...` |
| `estado.lua` | `carregar`, `salvar`, `trocar(fase, motivo)`, validação do nome da fase | `save`, `load`, `setPhase` |
| `mat.lua` | `clamp`, `qrot`, `toLocal`, `quatParts` | matemática |
| `sensores.lua` | `lerNave()` rápida (4 leituras em paralelo), `gravidade()`, leitura lenta (a cada 0,5 s) | `readShip`, `gravity`, bloco `if slow` |
| `sputnik.lua` | `dados()`, `direcaoOrbital()`, `periastro()`, vr, log `SPUTNIK`/`ORBITA` | `sputnik`, `orbitDir`, `periAlt` |
| `motores.lua` | `call`, `typeOf`, listas de motores, `setThrottle`, `orientThrottle`, `ignite`, `shutdown`, `safeAll`, `stageStatus`, `lavaTotal`, `engineLine`/`logEngines`, `equilibrar()` | periféricos + bloco de equilíbrio de empuxo |
| `controle.lua` | `steer` (PD+I), `alinhado`, `estabilizador(on)` | `steer`, `alignedFor`, `stabilizer` |
| `separacao.lua` | `pulso`, `separar(i)`, `largarBoosters(i)`, `confirmarIgnicaoBoosters()` | `pulse`, `separate`, `checkBoosterDrop`, bloco de retry dos Boosters |
| `checagem.lua` | `preflight()`, `teste()` | `preflight`, `teste` |
| `tela.lua` | `mostrar(linhas)` no terminal e no monitor | `show` |
| `telemetria.lua` | CSV e linha `FISICA` | `csvLine` + bloco de calibração |
| `rcs.lua` | RCS (descoberta, calibração, controle, `voo rcs`); não faz nada sem `rcs_enabled = true` | bloco RCS |
| `log.lua` | Biblioteca de log (movida da raiz, API igual) | `log.lua` |
| `laco.lua` | Laço principal: plataforma, retomada e ciclo por tick | `voo()` |
| `fases/plataforma.lua` | Preflight, espera do botão e contagem (PAD) | começo de `voo()` |
| `fases/subida.lua` | ASCENT e BALISTICO | ramo correspondente |
| `fases/orbita.lua` | COAST e CIRC | ramo correspondente |
| `fases/deorbit.lua` | DEORBIT | ramo correspondente |
| `fases/reentrada.lua` | REENTRADA | ramo correspondente |
| `fases/pouso.lua` | POUSO | ramo correspondente |

As fases terminais (`ORBIT`, `FALHA`, `FIM`, `POUSADO`) são tratadas no `laco.lua`, que mostra o resumo e sai, como hoje.

**Removido:** Gyrodyne (`gyroNames`, `gyroMode` e as chamadas a eles).

Regras para todos os módulos:
- sem variáveis globais;
- dependências recebidas por parâmetro (`ctx`, `cfg`, `log`);
- carregamento com `require("foguete.<modulo>")`: cada comando da raiz acrescenta `/lib/?.lua` ao `package.path` antes do primeiro `require`.

## 2. Interface das fases e contexto

Cada arquivo em `fases/` devolve uma tabela:

```lua
return {
  fases = { "COAST", "CIRC" },                 -- nomes de fase que o módulo atende
  novaMemoria = function() return { flips = 0 } end, -- memória volátil do módulo
  tick = function(ctx) end,                    -- um passo da fase
  estabilizador = function(ctx) return false end,
}
```

- Para trocar de fase, a fase chama `ctx.trocar(fase, motivo)`. Essa é a **única** função que troca de fase: ela grava no log e salva o estado, como o `setPhase` de hoje. A troca acontece **no mesmo ponto do código** em que acontece hoje, então a ordem dos comandos não muda.
- A memória de cada módulo (`ctx.mem`) é criada **uma vez por execução do `voo`** e **não é zerada nas trocas de fase**. Hoje as tabelas `orb`, `deorbit` e `land` funcionam assim, e a `orb` guarda dados de COAST para CIRC.
- Os comandos feitos ao retomar um voo (acender, desligar ou apontar conforme a fase) ficam no `laco.lua`, na mesma ordem de hoje. Numa troca de fase comum não existe comando de entrada.
- A troca de estágio, o que fazer quando a lava do último estágio acaba e o equilíbrio de empuxo ficam no `laco.lua`, na **mesma ordem de hoje**: equilíbrio → troca de estágio → tick da fase. Mover esses trechos para dentro das fases mudaria a ordem das chamadas aos motores.
- Uma fase com vários nomes (COAST/CIRC, ASCENT/BALISTICO) lê `ctx.S.phase`.

**Contexto `ctx`** (montado pelo laço):

| Campo | Conteúdo |
|---|---|
| `ctx.cfg` | config com os padrões |
| `ctx.S` | estado persistente (`estado.txt`), mesmos campos de hoje |
| `ctx.nave` | `pos`, `q`, `vel`, `angv`, `mass`, `speed` (todo tick) |
| `ctx.lento` | `true` no tick lento (a cada 0,5 s) |
| `ctx.orb` | `dsd`, `inSpace`, `ecc`, `dist`, `vr`, `g` (atualizados no tick lento) |
| `ctx.mot` | `thrust`, `spent`, `burnStart`, `igniteT` |
| `ctx.mem` | memória volátil do módulo da fase atual, criada uma vez por execução (substitui `orb`, `land` e `deorbit` locais) |
| `ctx.trocar` | `trocar(fase, motivo)`: troca de fase, grava no log e salva |
| `ctx.saida` | `tilt`, `err`, `gx`, `gz` para a tela e a telemetria |
| `ctx.agora`, `ctx.dt`, `ctx.log` | tempo e log |

**Ordem do tick no `laco.lua`**, a mesma ordem de hoje:
1. `sensores.lerNave`. No tick lento: gravidade, Sputnik, vr, `stageStatus` e os logs `SPUTNIK`/`ORBITA`.
2. `separacao.confirmarIgnicaoBoosters` (até 4 s após a ignição) e `separacao.largarBoosters`.
3. `motores.equilibrar` (só na fase ASCENT, como hoje).
4. Troca de estágio quando o estágio esgota. Se for o último, a mesma escolha de hoje (BALISTICO, FIM, REENTRADA ou erro de pouso).
5. `fase.tick(ctx)` do módulo da fase atual.
6. Telemetria (`FISICA`, `COMBUSTIVEL`, `logEngines` periódico).
7. `controle.estabilizador(fase.estabilizador(ctx))`.
8. Fim ao chegar numa fase terminal; senão CSV e tela.

## 3. Compatibilidade e erros

- **config.lua:** a tabela de padrões usa os mesmos nomes e valores que hoje estão soltos no código. Chave desconhecida gera AVISO no preflight e não bloqueia o voo. O `setup` continua gerando o mesmo formato.
- **estado.txt:** mantém os campos `phase`, `stage`, `padY`, `groundY`, `thrCap`, `deorbitSign`, `progSign`, `fuelOut`, `failed`, `boostersDropped`, `logFile` e `t0`, e os mesmos nomes de fase.
- **Chamadas a periféricos:** continuam protegidas; as falhas vão para o log como ERRO.
- **Crash:** o `voo.lua` roda tudo dentro de `xpcall`, grava o rastreamento no log e chama `motores.safeAll`.
- **Módulo faltando:** os comandos da raiz conferem os arquivos de `/lib/foguete` ao abrir e mostram "Arquivo lib/foguete/X faltando, rode atualizar".
- **Fase desconhecida no estado:** o voo não começa e aparece a mensagem para usar `voo reset`.

## 4. Atualizador e Sputnik

- **`arquivos.txt`:** um caminho por linha; linhas depois de `remover:` são apagadas no computador. As linhas começando com `#` são comentários.
- **Tudo ou nada.** O `atualizar`:
  1. baixa o `arquivos.txt`;
  2. baixa todos os arquivos para a memória;
  3. confere a sintaxe de todos com `load()`;
  4. só então cria as pastas, grava tudo e apaga os da lista `remover:`.

  Se qualquer passo falhar, não troca nada.
- **Nunca toca** em `config.lua`, `estado.txt`, `rcs.cal` e `logs/`.
- `atualizar <arquivo>` continua baixando um arquivo só.
- **Transição:** o `atualizar` antigo baixa o novo junto com os outros arquivos. O novo avisa na tela: "rode atualizar de novo para baixar /lib".
- **Sputnik:** o `atualizar` compara o `sputnik_guiagem.lua` antigo com o novo e só pede para colar de novo na Sputnik se o conteúdo mudou.

## 5. Simulador e comparação

**Estrutura `ferramentas/sim/`**, com toda a lógica do simulador em Lua:

| Arquivo | Conteúdo |
|---|---|
| `ambiente.lua` | CC imitado: `fs` em memória, `peripheral`, `parallel`, `redstone`, `textutils`, `vector`, `sublevel`, `aero`, relógio, `http` (para o `atualizar`) |
| `mundo.lua` | Física simplificada, motores (empuxo, lava, Boosters com carvão), Sputnik (dados orbitais e troca de dimensão com reboot), separadores e o **gravador** de eventos |
| `cenarios/*.lua` | Um cenário por arquivo: config, estado inicial, comando e duração |
| `testar.py` | Roda os cenários com `lupa`, grava ou compara com `referencia/`, mostra o `diff` |

**Cenários:**

| Cenário | Cobre |
|---|---|
| `comandos` | `voo teste`, `voo reset`, preflight com erros (sem Vector, TWR baixo) |
| `subida_boosters` | 4 Boosters, largada, separação de estágio |
| `orbita_velocity`, `orbita_novel`, `orbita_inverted` | COAST → CIRC → ORBIT nos 3 modos do `sim.py` atual |
| `descida` | DEORBIT → REENTRADA → POUSO → POUSADO |
| `retomada` | Reboot no meio de ASCENT, CIRC, DEORBIT e POUSO |
| `config_minima` | Config só com as chaves obrigatórias |
| `atualizar` | Download completo, falha de rede no meio, erro de sintaxe (nada deve ser trocado) |

**O gravador** registra, em ordem:
- trocas de fase, com o motivo;
- chamadas aos periféricos: `setThrust`, `setActive`, `setGimbal` (arredondado a 3 casas), `setOutput` dos relays e da redstone;
- o texto das linhas de log, sem o carimbo de tempo;
- o `estado.txt` final.

**Referência**
1. Antes de mexer no código, os cenários de voo rodam no `voo.lua` atual e a saída fica gravada em `ferramentas/sim/referencia/<cenario>.txt`.
2. `python ferramentas/sim/testar.py` compara com a referência. `--gravar` regrava.
3. Os cenários `config_minima` e `atualizar` não têm equivalente no código antigo (o atualizador muda de propósito). Eles usam checagens próprias em vez de referência.

**Diferenças esperadas e aceitas** (cada uma tem que aparecer no `diff` e ser conferida):
1. Ausência de chamadas ligadas ao Gyrodyne.
2. Linha de AVISO de chave desconhecida, apenas quando o config tiver uma.
3. Caminho do arquivo de log, que muda porque o `log.lua` passa para `/lib`. O conteúdo é o mesmo.

**Limite:** a física simplificada prova que a lógica e os comandos não mudaram, mas não prova a qualidade do voo. A validação final é no jogo:
1. `atualizar` duas vezes;
2. `voo teste`;
3. um voo, analisando os logs.

**Requisito:** Python 3 com `lupa`.

## 6. Entrega

- Branch `refatoracao-modulos`. Commits no nome `marcelin1555`, sem trailer de IA.
- Ordem:
  1. simulador unificado + cenários;
  2. referência gravada com o código atual;
  3. extração módulo por módulo, com a comparação rodando a cada commit;
  4. `arquivos.txt` e o novo `atualizar`;
  5. atualização de `README.md` e `HANDOFF.md`.
- Os `sim.py`, `sim2.py` e `sim3.py` antigos são apagados quando os cenários equivalentes passarem.
- O merge no `main` fica para o dono, depois do teste no jogo.
