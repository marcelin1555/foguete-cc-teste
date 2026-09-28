# Histórico do projeto: foguete automático com CC: Tweaked + Cosmonautics

Tudo o que foi feito, do começo da conversa até 28/09/2026, em ordem. Para o estado atual e os próximos passos, veja o [HANDOFF.md](HANDOFF.md).

---

## 1. Planejamento (sessão anterior, no PC do jogador)

**Pedido inicial:** um foguete que chegue à órbita usando CC: Tweaked e Create: Cosmonautics.

**Requisitos definidos pelo dono:**
1. 100% survival.
2. 100% automático, com um lugar para sentar.
3. Ele sabe programar, mas deixa toda a programação comigo.

**O que aconteceu nessa sessão**, que rodava no Claude Code dentro da pasta do perfil Modrinth "Quiral":
- Fiz o esquema de montagem do foguete. A primeira versão tinha 4 motores sólidos nas laterais (bico laranja) e um Vector Thruster (branco).
- Resolvi um problema do Modrinth App em que o jogo não abria.
- Coloquei o código no computador do jogo e criei o sistema de logs, porque um motor sólido não acendeu.
- Decidimos usar **só motores de combustível líquido** (lava).
- Configurei a Sputnik (a sonda). O editor de Lua dela não abria, então o script foi colocado direto.
- **Bug:** os motores ligavam sozinhos assim que recebiam lava, sem ninguém acionar o voo. Foi corrigido.
- **Primeiro sucesso:** o foguete **chegou ao espaço** (Y≈19.900, 866 m/s, excentricidade 0,05).
- Começamos a manobra para descer no planeta (Obi).

---

## 2. Sessão na nuvem: correção do pouso

A sessão continuou num servidor na nuvem, sem acesso ao PC. Pedidos de Chrome Remote Desktop foram recusados, porque exigem a conta Google e o PIN do dono. A partir daqui, ele passou a mandar os arquivos pelo chat.

**Logs do pouso em Obi.** A subida estava ótima, mas o pouso tinha 3 erros:
1. **Chão errado.** Sem o estado salvo (depois de `voo reset`), o script usava a altura atual como chão. Ele chegou a declarar "POUSADO" a Y≈11.860, caindo a 243 m/s de lado.
2. **Motor aceso de lado.** Acelerava com o foguete a 160° do alvo.
3. **Gravidade errada.** O mod informava 11 m/s², mas a real lá em cima era ~1 m/s². O empuxo "só para girar" fazia o foguete **subir**.

**Pouso novo no `voo.lua`:**
- nunca usa a altura atual como chão;
- mede a gravidade real;
- freia a velocidade lateral;
- só acelera de verdade com menos de 60° de erro;
- controla o gimbal ele mesmo.

**`sputnik_guiagem.lua`:** o script da Sputnik também mexia no gimbal na descida e brigava com o computador. Agora ele só guia na subida.

**`SISTEMA.zip`:** o dono mandou o sistema inteiro. Confirmei que o computador ainda rodava o `voo.lua` antigo.

---

## 3. GitHub

- **Criação do repositório.** Tentei criar pela API, mas o controle de segurança da sessão bloqueou e não tentei contornar. O dono criou **`marcelin1555/foguete-cc-teste`** e eu enviei tudo.
- **Regra do dono:** *nenhum trailer de IA*. Os commits saem com autor `marcelin1555 <147268877+marcelin1555@users.noreply.github.com>`, sem `Co-Authored-By`.
- **`atualizar.lua`** (novo): baixa os arquivos do GitHub e confere a sintaxe antes de trocar. Nunca mexe em `config.lua`, `estado.txt` nem nos logs.
  - Primeira vez: `wget https://raw.githubusercontent.com/marcelin1555/foguete-cc-teste/main/atualizar.lua` e depois `atualizar`.
- **A Sputnik não se atualiza sozinha.** O `sputnik_guiagem.lua` precisa ser colado de novo no nó "Lua Script" dela sempre que mudar.

---

## 4. O jogo parou de abrir (dependências de mods)

