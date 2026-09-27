# foguete-cc-teste

Piloto automático de foguete para Minecraft com **Create Cosmonautics (Rocketnautics)**, **Sable** e **CC: Tweaked**.
Ele cuida da subida até a órbita, da circularização, do deorbit e do pouso controlado, sempre com logs.

## Arquivos

| Arquivo | O que faz |
|---|---|
| `voo.lua` | piloto automático (subida, órbita, descida, pouso) |
| `setup.lua` | detecta os motores e gera o `config.lua` |
| `startup.lua` | roda o `voo` ao ligar (e retoma o voo depois de trocar de dimensão) |
| `parar.lua` | emergência: desliga todos os motores líquidos |
| `logs.lua` / `log.lua` | mostra e grava os logs (um arquivo por voo em `/logs`) |
| `atualizar.lua` | baixa a versão mais nova deste repositório |
| `diagnostico.lua` | lista tudo que o computador enxerga (motores, modems, config) |
| `sputnik_guiagem.lua` | script do nó "Lua Script" da Sputnik (gravity turn na subida) |

`config.lua`, `estado.txt`, `rcs.cal` e a pasta `logs/` ficam só no computador do jogo. Eles não vão para o repositório.

## Instalar no computador do foguete

```
wget https://raw.githubusercontent.com/marcelin1555/foguete-cc-teste/main/atualizar.lua
atualizar
setup
```

## Atualizar

```
atualizar            -- todos os scripts
atualizar voo.lua    -- só um arquivo
```

## Comandos de voo

```
voo                -- checagem e espera o botão de lançamento
voo teste          -- checagem + teste de gimbal, sem acender nada
voo descer         -- deorbit (se estiver no espaço) e pouso
voo descer 64      -- o mesmo, sabendo que o chão fica em Y=64
voo rcs            -- calibra os RCS e testa (nave solta no ar ou no espaco)
voo reset          -- apaga o estado (novo voo)
logs               -- últimas linhas do voo mais recente
logs lista         -- todos os logs, do mais novo (1) ao mais velho
logs 3 erros       -- avisos e erros do log 3 da lista
logs limpar        -- apaga todos os logs
```

### Controle de direção na subida

A Sputnik (`sputnik_guiagem.lua`) aponta o foguete com um controle PID: proporcional (`KP`),
amortecimento (`KD`) e **integral (`KI`)**. O integral tira o erro que ficaria parado quando o
centro de massa está fora do eixo ou um motor empurra menos que os outros.
Com `sputnik_guidance = false` quem controla é o computador, com os mesmos termos (`kp`, `kd`, `ki` no `config.lua`).

### Logs

Cada voo grava num arquivo próprio, com data e hora no nome:

```
/logs/2026-09-27_19-32-50_voo.txt              eventos
/logs/2026-09-27_19-32-50_voo_telemetria.csv   telemetria (y, velocidade, empuxo, erro...)
```

- Se o computador reiniciar no meio do voo (troca de dimensão), ele continua no **mesmo arquivo**.
- `voo teste` e `voo rcs` gravam arquivos `..._teste.txt` e `..._rcs.txt`.
- Os mais antigos são apagados sozinhos quando a pasta passa de 40 arquivos ou 500 KB.
- Um `voo reset` faz o próximo voo começar um arquivo novo.

### Como a órbita funciona

No espaço profundo a nave fica parada no próprio mundo e a Sputnik simula a órbita.
Por isso o piloto usa só os dados da Sputnik (`semiMajorAxis`, `eccentricity`, `velocity`, `distanceToPlanet`):

1. **COAST**: motores desligados até o apoastro (a distância para de subir).
2. **CIRC**: queima na direção do movimento orbital até o periastro passar de `orbit_peri_alt`.
   - Se o semi-eixo maior **cai** durante a queima, inverte a direção.
   - Se a órbita **não muda**, gira 90° e tenta de novo (até 4 vezes).
3. **ORBIT**: motores desligados e voo encerrado.

| Chave | Padrão | |
|---|---|---|
| `orbit_peri_alt` | 23000 | periastro mínimo (a nave volta para o overworld abaixo de ~21000) |
| `circ_slow_m` | 50000 | começa a reduzir o empuxo quando falta menos que isso para o alvo |

### RCS

**Desligado por padrão.** Para usar, coloque `rcs_enabled = true` no `config.lua`.
Desligado, o piloto gira a nave só com o gimbal do Vector Thruster, como antes.

O RCS gira a nave **sem gastar lava**: no espaço e na queda do pouso, é ele que aponta o foguete,
e o motor principal só liga quando a nave já está alinhada.

- **O script da Sputnik precisa ser o novo.** O computador só consegue ligar e desligar o RCS;
  o acelerador dele começa em 0 e só a Sputnik consegue colocar em 100%.
- **Calibração automática**: o CC não sabe para onde cada RCS aponta. Na primeira vez no espaço
  (ou com `voo rcs`), ele liga um de cada vez por 1 s, mede o giro e salva em `rcs.cal`.
  Se você mudar os RCS de lugar, apague o `rcs.cal` ou rode `voo rcs`.
- **Empuxo do RCS pelo Y da nave**: 12 N abaixo de Y=2000, sobe até 105 N em Y=5000.
  No espaço profundo a nave fica perto de Y=1100, então lá o RCS é fraco (12 N).
- **Onde colocar 4 RCS**: longe do centro de massa (perto do nariz ou da cauda), apontando para os 4 lados.
  Se eles não conseguirem girar a nave para algum lado, o log avisa e o piloto volta a girar com o motor principal.

| Chave | Padrão | |
|---|---|---|
| `rcs_kp` / `rcs_kd` | 0.4 / 1.2 | força da correção / amortecimento |
| `rcs_timeout` | 30 | segundos sem melhorar o erro antes de desistir do RCS |

### Pouso sem saber o Y do chão

O foguete freia até `land_ceiling_y` (padrão 400) e depois desce a `land_speed` (padrão 3 m/s) até encostar.
O toque é detectado sozinho.

### Opções de pouso no `config.lua` (todas opcionais)

| Chave | Padrão | |
|---|---|---|
| `ground_y` | – | Y do chão |
| `land_offset` | 3 | altura do centro de massa com a nave no chão |
| `land_ceiling_y` | 400 | teto da descida lenta quando o chão é desconhecido |
| `land_speed` | 3 | velocidade final de descida (m/s) |
| `land_max_speed` | 120 | velocidade máxima de queda (m/s) |
| `land_max_tilt` / `land_max_tilt_high` | 25 / 60 | inclinação máxima perto e longe do chão |
| `land_h_accel` | 8 | aceleração máxima para frear a deriva lateral |
| `land_orient_n` | 100 | empuxo mínimo por motor só para girar a nave |
| `land_cc_gimbal` | true | o computador controla o gimbal no pouso |
