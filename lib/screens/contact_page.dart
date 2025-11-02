import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  void _callPhone() async {
    final uri = Uri.parse("tel:+33695039119"); // <-- ton numéro ici
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openWhatsApp() async {
    final uri = Uri.parse("https://wa.me/33695039119"); // <-- ton numéro sans +
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _sendEmail() async {
    final uri = Uri.parse("mailto:support@naviaapp.com");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('contact_us'.tr(),style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF084C28),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Text(
              "Besoin d'aide ou d'informations ?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.phone, color: Colors.green),
                title: const Text('Appeler'),
                subtitle: const Text('+33695039119'),
                onTap: _callPhone,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.chat, color: Colors.green),
                title: const Text('WhatsApp'),
                subtitle: const Text('Envoyer un message'),
                onTap: _openWhatsApp,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.email, color: Colors.green),
                title: const Text('Email'),
                subtitle: const Text('support@naviaapp.com'),
                onTap: _sendEmail,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
