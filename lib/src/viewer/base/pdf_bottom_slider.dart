import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:pdfx/src/viewer/base/debouncer.dart';
import 'package:pdfx/src/viewer/base/slider_component_shape.dart';
import 'package:pdfx/src/viewer/base/slider_thumb_image.dart';
import 'package:pdfx/src/viewer/base/slider_track_shape.dart';

class PdfBottomSlider extends StatefulWidget {
  const PdfBottomSlider({
    super.key,
    required this.controller,
  });
  final PdfController controller;
  @override
  State<PdfBottomSlider> createState() => _PdfBottomSliderState();
}

class _PdfBottomSliderState extends State<PdfBottomSlider>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  // State variables
  List<PdfPageImage> _thumbnailImageList = [];
  ui.Image? _sliderImage;
  int _currentPage = 1;
  bool _isDragging = false;
  bool _pageIsActive = true;

  // Debouncers for delaying resize and slider image update
  final _resizeScreenDebouncer =
      Debouncer(delay: const Duration(milliseconds: 500));
  final _sliderImageDebouncer =
      Debouncer(delay: const Duration(milliseconds: 100));

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  // Initialize the page
  void _initializePage() {
    _pageIsActive = true;
    WidgetsBinding.instance.addObserver(this);
    _animationController = _createAnimationController();
  }

  // Generate initial images for the slider
  void _generateInitialSliderImages() {
    _generateSliderImages(
      PlatformDispatcher.instance.views.first.physicalSize.width,
    );
  }

  // Set initial page image
  void _setInitialPageImage() {
    _getPageImage(widget.controller.page);
  }

  // Dispose page and controllers
  void _disposePage() {
    _pageIsActive = false;
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void dispose() {
    _disposePage();
    super.dispose();
  }

  // Resize screen and regenerate thumbnails
  @override
  void didChangeMetrics() {
    if (_pageIsActive) {
      _resizeScreenDebouncer.run(() {
        _generateSliderImages(
          PlatformDispatcher.instance.views.first.physicalSize.width,
        );
      });
    }
    super.didChangeMetrics();
  }

  // Create Animation Controller
  AnimationController _createAnimationController() {
    return AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  // Generate thumbnails for the slider
  Future<void> _generateSliderImages(double width) async {
    // Get the document from the given path
    final document = await widget.controller.document;

    // Total number of pages in the document
    final pageCount = document.pagesCount;

    // Calculate the number of thumbnails to generate based on the screen width
    final thumbnailCount = (width / 130).round().clamp(0, pageCount);

    // Generate a list of points (page numbers) for which to capture thumbnails
    final points = _calculateThumbnailPoints(pageCount, thumbnailCount);

    // Generate thumbnail images
    final imageList = await _generateThumbnails(document, points);

    // Update the thumbnail list in the state
    if (mounted) {
      // <-- Check if the widget is still mounted
      setState(() {
        _thumbnailImageList = imageList;
      });
    }
  }

  // Calculate thumbnail points based on the number of pages and required thumbnails
  List<double> _calculateThumbnailPoints(int pageCount, int thumbnailCount) {
    if (thumbnailCount <= 1) {
      return [1.0]; // or return a value that makes sense in your context
    }

    return List<double>.generate(
      thumbnailCount,
      (i) => 1.0 + i * ((pageCount - 1) / (thumbnailCount - 1)),
    );
  }

// Generate thumbnails for given points (page numbers)
  Future<List<PdfPageImage>> _generateThumbnails(
      PdfDocument document, List<double> points) async {
    final imageList = <PdfPageImage>[];
    for (final point in points) {
      final page = await document.getPage(point.round());
      try {
        final pageImage = await page.render(
          width: page.width / 10,
          height: page.height / 10,
        );
        if (pageImage != null) {
          imageList.add(pageImage);
        }
      } finally {
        await page.close();
      }
    }
    return imageList;
  }

// Fetch image of a specific page number
  Future<void> _getPageImage(int pageNum) async {
    final document = await widget.controller.document;
    final page = await document.getPage(pageNum);
    try {
      final image = await page.render(
        width: page.width / 10,
        height: page.height / 10,
      );
      if (image != null) {
        final newImg = await _getUiImage(image.bytes);
        setState(() {
          _sliderImage = newImg;
        });
      }
    } finally {
      await page.close();
    }
  }

  // Convert PdfPageImage to ui.Image
  Future<ui.Image> _getUiImage(Uint8List byteData) async {
    final codec = await ui.instantiateImageCodec(byteData);
    return (await codec.getNextFrame()).image;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PdfLoadingState>(
        valueListenable: widget.controller.loadingState,
        builder: (context, loadingState, child) {
          if (loadingState == PdfLoadingState.loading) {
            _generateInitialSliderImages();
            _setInitialPageImage();
          }
          return ValueListenableBuilder<int>(
              valueListenable: widget.controller.pageListenable,
              builder: (context, page, child) {
                if (loadingState != PdfLoadingState.success) {
                  return Container();
                }
                final width = MediaQuery.of(context).size.width;
                return Container(
                  height: 60,
                  width: (width / 130)
                          .round()
                          .clamp(0, widget.controller.pagesCount!) *
                      37,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 40,
                        child: Align(
                          child: ListView.separated(
                            shrinkWrap: true,
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (context, index) {
                              return Container(
                                width: 30,
                                color: Theme.of(context).cardColor,
                                child: _thumbnailImageList.isEmpty ||
                                        _thumbnailImageList.length <= index
                                    ? const CupertinoActivityIndicator()
                                    : Image(
                                        image: MemoryImage(
                                          _thumbnailImageList[index].bytes,
                                        ),
                                      ),
                              );
                            },
                            itemCount: _thumbnailImageList.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 5, width: 5),
                          ),
                        ),
                      ),
                      if (widget.controller.pagesCount != 1)
                        SliderTheme(
                          data: SliderThemeData(
                            thumbShape: SliderThumbImage(
                              image: _sliderImage,
                              isDragging: _isDragging,
                              rotation: _animationController.value,
                            ),
                            overlayShape: SliderComponentShape.noOverlay,
                            trackHeight: 0,
                            trackShape: CustomTrackShape(),
                            showValueIndicator: ShowValueIndicator.always,
                            valueIndicatorShape: CustomValueIndicatorShape(),
                          ),
                          child: Slider(
                            value: _currentPage.toDouble(),
                            max: widget.controller.page.toDouble(),
                            min: 1,
                            label: widget.controller.page.toString(),
                            onChanged: (double value) {
                              final pageNum = value.round();
                              setState(() {
                                _sliderImage = null;
                                _isDragging = true;
                                _currentPage = pageNum;
                              });
                              _sliderImageDebouncer.run(
                                () => _getPageImage(pageNum),
                              );
                            },
                            onChangeEnd: (double value) {
                              widget.controller.jumpToPage(
                                value.round(),
                              );
                              setState(() {
                                _isDragging = false; // <-- Set to false
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                );
              });
        });
  }
}
