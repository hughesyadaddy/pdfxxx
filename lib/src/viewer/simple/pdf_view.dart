import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/src/renderer/interfaces/document.dart';
import 'package:pdfx/src/renderer/interfaces/page.dart';
import 'package:pdfx/src/viewer/base/base_pdf_builders.dart';
import 'package:pdfx/src/viewer/base/base_pdf_controller.dart';
import 'package:pdfx/src/viewer/base/debouncer.dart';
import 'package:pdfx/src/viewer/base/slider_component_shape.dart';
import 'package:pdfx/src/viewer/base/slider_thumb_image.dart';
import 'package:pdfx/src/viewer/base/slider_track_shape.dart';
import 'package:pdfx/src/viewer/pdf_page_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:synchronized/synchronized.dart';

part 'pdf_controller.dart';
part 'pdf_view_builders.dart';

typedef PDfViewPageRenderer = Future<PdfPageImage?> Function(PdfPage page);

final Lock _lock = Lock();

/// Widget for viewing PDF documents
class PdfView extends StatefulWidget {
  const PdfView({
    required this.controller,
    this.onPageChanged,
    this.onDocumentLoaded,
    this.onDocumentError,
    this.builders = const PdfViewBuilders<DefaultBuilderOptions>(
      options: DefaultBuilderOptions(),
    ),
    this.renderer = _render,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.pageSnapping = true,
    this.physics,
    this.backgroundDecoration = const BoxDecoration(),
    Key? key,
  }) : super(key: key);

  /// Page management
  final PdfController controller;

  /// Called whenever the page in the center of the viewport changes
  final void Function(int page)? onPageChanged;

  /// Called when a document is loaded
  final void Function(PdfDocument document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Object error)? onDocumentError;

  /// Builders
  final PdfViewBuilders builders;

  /// Custom PdfRenderer options
  final PDfViewPageRenderer renderer;

  /// Page turning direction
  final Axis scrollDirection;

  /// Reverse scroll direction, useful for RTL support
  final bool reverse;

  /// Set to false to disable page snapping, useful for custom scroll behavior.
  final bool pageSnapping;

  /// Pdf widget page background decoration
  final BoxDecoration? backgroundDecoration;

  /// Determines the physics of a [PdfView] widget.
  final ScrollPhysics? physics;