O dono instalou o **Aeronautics: Interstellar Expansion (AeroIE / `vsie`)**, e o jogo passou a travar na abertura. Resolvemos uma dependência por vez, pelo `latest.log`:

| Erro | Solução |
|---|---|
| Photon 2.2.0 era novo demais para o `vsie`, e puxava KilaGraph → LDLib2 | Photon rebaixado para **2.1.5** e **KilaGraph removido** |
| Photon 2.1.5 e Easy Block Editor precisam do LDLib2 | Instalado **LDLib2 2.2.41** (no Modrinth aparece como "LDLib") |
| `vsie` precisa do GeckoLib | Instalado **GeckoLib 4.9.3** |
| `vsie` precisa do Ritchie's Projectile Library | Instalado **RPL 2.1.2** |

**Cuidado:** não atualizar o Photon para 2.2.x enquanto o AeroIE não aceitar essa versão.

---

## 5. Entrar em órbita (1 estágio)

**Problema:**
- a subida chegava a Y≈19.600, mas o periastro ficava **dentro do planeta** (≈ -504.000);
- faltava a queima de circularização.

**Três causas:**
1. **Direção errada.** No espaço profundo a nave fica **parada** na própria dimensão (Y≈1133) e a órbita é simulada pela Sputnik. O script apontava pela velocidade local, que ali é zero.
2. **O apoastro nunca era detectado.** A velocidade de subida ficava congelada.
3. **A lava acabava** logo depois de entrar no espaço.

**Solução** (commit `444c75a`):
- fases **COAST** (espera o apoastro), **CIRC** e **ORBIT**;
- queima na direção orbital usando `getDeepSpaceData` da Sputnik;
- inverte a direção se o semieixo cair e testa 90° se nada mudar;
- para quando o periastro passa de 23.000.

---

## 6. RCS (adicionado e depois desligado)

- O dono pediu RCS e depois avisou que teria 4, um em cada lateral.
- O que vi no código do mod:
  - pelo CC só dá para **ligar e desligar**; o nível de empuxo quem define é a Sputnik;
  - não gasta combustível;
  - empurra 12 N abaixo de Y=2000 e 105 N a partir de Y=5000.
- Implementei calibração automática (`rcs.cal`) e controle (commit `23026c2`).
- **Os nomes vinham repetidos** porque havia 2 modems na mesma rede. O script agora ignora as repetições (`66b1dae`).
- O dono decidiu **ignorar o RCS**. Ele ficou desligado por padrão, com `rcs_enabled = true` para religar (`a213ff0`).

---

## 7. Foguete pesado demais e empuxo desigual

Em sequência de voos:

- **Massa 815** (muitos tanques, ~360 baldes de lava). TWR real ~0,31, e o foguete não saiu do chão.
  - O TWR mostrado na tela parecia melhor porque o script antigo contava cada motor 2 vezes (modems duplicados).
  - Orientação: tirar tanques até ~350 de massa, de forma simétrica.
- **Massa 360, TWR 1,26:** decolou mas tombou em ~5 s. Dois motivos:
  - **não tinha Vector Thruster** (nada controla a direção);
  - **as bombas davam vazão desigual** (um motor com 500 N, outro com 1000 N).
  - Commit `aaecbaf`: falta de Vector Thruster virou **erro** no preflight, e surgiu o aviso **EMPUXO DESIGUAL**.
- **Log por voo com data e hora** (pedido do dono, commit `30bdfe8`):
  - arquivos `/logs/AAAA-MM-DD_HH-MM-SS_voo.txt` + `_telemetria.csv`;
  - novo comando `logs lista`;
  - limpeza automática dos mais antigos.
- **"Tem o Vector mas não funciona."** Criei o **`diagnostico.lua`** (`33ecb25`): lista os lados do computador, os periféricos com o tipo de motor e o que está na config sem estar conectado.
  - Possíveis causas: modem não ativado (cinza), cabo fora da rede, ou Vector Thruster do AeroIE em vez do Cosmonautics.
