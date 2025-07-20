const { createClient } = require('@supabase/supabase-js');

// Connexion à Supabase
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE
);

exports.handler = async (event, context) => {
  try {
    const body = JSON.parse(event.body);
    const isCheckOnly = body.checkOnly === true;

    // 🔍 Récupération des données
    const voiture_id = body.voiture_id;
    const date = body.date;
    const heure = body.heure;
    const montant = body.montant ?? 0; // Si vide, met 0
    const uuid = body.uuid;
    const mois_validite = body.mois_validite;
    const ip = body.ip || event.headers['x-forwarded-for'] || '0.0.0.0';

    console.log("📦 Données reçues :", {
      voiture_id, date, heure, montant, uuid, ip, mois_validite, isCheckOnly
    });

    // 1️⃣ Vérifie si ce passager a déjà scanné aujourd’hui (par UUID + date)
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

    // 2️⃣ Vérifie si ce passager a scanné il y a moins de 15 minutes (anti-spam)
    const now = new Date();
    const fifteenMinAgo = new Date(now.getTime() - 15 * 60 * 1000).toISOString();

    const { data: recentScan } = await supabase
      .from('passagers')
      .select('created_at')
      .eq('uuid', uuid)
      .eq('voiture_id', voiture_id)
      .gte('created_at', fifteenMinAgo)
      .maybeSingle();

    if (recentScan) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'too_soon' }),
      };
    }

    // 3️⃣ Mode vérification uniquement
    if (isCheckOnly) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'ok' }),
      };
    }

    // 4️⃣ Insertion du passager
    const { error } = await supabase.from('passagers').insert([{
      voiture_id,
      date,
      heure,
      montant,
      uuid,
      ip,
      mois_validite,
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
