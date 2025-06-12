const { createClient } = require('@supabase/supabase-js');

// Initialiser Supabase avec les variables d'environnement
console.log("Initialisation Supabase...");
console.log("SUPABASE_URL =", process.env.SUPABASE_URL);
console.log("SERVICE_ROLE =", process.env.SUPABASE_SERVICE_ROLE);

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE
);

exports.handler = async (event, context) => {
  try {
    console.log("🟡 Requête reçue : ", event.body);
    const { chauffeur_id, date, heure, montant } = JSON.parse(event.body);

    console.log("🟢 Données à insérer :", { chauffeur_id, date, heure, montant });

    const { error } = await supabase
      .from('passagers')
      .insert([{ chauffeur_id, nombre_passagers: 1, date, heure, montant }]);

    if (error) {
      console.error("🔴 Erreur Supabase :", error);
      return {
        statusCode: 401,
        body: JSON.stringify({
          message: "Erreur Supabase",
          erreur: error.message,
          details: error.details,
        }),
      };
    }

    console.log("✅ Insertion réussie");
    return {
      statusCode: 200,
      body: JSON.stringify({ message: "Insertion réussie" }),
    };

  } catch (err) {
    console.error("❌ Erreur interne :", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ message: "Erreur interne", erreur: err.message }),
    };
  }
};
