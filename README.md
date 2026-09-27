# foguete-cc

Piloto automático de foguete para Minecraft com **Create Cosmonautics (Rocketnautics)**, **Sable** e **CC: Tweaked**.
Ele cuida da subida até a órbita, da circularização, do deorbit e do pouso controlado, sempre com logs.

## Arquivos

| Arquivo | O que faz |
|---|---|
| `voo.lua` | piloto automático (subida, órbita, descida, pouso) |
| `setup.lua` | detecta os motores e gera o `config.lua` |
| `startup.lua` | roda o `voo` ao ligar (e retoma o voo depois de trocar de dimensão) |
| `parar.lua` | emergência: desliga todos os motores líquidos |
| `logs.lua` / `log.lua` | mostra e grava o `log.txt` |
| `atualizar.lua` | baixa a versão mais nova deste repositório |
| `sputnik_guiagem.lua` | script do nó "Lua Script" da Sputnik (gravity turn na subida) |

`config.lua`, `estado.txt`, `log.txt` e `voo.log` ficam só no computador do jogo. Eles não vão para o repositório.

## Instalar no computador do foguete

```
wget https://raw.githubusercontent.com/marcelin1555/foguete-cc/main/atualizar.lua
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
voo reset          -- apaga o estado (novo voo)
logs erros         -- só avisos e erros
```

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