- **Vector apareceu, mas o TWR era 1,05** (um motor desconectado). O foguete flutuou, escorregou e capotou. O controle deixava **9° de erro parado**. Commit `110c89f`:
  - **termo integral** no controle (voo e Sputnik);
  - TWR abaixo de 1,15 virou **erro**.
- **Melhor voo até então:** erro menor que 1° e subida reta, mas **a lava acabou a Y=797**, subindo a 24 m/s. Com TWR ~1,3 quase todo o empuxo só segura o peso.
  - Conclusão: precisa de TWR ~2 e mais lava. Isso levou aos boosters.

---

## 8. Boosters de combustível sólido

- O dono perguntou se usava **docking** para soltar os boosters. A resposta foi usar o **Stage Separator** do próprio Cosmonautics.
- Commit `1789b68`:
  - os boosters acendem junto com os motores de lava;
  - quando **todos** acabam, o script pulsa `booster_separator` e segue com os líquidos.
- **Regras passadas pela foto do primeiro booster:**
  - boosters em pares opostos;
  - carvão encostado atrás do bico;
  - o separador precisa ser a **única** ligação com o núcleo (o cabo também prende);
  - cuidado com o lado que o Separator Charge destrói.

---

## 9. Apontar antes de acender + Magnetic Stabilizer

- **Pedido do dono:** "você tem que ajustar o ângulo e, quando o ângulo estiver correto, você ativa".
- Commit `87be57e`, no espaço e no pouso:
  - desalinhado: **só o Vector Thruster** empurra (35%) para girar;
  - erro abaixo de 5° e rotação baixa: acendem todos;
  - erro acima de 15° durante a queima: volta a só girar.
- **Erro meu:** recomendei o **Gyrodyne**, lendo o código da versão 1.4, que ainda não saiu. O dono avisou que o bloco não existe.
  - Baixei a **versão exata dele (26.08.307)**. Ela tem o **Magnetic Stabilizer**: ligado por redstone, **freia a rotação**, mas não aponta.
- Commit `3c95e09`:
  - o stabilizer liga quando a nave já está alinhada e durante reentrada/queimas, e desliga enquanto ela gira para apontar;
  - o `setup` pergunta o lado.
- O dono colocou o stabilizer **embaixo do computador**, então o lado é **`bottom`**. O separador dos boosters precisa usar outro lado ou um relay.

---

## 10. Voo com 13 motores: as bombas são o gargalo

- TWR 2,84 no papel, mas tombou aos 7 s.
  - Nos primeiros 2 s queimou a lava interna dos motores (~10.000 N).
  - Depois caiu para **~5.300 N**: as bombas entregam ~140 mB/t e 13 motores precisam de 520.
  - A distribuição desigual girou o foguete.
- Commit `662f0d8`: **equilíbrio de empuxo** na subida.
  - Se a diferença entre motores passar de 20%, todos ficam limitados à média.
  - O limite vai subindo quando sobra vazão.
  - Isso evita o tombo, mas não cria empuxo.
- **Orientação:** mais bombas em paralelo, mais RPM, canos curtos e iguais, e usar boosters.

---

## 11. Esquemas visuais

- **Sistema de boosters:** vista de lado e de cima, anel de separadores, cabo cortado pelo Charge, fases e checklist.
  - https://claude.ai/artifact/UNyTu7Ke1i94yCn8x34LaC
- **Foguete de dois estágios com 4 boosters** (pedido "bem detalhado, quais blocos preciso"):
  - https://claude.ai/artifact/Vx3yE4HX5g53JYtAn6fP4e
  - Lista de blocos por estágio:
    - Estágio 2: assento, computador, Sputnik, stabilizer, 2 Rocket + 1 Vector, Relay A.
    - Estágio 1: 4 Rocket + 1 Vector, ~18 tanques, 3 bombas, Relay B.
    - Boosters: 4, com 16 blocos de carvão.
    - Separação: ~72 separadores na saia entre estágios, ~32 no anel dos boosters, 5 Charges.
  - Também tem a rede de cabos, os lados do computador, as respostas do `setup` e o checklist.

---

## 12. Montagem em andamento (dúvidas respondidas)

