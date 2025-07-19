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

    // Données attendues
    const { voiture_id, date, heure, montant, uuid, ip, mois_validite } = body;

    console.log("📦 Données reçues :", {
      voiture_id, date, heure, montant, uuid, ip, mois_validite, isCheckOnly
    });

    // 🔄 Vérifie si ce téléphone (uuid) a scanné cette voiture dans les 2 dernières minutes
    const now = new Date();
    const twoMinAgo = new Date(now.getTime() - 2 * 60 * 1000).toISOString();

    const { data: recentScan, error: scanError } = await supabase
      .from('passagers')
      .select('created_at')
      .eq('uuid', uuid)
      .eq('voiture_id', voiture_id)
      .gte('created_at', twoMinAgo)
      .maybeSingle();

    if (scanError) {
      console.error("❌ Erreur vérification doublon :", scanError.message);
    }

    if (recentScan) {
      return {
        statusCode: 200,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ status: 'too_soon' }),
      };
    }

    // ✅ Vérification uniquement
    if (isCheckOnly) {
      return {
        statusCode: 200,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ status: 'ok' }),
      };
    }

    // ✅ Insertion dans Supabase
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
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ message: "Erreur insertion", erreur: error.message }),
      };
    }

    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ message: "Insertion réussie" }),
    };

  } catch (err) {
    console.error("💥 Erreur serveur :", err.message);
    return {
      statusCode: 500,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ message: "Erreur serveur", erreur: err.message }),
    };
  }
};
