const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE
);

exports.handler = async (event, context) => {
  try {
    const body = JSON.parse(event.body);
    const isCheckOnly = body.checkOnly === true;

    const { voiture_id, date, heure, montant, uuid, ip } = body;

    console.log("📦 Données reçues :", { voiture_id, date, heure, montant, uuid, isCheckOnly });

    // 🔄 Vérifie si ce téléphone (uuid) a scanné dans les 2 dernières minutes
    const now = new Date();
    const twoMinAgo = new Date(now.getTime() - 2 * 60 * 1000).toISOString();

    const { data: recentScan } = await supabase
      .from('passagers')
      .select('created_at')
      .eq('uuid', uuid)
      .eq('voiture_id', voiture_id)
      .gte('created_at', twoMinAgo)
      .maybeSingle();

    // ⛔️ Si déjà scanné récemment (page actualisée ou double clic), on bloque
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

    // ✅ Si juste une vérification (checkOnly), on s’arrête ici
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

    // ✅ Sinon on insère un passager
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
