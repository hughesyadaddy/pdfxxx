import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:pdfx/src/renderer/web/pdfjs.dart';
import 'package:web/web.dart' as web;

class Page {
  Page({
    required this.id,
    required this.documentId,
    required this.renderer,
  }) : _viewport = renderer.getViewport(PdfjsViewportParams(scale: 1));

  final String? id, documentId;
  final PdfjsPage renderer;
  final PdfjsViewport _viewport;

  int get number => renderer.pageNumber;

  int get width => _viewport.width.toInt();
  int get height => _viewport.height.toInt();

  Map<String, dynamic> get infoMap => {
        'documentId': documentId,
        'id': id,
        'pageNumber': number,
        'width': width,
        'height': height,
      };

  void close() {}

  Future<Data> render({
    required int width,
    required int height,
  }) async {
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    final context = canvas.getContext('2d', {'alpha': false}.jsify())
        as web.CanvasRenderingContext2D;

    final viewport = renderer
        .getViewport(PdfjsViewportParams(scale: width / _viewport.width));

    canvas
      ..height = viewport.height.toInt()
      ..width = viewport.width.toInt();

    final renderContext = PdfjsRenderContext(
      canvasContext: context,
      viewport: viewport,
    );

    await renderer.render(renderContext).promise.toDart;

    // Convert the image to PNG using callback-based toBlob
    final completer = Completer<Uint8List>();

    canvas.toBlob(
      ((web.Blob? blob) {
        if (blob == null) {
          completer.completeError('Failed to create blob');
          return;
        }
        final reader = web.FileReader();
        reader.onload = ((web.Event event) {
          final result = reader.result;
          if (result != null) {
            final arrayBuffer = result as JSArrayBuffer;
            completer.complete(arrayBuffer.toDart.asUint8List());
          }
        }).toJS;
        reader.onerror = ((web.Event event) {
          completer.completeError('Failed to read blob');
        }).toJS;
        reader.readAsArrayBuffer(blob);
      }).toJS,
      'image/png',
    );

    final data = await completer.future;

    return Data(
      width: width,
      height: height,
      data: data,
    );
  }
}

class Data {
  const Data({
    required this.width,
    required this.height,
    required this.data,
  });

  final int? width, height;
  final Uint8List data;

  Map<String, dynamic> get toMap => {
        'width': width,
        'height': height,
        'data': data,
      };
}
