import 'package:flutter/material.dart';

class Gallery extends StatefulWidget {
  const Gallery({super.key, required this.images});
  final List<String> images;

  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  late final PageController _pc;
  @override
  void initState() { super.initState(); _pc = PageController(); }
  @override
  void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _pc,
          itemCount: widget.images.length,
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 0.8, maxScale: 4,
            child: Image.network(widget.images[i], fit: BoxFit.contain),
          ),
        ),
        Positioned(
          top: 8, right: 8,
          child: IconButton(
            style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
