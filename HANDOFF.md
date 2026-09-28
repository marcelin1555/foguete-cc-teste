# Handoff do projeto foguete-cc-teste

Resumo de tudo o que existe e foi feito até 28/09/2026, para quem continuar o trabalho.

## Objetivo

Um foguete no Minecraft, 100% survival e totalmente automático, que decola com um jogador sentado, entra em órbita, sai de órbita e pousa. Todo o controle é feito por scripts Lua no CC: Tweaked.

**Mods**
- Create: Cosmonautics (rocketnautics), versão **26.08.307**. Não é a 1.4: nessa versão não existe Gyrodyne, mas existe o Magnetic Stabilizer.
- Create Aeronautics / Sable (física das naves)
- CC: Tweaked

**Regras do dono do projeto**
- Os commits saem no nome dele (`marcelin1555`), sem nenhum trailer de IA nem `Co-Authored-By`.
- Os textos para ele são em português.
- No jogo, ele atualiza os scripts com o comando `atualizar`, que baixa tudo deste repositório.

## Arquivos

| Arquivo | O que faz |
|---|---|
| `voo.lua` | Piloto automático, com todas as fases do voo. É o arquivo principal (~1400 linhas). |
| `setup.lua` | Assistente que cria o `config.lua`: estágios, motores, separadores, stabilizer e Sputnik. |
| `sputnik_guiagem.lua` | Script colado no nó Lua da Sputnik. Faz a curva de gravidade na subida e o PID de direção. |
| `log.lua` | Biblioteca de log: um arquivo por voo em `/logs/AAAA-MM-DD_HH-MM-SS_<tipo>.txt`, mais `_telemetria.csv`. |
| `logs.lua` | Leitor de logs: `logs`, `logs lista`, `logs N`, `logs erros`, `logs motores`, `logs fisica`, `logs tudo`, `logs limpar`. |
| `diagnostico.lua` | Lista os lados do computador, os periféricos (com o tipo de motor) e o que está na config mas não está conectado. |
| `atualizar.lua` | Baixa os arquivos do GitHub e confere a sintaxe com `load()` antes de trocar. |
| `parar.lua` | Corta todos os motores. |
| `startup.lua` | Retoma um voo em andamento depois que o computador reinicia. |
| `ferramentas/sim*.py` | Simulador fora do jogo (veja abaixo). O `atualizar` não baixa esta pasta. |

O `.gitignore` deixa de fora `config.lua`, `estado.txt`, `rcs.cal` e `logs/`, que são arquivos específicos de cada foguete.

**Comandos no jogo:** `setup`, `diagnostico`, `voo`, `voo teste` (só o preflight), `voo descer [Y]` (vai direto para o pouso), `voo rcs` (calibra o RCS), `voo reset`, `parar`, `logs`, `atualizar`.

## Como o voo funciona (`voo.lua`)

Fases: `ASCENT → BALISTICO → COAST/CIRC (órbita) → ORBIT → DEORBIT → REENTRADA → POUSO`.

- **Preflight.** Aborta se:
  - não houver Vector Thruster no estágio 1;
  - o TWR for menor que `min_twr`;
  - os boosters tiverem potências diferentes.
- **Subida.** A Sputnik faz a curva de gravidade. O `voo` controla o empuxo, o gimbal (PD + integral: `kp`, `kd`, `ki`, `imax`) e a troca de estágio.
- **Equilíbrio de empuxo.** Durante a ASCENT, a cada 1,5 s: se a diferença entre os motores passar de 0,2, todos ficam limitados à média (`S.thrCap`). O limite sobe 50 N quando todos alcançam o teto. Foi criado porque as bombas não entregavam lava igual para todos os motores e o foguete tombava.
- **Boosters.** Acendem junto com os motores de lava do mesmo estágio. Quando **todos** acabam, `checkBoosterDrop` manda um pulso em `booster_separator` e os tira da lista (`S.boostersDropped`).
- **Troca de estágio.** Quando a lava acaba, `separate(i)` pulsa `stages[i].separator` e passa para o estágio seguinte.
- **Órbita (COAST/CIRC).**
  - Usa `getDeepSpaceData` da Sputnik: semiMajorAxis, eccentricity, velocity etc.
  - Queima na direção da velocidade orbital. Se o semieixo cair, inverte o sinal. Se nada mudar, testa 90°.
  - Para quando o periapsis chega a ≥ min(`orbit_peri_alt` 23000, dist−300).
- **Apontar antes de acender.**
  - No espaço e no pouso, primeiro só o Vector gira a nave (`orient_throttle` 0,35), com os outros motores desligados.
  - Acende tudo quando o erro fica abaixo de `align_deg` (5°) com rotação baixa (`align_rate`).
  - Mantém a queima enquanto o erro for menor que `align_keep_deg` (15°).
- **Magnetic Stabilizer** (`CFG.stabilizer`, pelo lado do computador ou por um relay). É ligado por redstone e só amortece a rotação, não aponta a nave. Quando fica ligado:
  - COAST: quando não está apontando;
  - CIRC e DEORBIT: durante a queima;
  - REENTRADA: sempre;
  - POUSO: com erro menor que 15°;
  - ASCENT: se `stab_ascent` estiver ligado.
- **Pouso.**
  - Mede a gravidade de verdade (no pad deu ~11).
  - Usa `ground_y` e `land_ceiling_y` (teto de 400).
  - Freia a velocidade horizontal e detecta o contato com o chão.
