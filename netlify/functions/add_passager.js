const fetch = require('node-fetch');

exports.handler = async (event) => {
  const { chauffeur_id, date, heure, montant } = JSON.parse(event.body);

  const response = await fetch(`${process.env.SUPABASE_URL}/rest/v1/passagers`, {
    method: 'POST',
    headers: {
      apikey: process.env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation'
    },
    body: JSON.stringify({
      chauffeur_id,
      nombre_passagers: 1,
      date,
      heure,
      montant
    })
  });

  const data = await response.json();
  return {
    statusCode: response.status,
    body: JSON.stringify(data)
  };
};
