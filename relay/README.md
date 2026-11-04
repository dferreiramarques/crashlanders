# CRASHLANDERS — relay de cross-play

Liga as consolas (port LÖVE) às salas online do browser.

O browser joga online pelo Supabase Realtime (`wss://`). O LÖVE 11 não tem TLS, por isso a
consola não entra diretamente nessas salas. O relay entra na sala do Supabase em nome da consola
e passa as mensagens por TCP simples (uma linha JSON por mensagem):

```
consola ──TCP 47240──▶ relay ──Supabase Realtime──▶ browser
```

As mensagens são as mesmas da versão web (`in` = botões, `snap` = estado do jogo), por isso
browser e consola partilham as mesmas salas de 4 letras, em qualquer combinação de anfitrião/convidado.

## Correr

Precisa de Node 22+, no mesmo Wi-Fi que a consola:

```
cd relay
npm install
npm start
```

O relay anuncia-se na rede (UDP 47231); a consola mostra-o em
**LAN · CO-OP → PROCURAR JOGO** como `ONLINE (relay …)`. Lá podes **CRIAR SALA** (mostra o
código para o amigo escrever no browser) ou **ENTRAR COM CÓDIGO** (a sala criada no browser).

Variáveis opcionais: `SB_URL`, `SB_KEY` (por omissão, o projeto do jogo) e `PORT` (47240).

## Limites

- A consola tem de estar na mesma rede que o PC do relay (o browser pode estar em qualquer lado).
- Para jogar a consola fora de casa, aloja o relay num serviço que aceite TCP simples
  (ex.: Fly.io) e aponta a consola para esse endereço.
- Usa a quota de mensagens do Realtime do Supabase (~30 mensagens/s durante um jogo).
