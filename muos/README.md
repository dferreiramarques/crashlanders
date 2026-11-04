# CRASHLANDERS — port LÖVE para muOS (RG35XX H)

Port do jogo web (`index.html`) para **LÖVE 11.5**, empacotado para **PortMaster**
(funciona no muOS e noutros sistemas com PortMaster; arquiteturas aarch64 e x86_64).

## Instalar na RG35XX H (muOS)

1. Gera o pacote: `python muos/build_zip.py` → `muos/dist/crashlanders.zip`
2. Copia `crashlanders.zip` para a pasta **autoinstall** do PortMaster no cartão
   (no muOS: `MUOS/PortMaster/autoinstall/`).
3. Abre o **PortMaster** na consola: instala o zip sozinho.
4. O jogo aparece em **Ports** como *Crashlanders*.

O runtime LÖVE 11.5 é partilhado e vem do próprio PortMaster (descarrega-o na
primeira vez, se ainda não estiver instalado).

## Controlos

| Ação | Comando | Teclado P1 | Teclado P2 |
|---|---|---|---|
| Mover / mirar | D-pad ou stick | setas | W A S D |
| Saltar | A | AltGr / Shift dir. | 1 / Espaço |
| Disparar (segurar fixa a direção) | B ou R2 | Ctrl dir. | Q |
| Descer plataforma | Baixo + A | ↓ + saltar | S + saltar |
| Loja: arma / cadência / salto×2 / paraquedas | X / Y / L1 / R1 | Z X C V | G H J K |
| Confirmar / saltar intro | Start | Enter | Enter |
| Menu | Select | Esc | Esc |

O 2.º jogador usa um segundo comando (USB-C).

## Co-op em LAN

1. As duas consolas (ou consola + PC) na **mesma rede Wi-Fi**.
2. Num aparelho: **LAN · CO-OP → CRIAR JOGO** (fica à espera e mostra o IP).
3. No outro: **LAN · CO-OP → PROCURAR JOGO**, escolhe o anfitrião na lista e carrega em **A**.

O anfitrião corre o jogo; o convidado envia os botões e recebe o estado ~30×/s (ENet, portas
UDP 47231 para descoberta e 47232 para o jogo). Um jogo LAN não mexe no save local.

Teste no PC com duas janelas: `love gamedata --lanhost` e `love gamedata --languest`.

## Cross-play com o browser

Com o relay a correr num PC da mesma rede (`relay/README.md`), o relay aparece em
**PROCURAR JOGO** como `ONLINE (relay …)`. Daí podes criar uma sala (o código aparece no ecrã
para quem está no browser escolher **ONLINE · CO-OP → ENTRAR COM CÓDIGO**) ou entrar numa sala
criada no browser (o código escolhe-se letra a letra com o D-pad).

## Diferenças para a versão web

- Ecrã 800×450 desenhado com barras pretas no 640×480 da consola.
- Highscores **locais** com iniciais estilo arcade (o LÖVE 11 não tem HTTPS para o Supabase).
- Som sintetizado em código ao arrancar (sem ficheiros de áudio).
- Fontes: usa a fonte embutida do LÖVE; para o aspeto exato, copia os TTF indicados em
  `crashlanders/gamedata/assets/fonts/README.txt`.
- Sem consola de debug / god mode.

## Testar no PC

Com o LÖVE 11.5 instalado, a partir de `muos/crashlanders/`:

```
love gamedata
love gamedata --autotest   # percorre todos os ecrãs, guarda capturas e sai
```

As capturas e os saves ficam na pasta de dados do LÖVE (`%APPDATA%/LOVE/crashlanders` no Windows).
