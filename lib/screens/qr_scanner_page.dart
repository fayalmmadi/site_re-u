import 'dart:html' as html;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QRCodePage extends StatelessWidget {
  final String voitureId;
  QRCodePage({super.key, required this.voitureId});

  final GlobalKey qrKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final String chauffeurId = userId;

    final now = DateTime.now();
    final String currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final String qrData =
        'https://suivi-taxis.netlify.app/checkin.html?voiture_id=$voitureId&valid=$currentMonth';

    return Scaffold(
      backgroundColor: const Color(0xFFFDF7EE), // beige clair
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4D3E), // vert foncé
        title: const Text(
          'Suivi Taxi',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Text(
                'Mon QR Code de voiture',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B4D3E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Color(0xFF3E8E7E), width: 3),
                ),
                child: RepaintBoundary(
                  key: qrKey,
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 240.0,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  try {
                    RenderRepaintBoundary boundary =
                        qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
                    var image = await boundary.toImage(pixelRatio: 5.0);
                    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                    Uint8List pngBytes = byteData!.buffer.asUint8List();

                    final blob = html.Blob([pngBytes]);
                    final url = html.Url.createObjectUrlFromBlob(blob);
                    final anchor = html.AnchorElement(href: url)
                      ..setAttribute("download", "qr_code_${chauffeurId}_$currentMonth.png")
                      ..click();
                    html.Url.revokeObjectUrl(url);
                  } catch (e) {
                    print("Erreur lors du téléchargement : $e");
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4D3E),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Télécharger mon QR code',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
