const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE
);

exports.handler = async (event, context) => {
  try {
    const body = JSON.parse(event.body);
    const isCheckOnly = body.checkOnly === true;

    const ip = body.ip || event.headers['x-forwarded-for'] || '0.0.0.0';
    const { voiture_id, date, heure, montant, uuid } = body;

    console.log("📦 Données reçues :", { voiture_id, date, heure, montant, uuid, ip, isCheckOnly });

    // 1️⃣ Vérifie si cette IP a scanné CETTE voiture dans les 2 dernières minutes
    const now = new Date();
    const twoMinAgo = new Date(now.getTime() - 2 * 60 * 1000).toISOString();

    const { data: recentShortScan } = await supabase
      .from('passagers')
      .select('created_at')
      .eq('uuid', uuid)
      .eq('voiture_id', voiture_id)
      .gte('created_at', twoMinAgo)
      .maybeSingle();

    if (recentShortScan) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'too_soon' }),
      };
    }

    // 2️⃣ Vérifie si cette IP a scanné CETTE voiture dans les 15 dernières minutes
    const fifteenMinAgo = new Date(now.getTime() - 15 * 60 * 1000).toISOString();

    const { data: recentLongScan } = await supabase
      .from('passagers')
      .select('created_at')
      .eq('uuid', uuid)
      .eq('voiture_id', voiture_id)
      .gte('created_at', fifteenMinAgo)
      .maybeSingle();

    if (recentLongScan) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'too_soon' }),
      };
    }

    // 3️⃣ Si checkOnly, ne fais pas d'insertion
    if (isCheckOnly) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'ok' }),
      };
    }

    // 4️⃣ Insertion
    const { error } = await supabase.from('passagers').insert([{
      voiture_id,
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
