// Edge Function "notifiche": invia le notifiche push dell'app Il mio Uliveto.
//  - chiamata ogni minuto da pg_cron (header x-cron-secret) per svuotare la coda
//  - chiamata ogni mattina da pg_cron con {"modo":"meteo"} per gli avvisi meteo
//  - chiamata dall'app con il token dell'utente per la notifica di prova
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const APP = "https://laurentimrc.github.io/Oil-management-system/";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

type Config = { vapid_public: string; vapid_private: string; subject: string; cron_secret: string };
async function config(): Promise<Config> {
  const { data, error } = await sb.from("config_push").select("*").eq("id", 1).single();
  if (error) throw error;
  if (!data.vapid_public || !data.vapid_private) {
    const k = webpush.generateVAPIDKeys();          // generate una sola volta, restano nel database
    const up = await sb.from("config_push").update({ vapid_public: k.publicKey, vapid_private: k.privateKey }).eq("id", 1);
    if (up.error) throw up.error;
    data.vapid_public = k.publicKey; data.vapid_private = k.privateKey;
  }
  webpush.setVapidDetails(data.subject, data.vapid_public, data.vapid_private);
  return data as Config;
}

async function inviaA(userId: string, payload: Record<string, unknown>) {
  const { data: subs } = await sb.from("push_iscrizioni").select("*").eq("user_id", userId);
  let ok = 0; const err: string[] = [];
  for (const s of subs ?? []) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(payload), { TTL: 60 * 60 * 12 });
      ok++;
      await sb.from("push_iscrizioni").update({ ultimo_invio: new Date().toISOString() }).eq("id", s.id);
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) await sb.from("push_iscrizioni").delete().eq("id", s.id);   // dispositivo non più valido
      err.push(String(code ?? (e as Error).message));
    }
  }
  return { dispositivi: (subs ?? []).length, ok, err };
}

async function processaCoda() {
  const { data: candidati } = await sb.from("coda_notifiche").select("id").is("inviata_at", null).order("id").limit(100);
  if (!candidati?.length) return { righe: 0, inviate: 0 };
  // "prenota" le righe, così due esecuzioni sovrapposte non inviano doppioni
  const { data: righe } = await sb.from("coda_notifiche").update({ inviata_at: new Date().toISOString(), esito: "in invio" })
    .in("id", candidati.map((c) => c.id)).is("inviata_at", null).select("*");
  if (!righe?.length) return { righe: 0, inviate: 0 };
  const utenti = [...new Set(righe.map((r) => r.destinatario))];
  const { data: prefs } = await sb.from("preferenze_notifiche").select("*").in("user_id", utenti);
  const P = Object.fromEntries((prefs ?? []).map((p) => [p.user_id, p]));
  let inviate = 0;
  for (const r of righe) {
    let esito: string;
    if (r.categoria !== "prova" && P[r.destinatario]?.[r.categoria] === false) esito = "disattivata dall'utente";
    else {
      const x = await inviaA(r.destinatario, { titolo: r.titolo, testo: r.testo, url: APP + (r.url ?? ""), tag: `${r.categoria}-${r.id}` });
      esito = x.dispositivi ? `ok ${x.ok}/${x.dispositivi}${x.err.length ? " errori " + x.err.join(",") : ""}` : "nessun dispositivo";
      inviate += x.ok;
    }
    await sb.from("coda_notifiche").update({ esito }).eq("id", r.id);
  }
  return { righe: righe.length, inviate };
}

const fmt = (n: number) => String(Math.round(n * 10) / 10).replace(".", ",");
const quando = (i: number) => (i === 0 ? "Oggi" : i === 1 ? "Domani" : "Dopodomani");
const addGiorni = (d: string, n: number) => { const x = new Date(d + "T12:00:00Z"); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };

async function meteo() {
  const { data: luoghi, error } = await sb.rpc("luoghi_meteo");
  if (error) throw error;
  const oggi = new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Rome" });
  const { data: tratt } = await sb.from("promemoria").select("user_id,titolo,data")
    .eq("fatto", false).eq("tipo", "trattamento").gte("data", oggi).lte("data", addGiorni(oggi, 3)).order("data");
  const accoda = (owner: string, cat: string, titolo: string, testo: string, chiave: string) =>
    sb.rpc("accoda", { p_owner: owner, p_ruoli: ["manager", "agricoltore"], p_categoria: cat, p_titolo: titolo, p_testo: testo, p_url: "#tab=home", p_chiave: chiave, p_escludi: null });
  let avvisi = 0;
  for (const l of luoghi ?? []) {
    const r = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${l.lat.toFixed(4)}&longitude=${l.lng.toFixed(4)}`
      + "&daily=temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max&forecast_days=3&timezone=Europe%2FRome");
    if (!r.ok) continue;
    const d = (await r.json()).daily;
    const g = d.time.findIndex((_: string, i: number) => d.temperature_2m_min[i] <= 0);
    if (g >= 0) {
      await accoda(l.owner_id, "meteo", "❄️ Gelo in arrivo",
        `${quando(g)} minima ${fmt(d.temperature_2m_min[g])}°C a ${l.luogo}. Proteggi le piante giovani e rimanda le potature.`, `gelo:${l.owner_id}:${d.time[g]}`);
      avvisi++;
    }
    const p = d.time.findIndex((_: string, i: number) => d.precipitation_sum[i] >= 20);
    if (p >= 0) {
      await accoda(l.owner_id, "meteo", "🌧️ Pioggia abbondante", `${quando(p)} circa ${Math.round(d.precipitation_sum[p])} mm a ${l.luogo}.`, `pioggia:${l.owner_id}:${d.time[p]}`);
      avvisi++;
    }
    const buono = (i: number) => d.precipitation_sum[i] < 0.5 && (d.precipitation_probability_max[i] ?? 0) < 30 && d.wind_speed_10m_max[i] < 15
      && (i + 1 >= d.time.length || d.precipitation_sum[i + 1] < 2);
    const t = (tratt ?? []).find((x) => x.user_id === l.owner_id);
    if (t && buono(1)) {
      await accoda(l.owner_id, "meteo", "🧪 Domani è un buon giorno per trattare", `${t.titolo}: niente pioggia e vento debole a ${l.luogo}.`, `tratt:${l.owner_id}:${d.time[1]}`);
      avvisi++;
    }
  }
  return { luoghi: (luoghi ?? []).length, avvisi };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const cfg = await config();
    const segreto = req.headers.get("x-cron-secret");
    if (segreto !== null) {
      if (segreto !== cfg.cron_secret) return json({ error: "non autorizzato" }, 401);
      if (body.modo === "salute") return json({ ok: true, chiavi: Boolean(cfg.vapid_public) });
      if (body.modo === "meteo") return json(await meteo());
      return json(await processaCoda());
    }
    const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await sb.auth.getUser(jwt);
    if (!user) return json({ error: "non autorizzato" }, 401);
    if (body.azione === "prova") {
      const x = await inviaA(user.id, { titolo: "🔔 Notifiche attive", testo: "Da ora riceverai qui gli avvisi del tuo uliveto.", url: APP, tag: "prova" });
      return json(x);
    }
    return json({ error: "azione sconosciuta" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
