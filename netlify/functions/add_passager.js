const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE
);

exports.handler = async (event, context) => {
  try {
    const body = JSON.parse(event.body);
    const isCheckOnly = body.checkOnly == true;

    // ✅ On récupère IP depuis le body ou depuis le header
    const ip = body.ip || event.headers['x-forwarded-for'] || '0.0.0.0';

    // ✅ On récupère le reste normalement
    const { chauffeur_id, date, heure, montant, uuid } = body;

    console.log("📦 Données reçues :", { chauffeur_id, date, heure, montant, uuid, ip, isCheckOnly });

    // 1️⃣ Vérifie si ce passager a déjà scanné aujourd’hui
    const { data: existing } = await supabase
      .from('passagers')
      .select('id')
      .eq('uuid', uuid)
      .eq('date', date)
      .maybeSingle();

    if (existing) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'exists' }),
      };
    }

    // 2️⃣ Vérifie si cette IP a scanné ce chauffeur dans les 15 dernières minutes
    const now = new Date();
    const fifteenMinAgo = new Date(now.getTime() - 15 * 60 * 1000).toISOString();

    const { data: recentScan } = await supabase
      .from('passagers')
      .select('created_at')
      .eq('ip', ip)
      .eq('chauffeur_id', chauffeur_id)
      .gte('created_at', fifteenMinAgo)
      .maybeSingle();

    if (recentScan) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'too_soon' }),
      };
    }

    // 3️⃣ Si checkOnly, ne fais pas l'insertion
    if (isCheckOnly) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'ok' }),
      };
    }

    // 4️⃣ Insertion du passager
    const { error } = await supabase.from('passagers').insert([{
      chauffeur_id,
      date,
      heure,
      montant,
      uuid,
      ip,
      nombre_passagers: 1
    }]);

    if (error) {
      console.error("❌ Erreur insertion Supabase :", error.message);
      return {
        statusCode: 401,
        body: JSON.stringify({ message: "Erreur insertion", erreur: error.message }),
      };
    }

    return {
      statusCode: 200,
      body: JSON.stringify({ message: "Insertion réussie" }),
    };

  } catch (err) {
    console.error("💥 Erreur serveur :", err.message);
    return {
      statusCode: 500,
      body: JSON.stringify({ message: "Erreur serveur", erreur: err.message }),
    };
  }
};
