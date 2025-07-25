const { createClient } = require('@supabase/supabase-js');

// 🔐 Remplace par ta vraie clé Service Role
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE
);

exports.handler = async (event, context) => {
  try {
    const body = JSON.parse(event.body);

    // 🔸 Récupération des données
    const voiture_id = body.voiture_id;
    const date = body.date;
    const heure = body.heure;
    const montant = body.montant ?? 0;
    const uuid = body.uuid;
    const mois_validite = body.mois_validite;
    const ip = body.ip || event.headers['x-forwarded-for'] || '0.0.0.0';
    const isCheckOnly = body.isCheckOnly === true;

    console.log("📥 Données reçues :", {
      voiture_id,
      date,
      heure,
      montant,
      uuid,
      mois_validite,
      ip,
      isCheckOnly
    });

    // ✅ Vérifie délai anti-spam (15 minutes)
    const now = new Date();
    const { data: recentScans, error: scanError } = await supabase
      .from('passagers')
      .select('created_at')
      .eq('voiture_id', voiture_id)
      .eq('ip', ip)
      .order('created_at', { ascending: false })
      .limit(1);

    if (recentScans && recentScans.length > 0) {
      const lastScan = new Date(recentScans[0].created_at);
      const diffMinutes = (now - lastScan) / (1000 * 60);

      if (diffMinutes < 15) {
        console.log("⏳ Scan trop récent, refusé.");
        return {
          statusCode: 200,
          body: JSON.stringify({ status: 'too_soon' }),
        };
      }
    }

    // ✅ Mode check uniquement (affichage reçu sans insertion)
    if (isCheckOnly) {
      return {
        statusCode: 200,
        body: JSON.stringify({ status: 'ok' }),
      };
    }

    // ✅ Insertion du passager
    console.log("👉 Données envoyées à Supabase :", {
      voiture_id,
      date,
      heure,
      montant,
      uuid,
      ip,
      mois_validite
    });

    const { error } = await supabase.from("passagers").insert([{
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

    console.log("✅ Passager inséré avec succès !");
    return {
      statusCode: 200,
      body: JSON.stringify({ message: "Insertion réussie" }),
    };

  } catch (err) {
    console.error("❌ Erreur globale :", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ message: "Erreur serveur", erreur: err.message }),
    };
  }
};
