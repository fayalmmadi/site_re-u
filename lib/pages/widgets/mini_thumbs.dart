import 'package:flutter/material.dart';

class MiniThumbs extends StatelessWidget {
  const MiniThumbs({super.key, required this.images, required this.onTap});
  final List<String> images;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = 64.0;
    final url1 = images.isNotEmpty ? images[0] : null;
    final url2 = images.length > 1 ? images[1] : null;

    Widget box(String? url) => InkWell(
      onTap: (url == null || url.isEmpty) ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: size, height: size, color: const Color(0xFFEDEDED),
          child: (url == null || url.isEmpty)
              ? const Icon(Icons.image, color: Colors.black26)
              : Image.network(url, fit: BoxFit.cover),
        ),
      ),
    );

    return Row(children: [
      box(url1),
      const SizedBox(width: 6),
      box(url2),
    ]);
  }
}
