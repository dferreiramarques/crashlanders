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
