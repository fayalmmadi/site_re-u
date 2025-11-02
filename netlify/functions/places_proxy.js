// /netlify/functions/places_proxy.js
const fetch = (...args) => import('node-fetch').then(({ default: fetch }) => fetch(...args));

const GOOGLE_KEY = process.env.GOOGLE_API_KEY;

const ALLOW = {
  autocomplete: "https://maps.googleapis.com/maps/api/place/autocomplete/json",
  details:      "https://maps.googleapis.com/maps/api/place/details/json",
  geocode:      "https://maps.googleapis.com/maps/api/geocode/json",
  directions:   "https://maps.googleapis.com/maps/api/directions/json", // 👈 ajouté
};

exports.handler = async (event) => {
  // Préflight CORS
  if (event.httpMethod === 'OPTIONS') {
    return send(200, { ok: true });
  }

  try {
    if (!GOOGLE_KEY) return send(500, { error: 'Missing GOOGLE_API_KEY' });

    const path = (event.queryStringParameters?.endpoint || "").toLowerCase();
    const base = ALLOW[path];
    if (!base) return send(400, { error: "endpoint must be autocomplete|details|geocode|directions" });

    // On reconstruit les paramètres proprement
    const lqs = new URLSearchParams(event.queryStringParameters || {});
    const qs  = new URLSearchParams(lqs);

    // On ne relaie pas "endpoint"
    qs.delete("endpoint");

    // Force la clé et la langue (si absentes)
    qs.set("key", GOOGLE_KEY);
    if (!qs.has("language")) qs.set("language", "fr");

    const url = `${base}?${qs.toString()}`;
    const response = await fetch(url);
    const data = await response.json();

    return send(200, data);
  } catch (e) {
    return send(500, { error: String(e) });
  }
};

function send(status, body) {
  return {
    statusCode: status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
    body: JSON.stringify(body),
  };
}
