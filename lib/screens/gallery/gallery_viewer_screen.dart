// screens/gallery/gallery_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';

class GalleryViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  // NEW: when provided, each page gets a Hero tag of
  // '${heroTagPrefix}_$index' so swiping in from the detail screen's
  // carousel (which uses the same tag scheme) animates smoothly.
  // Left null, pages render with no Hero wrapper — fully backward
  // compatible with any existing caller that doesn't pass it.
  final String? heroTagPrefix;

  const GalleryViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.heroTagPrefix,
  });

  @override
  State<GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends State<GalleryViewerScreen> {
  late PageController _pageController;

  late int currentIndex;

  @override
  void initState() {
    super.initState();

    currentIndex = widget.initialIndex;

    _pageController = PageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _pageController,

            itemCount: widget.images.length,

            onPageChanged: (index) {
              setState(() {
                currentIndex = index;
              });
            },

            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(widget.images[index]),

                // NEW: enables the Hero flight from the detail screen's
                // carousel page into the matching gallery page.
                heroAttributes: widget.heroTagPrefix != null
                    ? PhotoViewHeroAttributes(
                        tag: '${widget.heroTagPrefix}_$index',
                      )
                    : null,

                minScale: PhotoViewComputedScale.contained,

                maxScale: PhotoViewComputedScale.covered * 3,
              );
            },

            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },

                    child: Container(
                      padding: const EdgeInsets.all(10),

                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),

                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: Text(
                      '${currentIndex + 1}/${widget.images.length}',

                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
