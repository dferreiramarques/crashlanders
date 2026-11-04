// CRASHLANDERS cross-play relay
//
// Browsers play online through Supabase Realtime (wss://). LÖVE 11 has no TLS, so
// consoles can't join those rooms directly. This relay joins the Supabase room on
// the console's behalf and forwards messages over a plain TCP socket:
//
//   console  ──TCP, one JSON per line──▶  relay  ──Supabase Realtime──▶  browser
//
// Messages are the same ones the web build uses ("in" = buttons, "snap" = state).
// The relay also beacons "CRASHRELAY|<ip>" on UDP 47231 so consoles find it on the LAN.
//
//   cd relay && npm install && npm start
//
import net from 'node:net';
import dgram from 'node:dgram';
import os from 'node:os';
import { createClient } from '@supabase/supabase-js';

const SB_URL = process.env.SB_URL || 'https://rdwmqhgcjkfniahtofgt.supabase.co';
const SB_KEY = process.env.SB_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJkd21xaGdjamtmbmlhaHRvZmd0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5MDE5MDgsImV4cCI6MjA4OTQ3NzkwOH0.rfCK4cUS7ODEGt4UIE5cbqcK5spqN9yrq36sNC5NlV4';
const TCP_PORT = Number(process.env.PORT || 47240);
const DISC_PORT = 47231;
const ROOM_RE = /^[A-Z0-9]{4}$/;

const sb = createClient(SB_URL, SB_KEY, { realtime: { params: { eventsPerSecond: 80 } } });
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

function lanIP() {
  for (const list of Object.values(os.networkInterfaces()))
    for (const a of list || []) if (a.family === 'IPv4' && !a.internal) return a.address;
  return '127.0.0.1';
}

net.createServer(sock => {
  sock.setNoDelay(true);
  const who = `${sock.remoteAddress}:${sock.remotePort}`;
  let buf = '', ch = null, role = null, room = null, peer = false;
  const out = o => { if (!sock.destroyed) sock.write(JSON.stringify(o) + '\n'); };

  function join(m) {
    if (ch) return;
    if (!ROOM_RE.test(m.room || '') || !['host', 'guest'].includes(m.role)) { out({ t: 'status', st: 'BAD_JOIN' }); return; }
    role = m.role; room = m.room;
    const key = `${role}-${Math.random().toString(36).slice(2, 8)}`;
    ch = sb.channel(`crashlanders-${room}`, { config: { broadcast: { self: false, ack: false }, presence: { key } } });
    ch.on('broadcast', { event: 'in' }, ({ payload }) => { if (role === 'host') out({ t: 'in', k: payload.k || {} }); })
      .on('broadcast', { event: 'snap' }, ({ payload }) => { if (role === 'guest') out({ t: 'snap', s: payload }); })
      .on('presence', { event: 'sync' }, () => {
        const other = Object.keys(ch.presenceState()).some(k => !k.startsWith(role + '-'));
        if (other !== peer) { peer = other; out({ t: 'peer', on: other }); log(`room ${room}: peer ${other ? 'joined' : 'left'} (${role} ${who})`); }
      })
      .subscribe(async st => {
        out({ t: 'status', st });
        if (st === 'SUBSCRIBED') await ch.track({ at: Date.now(), via: 'relay' });
      });
    log(`${who} joined room ${room} as ${role}`);
  }

  sock.on('data', d => {
    buf += d;
    if (buf.length > 1e6) { sock.destroy(); return; }          // runaway client
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i); buf = buf.slice(i + 1);
      if (!line) continue;
      let m; try { m = JSON.parse(line); } catch { continue; }
      if (m.t === 'join') join(m);
      else if (ch && m.t === 'in' && role === 'guest') ch.send({ type: 'broadcast', event: 'in', payload: { k: m.k || {} } });
      else if (ch && m.t === 'snap' && role === 'host') ch.send({ type: 'broadcast', event: 'snap', payload: m.s });
    }
  });
  const close = () => {
    if (ch) { ch.untrack().catch(() => {}); sb.removeChannel(ch); ch = null; log(`${who} left room ${room}`); }
  };
  sock.on('close', close);
  sock.on('error', close);
}).listen(TCP_PORT, () => log(`relay listening on tcp ${TCP_PORT} (LAN ${lanIP()})`));

// LAN discovery beacon
const udp = dgram.createSocket('udp4');
udp.bind(() => {
  udp.setBroadcast(true);
  setInterval(() => {
    const msg = Buffer.from(`CRASHRELAY|${lanIP()}`);
    udp.send(msg, DISC_PORT, '255.255.255.255');
    udp.send(msg, DISC_PORT, '127.0.0.1');
  }, 1000);
});
