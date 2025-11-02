import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/driver_dashboard.dart';
import 'screens/owner_dashboard.dart';
import 'screens/contact_page.dart';
import 'screens/receipt_page.dart';
import 'screens/qr_scanner_page.dart';
import 'screens/password_reset_page.dart';
import 'screens/ajouter_voiture_page.dart';
import 'screens/abonnement_page.dart';

import 'pages/home_page.dart';                    // <- ACCUEIL
import 'pages/role_selection_page.dart';
import 'pages/clients_page.dart';
import 'pages/partenaire_statut.dart' ; 
import 'pages/livreur_status.dart';
import 'pages/livreur_dashboard_page.dart';
import 'pages/pending_status_page.dart';
import 'pages/acces_compte_page.dart';               // <- /commande-taxi

import 'pages/login_chauffeur.dart';
import 'pages/login_partenaire.dart';
import 'pages/admin_dashboard.dart';
import 'pages/profil_chauffeur_page.dart';
import 'pages/profil_proprietaire_page.dart';
import 'pages/profil_livreur_page.dart';
import 'pages/inscription_partenaire.dart';
import 'pages/partenaire_dashboard_page.dart';
import 'pages/update_password_page.dart';
import 'pages/acces_partenaire_page.dart';
import 'pages/support_chat_page.dart';
import 'pages/login_admin.dart';
import 'pages/email_confirmed_page.dart';
import 'pages/signup_chauffeur_page.dart';
import 'pages/demander_livraison_page.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:easy_localization/easy_localization.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await EasyLocalization.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pzwypnxmdasuhiebtjwm.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB6d3lwbnhtZGFzdWhpZWJ0andtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDg5NzEwOTYsImV4cCI6MjA2NDU0NzA5Nn0.ooUjVT4YUmr7kjMY1KwI6xysD4i5CSF4HlSDjKGzAdE',
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('fr'), Locale('en'), Locale('km'), Locale('ar'),
        Locale('es'), Locale('zh'), Locale('tr'),
      ],
      path: 'assets/langs',
      fallbackLocale: const Locale('fr'),
      child: const SuiviTaxiApp(),
    ),
  );
}

class SuiviTaxiApp extends StatelessWidget {
  const SuiviTaxiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Suivi Taxi',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF084C28),
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF084C28)),
      ),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,

      // ACCUEIL -> “Accéder à mon espace” (login/signup)
      home: const HomePage(),

      routes: {
        // Navigation principale
        '/roles': (_) => const RoleSelectionPage(),
        '/admin': (_) => const AdminDashboard(),

        // Public
        '/commande-taxi': (_) => const ClientsPage(),

        // Auth / accès
        '/login': (_) => LoginChauffeurPage(),            // <- route attendue par RoleSelectionPage
        '/login_chauffeur': (_) => LoginChauffeurPage(),
        '/login_partenaire': (_) => const LoginPartenairePage(),
        '/login_admin': (_) => LoginAdminPage(),
        '/signup_chauffeur': (_) => const SignupChauffeurPage(),
        '/update-password': (_) => const UpdatePasswordPage(),
        '/reset': (_) => PasswordResetPage(),
        '/email-confirmed': (_) => const EmailConfirmedPage(),

        // Profils (SANS email/mot de passe)
        '/profil_chauffeur': (_) => const ProfilChauffeurPage(),
        '/profil_proprietaire': (_) => const ProfilProprietairePage(),
        '/profil_livreur': (_) => const ProfilLivreurPage(),

        // Partenaire (inscription + accès sécurisé)
        '/inscription_partenaire': (_) => const InscriptionPartenairePage(),
        '/acces_partenaire': (_) => const AccesPartenairePage(),
        '/partenaire_dashboard': (_) => const PartenaireDashboardPage(),
        '/acces-compte': (_) => const AccesComptePage(),
        '/livreur_statut': (_) => PendingStatusPage(
          tableName: 'livreurs',
          roleLabel: 'Livreur',
          dashboardRoute: '/livreur_dashboard',
          signupRoute: '/profil_livreur',
        ),
        '/partenaire_statut': (_) => PendingStatusPage(
          tableName: 'partenaires',
          roleLabel: 'Partenaire',
          dashboardRoute: '/partenaire_dashboard',
          signupRoute: '/inscription_partenaire',
        ),
        '/livraison-demande': (context) => const DemanderLivraisonPage(),
        '/livreur_dashboard': (_) => const LivreurDashboardPage(),

        // Dashboards
        '/chauffeur': (_) => DriverDashboard(),
        '/proprietaire': (_) => OwnerDashboard(),
        '/admin_dashboard': (_) => const AdminDashboard(),

        // Divers
        '/contact': (_) => ContactPage(),
        '/recu': (_) => ReceiptPage(),
        '/scanner': (_) => QRCodePage(
              voitureId: 'b8dd533e-5a12-4692-8de0-b145c108e28d',
            ),
        '/ajouter-voiture': (_) => AjouterVoiturePage(),
        '/abonnement': (_) => AbonnementPage(),
        '/support': (_) => SupportChatPage(
              partnerId: Supabase.instance.client.auth.currentUser?.id ?? 'admin',
            ),

        // Alias éventuel
        '/role-selection': (_) => const RoleSelectionPage(),
      },
    );
  }
}