- **Tanque de 144 baldes (3×3×2)**
  - Dura ~36 s com 5 motores a 100%.
  - Um tanque do Create tem base de no máximo 3×3. Para ter mais lava, só aumentando a altura: +72 baldes e +18 s por camada, mas também mais peso.
  - Sugestão: estágio 1 com 3×3×4 (288 baldes) e estágio 2 com 2×2×3 (96).
  - Para encher, use uma Hose Pulley num lago de lava grande (≥10.000 fontes = infinito).
- **Ativação do booster** (conferido no código):
  - acende por **redstone ou pelo computador** (`setActive`) e **não desliga mais**;
  - só aceita **Bloco de Carvão**, que é gasto um por vez, 10 s cada;
  - camadas de até 3×3, até 64 de profundidade;
  - potência ajustável até 1000 N, igual em todos.
- **Separação do booster:**
  - anel de Stage Separators ligados entre si (pinos; a Wrench liga e desliga);
  - Relay B encostado em um deles;
  - o anel não pode encostar na saia entre estágios;
  - teste com alavanca antes do voo.
- **"O booster vai ter um computador?"** Não. Só um **Wired Modem** encostado nele, ligado por cabo à mesma rede. O único computador fica no estágio 2.
- **Como o booster se comunica:**
  - o cabo desce do computador pelo foguete e se divide dentro do núcleo;
  - atravessa o anel;
  - no ponto onde atravessa, um **Separator Charge colocado clicando no cabo** destrói o cabo na separação;
  - no booster, o cabo termina num modem clicado (vermelho).
  - Confira com `diagnostico`, que deve mostrar Booster: 4.
- **Revisão da foto do teste:**
  - o cabo passava **por fora** da fileira de separadores e seguraria o booster;
  - solução: trocar o separador acima do cabo por um Charge clicado no cabo;
  - também confirmar que o corpo preto é mesmo bloco de carvão.

---

## 13. Handoff e documentação

- **`HANDOFF.md`:** estado atual, arquitetura, fatos do mod e próximos passos.
- **`ferramentas/`:** o simulador fora do jogo (`sim.py` órbita, `sim2.py` comandos, `sim3.py` boosters). Precisa de Python + `lupa`.
- **Este arquivo (`HISTORICO.md`).**

---

## Commits, em ordem

| Commit | O que mudou |
|---|---|
| `ff22fb1` | Piloto automático inicial (pouso novo, Sputnik só na subida) |
| `3b6ea0f` | Atualizador apontando para `foguete-cc-teste` |
| `444c75a` | Circularização com os dados orbitais da Sputnik |
| `23026c2` | Suporte a RCS |
| `66b1dae` | Ignora periféricos repetidos (2 modems) |
| `a213ff0` | RCS desligado por padrão |
| `aaecbaf` | Erro sem Vector Thruster + aviso de empuxo desigual |
| `30bdfe8` | Um log por voo com data e hora |
| `33ecb25` | Programa `diagnostico` |
| `110c89f` | Integral no controle + TWR baixo vira erro |
| `1789b68` | Boosters em paralelo com separação automática |
| `87be57e` | Aponta antes de acender (espaço e pouso) |
| `3c95e09` | Magnetic Stabilizer |
| `662f0d8` | Equilíbrio de empuxo |
| `83e9fea` | Handoff + simulador |

## Lições aprendidas

- **Sempre conferir a versão exata do mod** (26.08.307) antes de recomendar um bloco.
- **No espaço profundo** a nave fica parada e a órbita é simulada. Use `getDeepSpaceData`, não a velocidade local.
- **O gimbal só gira a nave com empuxo.** Para segurar o ângulo com o motor apagado, use o Magnetic Stabilizer.
- **O empuxo real depende da vazão das bombas** (40 mB/t por motor), não do número de motores.
- **Qualquer bloco ligando duas partes impede a separação**, inclusive cabo de rede. Use o Separator Charge para cortar o cabo.
- **Redstone nunca deve atravessar de um estágio para outro.** Use relays pela rede de cabos.
