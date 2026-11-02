// Edge Function "account": operazioni che richiedono i permessi del server.
//  - {"azione":"chiudi","conferma":"ELIMINA"} con il token dell'utente: chiude il suo account.
//    Cancella le foto delle sue vetrine e poi l'utente: tutti i suoi dati se ne vanno a cascata.
//  - {"azione":"pulizia"} da pg_cron (header x-cron-secret): cancella i clienti importati
//    che non hanno accettato l'invito entro 12 mesi.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

async function chiudi(req: Request, body: { conferma?: string }) {
  if (body.conferma !== "ELIMINA") return json({ error: "Scrivi ELIMINA per confermare" }, 400);
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: u, error } = await sb.auth.getUser(jwt);
  if (error || !u?.user) return json({ error: "Accesso richiesto" }, 401);
  const uid = u.user.id;
  // foto delle vetrine dei negozi di cui è titolare
  const { data: negozi } = await sb.from("negozi").select("id").eq("owner_id", uid);
  for (const n of negozi ?? []) {
    const { data: files } = await sb.storage.from("vetrine").list(n.id, { limit: 1000 });
    if (files?.length) await sb.storage.from("vetrine").remove(files.map((f) => `${n.id}/${f.name}`));
  }
  const del = await sb.auth.admin.deleteUser(uid);
  if (del.error) return json({ error: del.error.message }, 500);
  return json({ ok: true });
}

async function pulizia(req: Request) {
  const { data: cfg } = await sb.from("config_push").select("cron_secret").eq("id", 1).single();
  if (!cfg?.cron_secret || req.headers.get("x-cron-secret") !== cfg.cron_secret) return json({ error: "Non autorizzato" }, 401);
  const limite = new Date(Date.now() - 365 * 864e5).toISOString();
  const { data, error } = await sb.from("clienti").delete().is("user_id", null).lt("importato_at", limite).select("id");
  if (error) return json({ error: error.message }, 500);
  return json({ cancellati: data?.length ?? 0 });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Metodo non consentito" }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    if (body.azione === "chiudi") return await chiudi(req, body);
    if (body.azione === "pulizia") return await pulizia(req);
    return json({ error: "Azione sconosciuta" }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