- **RCS.** Desligado por padrão, a pedido do dono. Só funciona com `rcs_enabled = true`. Pelo CC dá só para ligar e desligar; o nível de empuxo quem define é a Sputnik.
- **Gyrodyne.** Tem suporte opcional no código, mas o bloco não existe na versão usada.

As outras chaves do `config.lua` têm valor padrão no início de `voo.lua`. Procure por `CFG.`.

## Fatos da mecânica, conferidos no código-fonte da 26.08.307

- **Rocket / Vector Thruster**
  - Máximo de 1000 N.
  - `setThrust` em newtons, arredondado de 50 em 50.
  - Tanque interno de 1000 mB. Gasta 40 mB/tick (0,8 balde/s) a 100%.
  - O fogo derrete até 3 blocos atrás do bico.
- **Booster Thruster**
  - Acende por redstone encostada **ou** por `setActive` do computador. Depois de aceso, não desliga mais.
  - Combustível: **só Bloco de Carvão** do Minecraft, encostado atrás do bico. Camadas de até 3×3 e até 64 de profundidade.
  - Gasta **um bloco por vez, 10 s (200 ticks) cada**.
  - Potência ajustável de 50 em 50 N, até 1000 N.
  - `getData` retorna `ignited`, `is_spent`, `thrust_power` e `ignition_ticks`.
- **Stage Separator / Separator Charge**
  - Qualquer sinal de redstone vizinho faz o bloco sumir.
  - Separadores vizinhos se ligam sozinhos (aparece um pino) e explodem em corrente. A Wrench liga e desliga cada pino.
  - O Charge também destrói o bloco atrás dele, ou seja, o bloco em que se clicou para colocá-lo. É assim que se corta o cabo de rede na separação.
- **Tanque de fluido do Create:** 8 baldes por bloco, base de no máximo 3×3, até 32 de altura. Uma camada de 3×3 guarda 72 baldes.
- **Sputnik:**
  - No espaço profundo, a nave fica parada na própria dimensão (Y≈1133) e a órbita é simulada.
  - Volta para o overworld abaixo de ~21000 de distância.

## Situação do foguete do jogador

- **Último voo analisado:** 13 motores, massa 415. As bombas entregavam ~140 dos 520 mB/t necessários, então o empuxo caiu para ~5300 N quando os tanques internos esvaziaram. O foguete tombou a 51°. Isso levou ao equilíbrio de empuxo e à recomendação de usar boosters, mais bombas/RPM e canos curtos do mesmo tamanho.
- **Lados do computador:**
  - `top` = Sputnik;
  - `bottom` = Magnetic Stabilizer;
  - `back` = modem com fio.

  Separadores e boosters usam **relays**, nunca o `bottom`.
- **Em construção:** um foguete de 2 estágios com 4 boosters, conforme o esquema (link abaixo).
  - Estágio 1: 4 Rocket + 1 Vector, tanque de lava 3×3 (144 baldes com 2 de altura; a sugestão é 3×3×4 = 288).
  - Estágio 2: 2 Rocket + 1 Vector, sugestão de tanque 2×2×3.
  - Boosters: 4 de 1000 N.
- **Teste de booster (último print):**
  - Fileira de separadores ligando o booster, com o cabo passando **por fora** dela.
  - O dono foi orientado a trocar o separador acima do cabo por um Separator Charge, colocado clicando no cabo, e a testar com uma alavanca antes do voo.
  - Ainda falta confirmar que o corpo preto do booster é mesmo Bloco de Carvão.

## Esquemas publicados (privados, na conta do dono)

- Sistema de boosters: https://claude.ai/artifact/UNyTu7Ke1i94yCn8x34LaC
- Foguete de dois estágios com boosters (lista de blocos, fiação, respostas do setup, checklist): https://claude.ai/artifact/Vx3yE4HX5g53JYtAn6fP4e

## Simulador (`ferramentas/`)

- Precisa de Python 3 com `lupa` (`pip install lupa`).
- Roda a partir da raiz do repositório:
  - `python3 ferramentas/sim.py` simula a órbita;
  - `sim2.py` testa os comandos `voo`, `voo reset` e `voo teste`;
  - `sim3.py` simula a subida com 4 boosters e a separação.
- Simula `fs`, os periféricos, a Sputnik, a redstone (`STAB`, `PULSOS`) e os boosters.
- Variáveis de ambiente: `RCSN`, `NOTHR`, `STAB`, `ARG1`, `FRACO`.
- A física é bem simplificada. Serve para pegar erros de lógica e de Lua, não para ajustar ganhos de controle.

## Próximos passos

1. O dono termina o foguete de 2 estágios. Depois:
   - `diagnostico`, que deve mostrar Vector ×2, Rocket ×6 e Booster ×4;
   - `setup`, com os boosters no estágio 1, `booster_separator` = Relay B, separador do estágio 1 = Relay A e stabilizer = `bottom`;
   - `voo teste`.
2. Primeiro voo real. Com os logs (`logs lista`, depois mandar o arquivo `.txt` e o `_telemetria.csv`), conferir:
   - se os boosters caíram na hora certa;
   - se a separação do estágio 1 cortou o cabo;
   - a sobra de lava em cada estágio, na linha `COMBUSTIVEL`.
3. Ajustar o tamanho dos tanques e os ganhos (`kp`, `kd`, `ki`) pelo log.
4. Ainda não testado em voo real: circularização completa, saída de órbita e pouso com o Magnetic Stabilizer.