  /// Default PdfRenderer options
  static Future<PdfPageImage?> _render(PdfPage page) => page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#ffffff',
      );

  @override
  State<PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<PdfView>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  final Map<int, PdfPageImage?> _pages = {};
  PdfController get _controller => widget.controller;
  Exception? _loadingError;
  List<double>? _thumbnailPoints;
  int _sliderNumber = 0;
  bool _isDragging = false;
  ui.Image? _sliderImage;
  // Debouncers for delaying resize and slider image update
  final _resizeScreenDebouncer =
      Debouncer(delay: const Duration(milliseconds: 500));
  final _sliderImageDebouncer =
      Debouncer(delay: const Duration(milliseconds: 100));
  @override
  void initState() {
    super.initState();
    _controller._attach(this);
    _controller.loadingState.addListener(() {
      switch (_controller.loadingState.value) {
        case PdfLoadingState.loading:
          _pages.clear();
          break;
        case PdfLoadingState.success:
          setState(() {
            _sliderNumber = 0;
          });
          _initializeSliderImage();
          _initializeThumbnails();

          widget.onDocumentLoaded?.call(_controller._document!);
          break;
        case PdfLoadingState.error:
          widget.onDocumentError?.call(_loadingError!);
          break;
      }
      if (mounted) {
        setState(() {});
      }
    });
    _animationController = _createAnimationController();
  }

  // Create Animation Controller
  AnimationController _createAnimationController() {
    return AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  // Resize screen and regenerate thumbnails
  @override
  void didChangeMetrics() {
    _resizeScreenDebouncer.run(() {
      final thumbnailCount = _calculateThumbnailCount(
          ui.PlatformDispatcher.instance.views.first.physicalSize.width,
          _controller._document!.pagesCount);
      _calculateThumbnailPoints(
          _controller._document!.pagesCount, thumbnailCount);
    });
    super.didChangeMetrics();
  }

  @override
  void dispose() {
    _controller._detach();
    super.dispose();
  }

  void _initializeSliderImage() async {
    if (_controller._document != null &&
        _controller._document!.pagesCount > 0) {
      await _getSliderImage(_sliderNumber);
    }
  }

  Future<PdfPageImage> _getPageImage(int pageIndex) =>
      _lock.synchronized<PdfPageImage>(() async {
        if (_pages[pageIndex] != null) {
          return _pages[pageIndex]!;
        }

        final page = await _controller._document!.getPage(pageIndex + 1);

        try {
          _pages[pageIndex] = await widget.renderer(page);
        } finally {
          await page.close();
        }

        return _pages[pageIndex]!;
      });

  Future<void> _getSliderImage(int pageIndex) async {
    final image = await _getUiImage((await _getPageImage(pageIndex)).bytes);
    setState(() {
      _sliderImage = image;
    });
  }

  // Convert PdfPageImage to ui.Image
  Future<ui.Image> _getUiImage(Uint8List byteData) async {
    final codec = await ui.instantiateImageCodec(byteData);
    return (await codec.getNextFrame()).image;
  }

  // Initialize thumbnails
  void _initializeThumbnails() {
    final thumbnailCount = _calculateThumbnailCount(
        ui.PlatformDispatcher.instance.views.first.physicalSize.width,
        _controller._document!.pagesCount);
    _calculateThumbnailPoints(
        _controller._document!.pagesCount, thumbnailCount);
  }

  int _calculateThumbnailCount(double width, int pageCount) {
    return (width / 130).round().clamp(0, pageCount);
  }

  void _calculateThumbnailPoints(int pageCount, int thumbnailCount) {
    setState(() {
      _thumbnailPoints = List<double>.generate(
        thumbnailCount,
        (i) => i * ((pageCount - 1) / (thumbnailCount - 1)),
      );
    });
  }

  // Thumbnail builder
  Widget _buildThumbnail(int index) {
    final pageIndex = _thumbnailPoints![index].toInt();

    // Check if the thumbnail is already loaded
    if (_pages.containsKey(pageIndex) && _pages[pageIndex]?.bytes != null) {
      // If the thumbnail is already loaded, display it
      return Image(image: MemoryImage(_pages[pageIndex]!.bytes));
    } else {
      // If the thumbnail is not loaded, use FutureBuilder to load it
      return FutureBuilder<PdfPageImage?>(
        future: _getPageImage(pageIndex),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CupertinoActivityIndicator();
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else if (snapshot.hasData) {
            // Once the data is available, update _pages and display the image
            _pages[pageIndex] = snapshot.data;
            return Image(image: MemoryImage(snapshot.data!.bytes));
          } else {
            return const Text('No image available');
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builders.builder(
      context,
      widget.builders,
      _controller.loadingState.value,
      _buildLoaded,
      _controller._document,
      _loadingError,
    );
  }

  static Widget _builder(
    BuildContext context,
    PdfViewBuilders builders,
    PdfLoadingState state,
    WidgetBuilder loadedBuilder,
    PdfDocument? document,
    Exception? loadingError,
  ) {
    final Widget content = () {
      switch (state) {
        case PdfLoadingState.loading:
          return KeyedSubtree(
            key: const Key('pdfx.root.loading'),
            child: builders.documentLoaderBuilder?.call(context) ??
                const SizedBox(),
          );
        case PdfLoadingState.error:
          return KeyedSubtree(
            key: const Key('pdfx.root.error'),
            child: builders.errorBuilder?.call(context, loadingError!) ??
                Center(child: Text(loadingError.toString())),
          );
        case PdfLoadingState.success:
          return KeyedSubtree(
            key: Key('pdfx.root.success.${document!.id}'),
            child: loadedBuilder(context),
          );
      }
    }();

    final defaultBuilder = builders as PdfViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return AnimatedSwitcher(
      duration: options.loaderSwitchDuration,
      transitionBuilder: options.transitionBuilder,
      child: content,
    );
  }

  /// Default page builder
  static PhotoViewGalleryPageOptions _pageBuilder(
    BuildContext context,
    Future<PdfPageImage> pageImage,
    int index,
    PdfDocument document,
  ) =>
      PhotoViewGalleryPageOptions(
        imageProvider: PdfPageImageProvider(
          pageImage,
          index,
          document.id,
        ),
        minScale: PhotoViewComputedScale.contained * 1,
        maxScale: PhotoViewComputedScale.contained * 3.0,
        initialScale: PhotoViewComputedScale.contained * 1.0,
        heroAttributes: PhotoViewHeroAttributes(tag: '${document.id}-$index'),
      );

  Widget _buildLoaded(BuildContext context) => Stack(
        children: [
          PhotoViewGallery.builder(
            builder: (context, index) => widget.builders.pageBuilder(
              context,
              _getPageImage(index),
              index,
              _controller._document!,
            ),
            itemCount: _controller._document?.pagesCount ?? 0,
            loadingBuilder: (_, __) =>
                widget.builders.pageLoaderBuilder?.call(context) ??
                const SizedBox(),
            backgroundDecoration: widget.backgroundDecoration,
            pageController: _controller._pageController,
            onPageChanged: (index) {
              setState(() {
                _getSliderImage(index);
                _sliderNumber = index;
              });
              final pageNumber = index + 1;
              _controller.pageListenable.value = pageNumber;
              widget.onPageChanged?.call(pageNumber);
            },
            scrollDirection: widget.scrollDirection,
            reverse: widget.reverse,
            scrollPhysics: widget.physics,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 60,
                  width: _thumbnailPoints!.length * 37,
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
                            itemBuilder: (context, index) =>
                                _buildThumbnail(index),
                            itemCount: _thumbnailPoints?.length ?? 0,
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
                            valueIndicatorShape:
                                CustomValueIndicatorShape(verticalOffset: 65),
                          ),
                          child: Slider(
                            value: _sliderNumber.toDouble(),
                            max: widget.controller._document!.pagesCount
                                    .toDouble() -
                                1,
                            min: 0,
                            label: (_sliderNumber + 1).toString(),
                            onChanged: (double value) {
                              final pageNum = value.round();
                              setState(() {
                                _sliderImage = null;
                                _isDragging = true;
                                _sliderNumber = pageNum;
                              });
                              _sliderImageDebouncer.run(
                                () => _getSliderImage(pageNum),
                              );
                            },
                            onChangeEnd: (double value) {
                              widget.controller.jumpToPage(
                                value.round() + 1,
                              );
                              setState(() {
                                _isDragging = false; // <-- Set to false
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          )
        ],
      );
}
