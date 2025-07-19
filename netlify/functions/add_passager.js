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

    // 📥 Données attendues
    const {
      voiture_id,
      date,
      heure,
      montant = 0,
      uuid,
      mois_validite
    } = body;

    // 🔍 Récupère l'IP (depuis body ou header)
    const ip = body.ip || event.headers['x-forwarded-for'] || '0.0.0.0';

    console.log("📦 Données reçues :", {
      voiture_id, date, heure, montant, uuid, ip, mois_validite, isCheckOnly
    });

    // 1️⃣ Vérifie si ce passager (uuid) a déjà scanné aujourd’hui
    const { data: dejaInsere } = await supabase
      .from('passagers')
      .select('id')
      .eq('uuid', uuid)
      .eq('date', date)
      .eq('voiture_id', voiture_id)
      .maybeSingle();

    if (dejaInsere) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'exists' }),
      };
    }

    // 2️⃣ Vérifie délai 15 min pour cette IP + voiture
    const now = new Date();
    const quinzMinAgo = new Date(now.getTime() - 15 * 60 * 1000).toISOString();

    const { data: doublon } = await supabase
      .from('passagers')
      .select('id')
      .eq('voiture_id', voiture_id)
      .eq('ip', ip)
      .gte('created_at', quinzMinAgo)
      .maybeSingle();

    if (doublon) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'too_soon' }),
      };
    }

    // 3️⃣ Si checkOnly, ne rien insérer
    if (isCheckOnly) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'ok' }),
      };
    }

    // 4️⃣ Insertion finale du passager
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
