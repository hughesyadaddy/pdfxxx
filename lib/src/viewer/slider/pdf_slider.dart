import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:pdfx/src/viewer/slider/debouncer.dart';
import 'package:pdfx/src/viewer/slider/slider_component_shape.dart';
import 'package:pdfx/src/viewer/slider/slider_thumb_image.dart';
import 'package:pdfx/src/viewer/slider/slider_track_shape.dart';

class PdfSlider extends StatefulWidget {
  final int totalPages;
  final Map<int, PdfPageImage?> thumbnailCache;
  final ValueChanged<int> onPageChanged;
  final Future<PdfPageImage?> Function(int pageIndex) getPageImage;

  const PdfSlider({
    Key? key,
    required this.totalPages,
    required this.thumbnailCache,
    required this.onPageChanged,
    required this.getPageImage,
  }) : super(key: key);

  @override
  _PdfSliderState createState() => _PdfSliderState();
}

class _PdfSliderState extends State<PdfSlider>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  int _sliderPage = 0;
  late List<double> _thumbnailPoints;
  bool _isDragging = false;
  ui.Image? _sliderImage;
  bool _pageIsActive = true;
  // Debouncers for delaying resize and slider image update
  final _resizeScreenDebouncer =
      Debouncer(delay: const Duration(milliseconds: 500));
  final _sliderImageDebouncer =
      Debouncer(delay: const Duration(milliseconds: 100));
  @override
  void initState() {
    super.initState();
    _pageIsActive = true;
    WidgetsBinding.instance.addObserver(this);
    _animationController = _createAnimationController();
    _initializeThumbnails();
    _getSliderImage(_sliderPage);
  }

  @override
  void dispose() {
    _pageIsActive = false;
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  } // Resize screen and regenerate thumbnails

  @override
  void didChangeMetrics() {
    if (_pageIsActive) {
      _resizeScreenDebouncer.run(() {
        _initializeThumbnails();
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

  // Initialize thumbnails
  void _initializeThumbnails() {
    final thumbnailCount = _calculateThumbnailCount(
        ui.PlatformDispatcher.instance.views.first.physicalSize.width,
        widget.totalPages);
    _calculateThumbnailPoints(widget.totalPages, thumbnailCount);
  }

  int _calculateThumbnailCount(double width, int pageCount) {
    return (width / 130).round().clamp(0, pageCount);
  }

  void _calculateThumbnailPoints(int pageCount, int thumbnailCount) {
    setState(() {
      if (thumbnailCount <= 1) {
        _thumbnailPoints = [0.0];
      } else {
        _thumbnailPoints = List<double>.generate(
          thumbnailCount,
          (i) => i * ((pageCount - 1) / (thumbnailCount - 1)),
        );
      }
    });
  }

  // Thumbnail builder
  Widget _buildThumbnail(int index) {
    final pageIndex = _thumbnailPoints[index].toInt();

    // Check if the thumbnail is already loaded
    if (widget.thumbnailCache.containsKey(pageIndex) &&
        widget.thumbnailCache[pageIndex]?.bytes != null) {
      // If the thumbnail is already loaded, display it
      return Image(image: MemoryImage(widget.thumbnailCache[pageIndex]!.bytes));
    } else {
      // If the thumbnail is not loaded, use FutureBuilder to load it
      return FutureBuilder<PdfPageImage?>(
        future: widget.getPageImage(pageIndex),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CupertinoActivityIndicator();
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else if (snapshot.hasData) {
            // Once the data is available, update _pages and display the image
            widget.thumbnailCache[pageIndex] = snapshot.data;
            return Image(image: MemoryImage(snapshot.data!.bytes));
          } else {
            return const Text('No image available');
          }
        },
      );
    }
  }

  Future<void> _getSliderImage(int pageIndex) async {
    final image =
        await _getUiImage((await widget.getPageImage(pageIndex))!.bytes);
    setState(() {
      _sliderImage = image;
    });
  }

  // Convert PdfPageImage to ui.Image
  Future<ui.Image> _getUiImage(Uint8List byteData) async {
    final codec = await ui.instantiateImageCodec(byteData);
    return (await codec.getNextFrame()).image;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: _thumbnailPoints.length * 37,
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
                itemBuilder: (context, index) => _buildThumbnail(index),
                itemCount: _thumbnailPoints.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 5, width: 5),
              ),
            ),
          ),
          if (widget.totalPages != 1)
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
                valueIndicatorShape:
                    CustomValueIndicatorShape(verticalOffset: 65),
              ),
              child: Slider(
                value: _sliderPage.toDouble(),
                max: widget.totalPages.toDouble() - 1,
                min: 0,
                label: (_sliderPage + 1).toString(),
                onChanged: (double value) {
                  final pageNum = value.round();
                  setState(() {
                    _sliderImage = null;
                    _isDragging = true;
                    _sliderPage = pageNum;
                  });
                  _sliderImageDebouncer.run(
                    () => _getSliderImage(pageNum),
                  );
                },
                onChangeEnd: (double value) {
                  setState(() {
                    _isDragging = false; // <-- Set to false
                  });
                  widget.onPageChanged(value.round());
                },
              ),
            ),
        ],
      ),
    );
  }
}
