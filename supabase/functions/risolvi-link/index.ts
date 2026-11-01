// Edge Function "risolvi-link": espande un link breve di Google Maps (maps.app.goo.gl)
// nell'indirizzo completo, da cui l'app legge le coordinate. Solo per utenti collegati
// (verify_jwt) e solo verso host di Google Maps: non è un proxy generico.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const BREVI = ["maps.app.goo.gl", "goo.gl"];
const GOOGLE = /(^|\.)google\.[a-z.]+$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { url } = await req.json();
    let u = new URL(String(url).trim());
    if (u.protocol !== "https:" || !BREVI.includes(u.hostname)) return json({ error: "Non è un link breve di Google Maps" }, 400);
    for (let i = 0; i < 6; i++) {
      if (GOOGLE.test(u.hostname) && u.hostname.startsWith("consent.")) {      // pagina dei cookie: l'indirizzo vero è in "continue"
        const c = u.searchParams.get("continue"); if (!c) break; u = new URL(c); continue;
      }
      if (GOOGLE.test(u.hostname)) return json({ url: u.toString() });
      if (!BREVI.includes(u.hostname)) break;
      const r = await fetch(u, { redirect: "manual" });
      const loc = r.headers.get("location");
      await r.body?.cancel();
      if (!loc) break;
      u = new URL(loc, u);
    }
    return json({ error: "Non riesco a leggere questo link" }, 422);
  } catch (_e) {
    return json({ error: "Link non valido" }, 400);
  }
});
