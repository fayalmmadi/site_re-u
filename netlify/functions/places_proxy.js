const fetch = (...args) => import('node-fetch').then(({default: fetch}) => fetch(...args));

const GOOGLE_KEY = process.env.GOOGLE_API_KEY;

const ALLOW = {
  autocomplete: "https://maps.googleapis.com/maps/api/place/autocomplete/json",
  details:      "https://maps.googleapis.com/maps/api/place/details/json",
  geocode:      "https://maps.googleapis.com/maps/api/geocode/json",
};

exports.handler = async (event) => {
  try {
    const path = (event.queryStringParameters?.endpoint || "").toLowerCase();
    const base = ALLOW[path];
    if (!base) {
      return send(400, { error: "endpoint must be autocomplete|details|geocode" });
    }

    const qs = new URLSearchParams(event.queryStringParameters || {});
    qs.delete("endpoint");
    if (!qs.has("key")) qs.set("key", GOOGLE_KEY);
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
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
    body: JSON.stringify(body),
  };
}
