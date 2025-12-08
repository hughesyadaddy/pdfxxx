/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// ignore_for_file: public_member_api_docs

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool checkPdfjsLibInstallation() =>
    web.window.hasProperty('pdfjsLib'.toJS).toDart;

@JS('pdfjsLib.getDocument')
external _PDFDocumentLoadingTask _pdfjsGetDocument(JSObject data);

@JS('pdfRenderOptions')
external JSObject get _pdfRenderOptions;

extension type _PDFDocumentLoadingTask._(JSObject _) implements JSObject {
  external JSPromise get promise;
}

Map<String, dynamic> _getParams(Map<String, dynamic> jsParams) {
  final params = <String, dynamic>{
    'cMapUrl': _pdfRenderOptions['cMapUrl'],
    'cMapPacked': _pdfRenderOptions['cMapPacked'],
  }..addAll(jsParams);
  final otherParams = _pdfRenderOptions['params'];
  if (otherParams != null) {
    params.addAll((otherParams as JSObject).dartify() as Map<String, dynamic>);
  }
  return params;
}

Future<PdfjsDocument> _pdfjsGetDocumentJsParams(
  Map<String, dynamic> jsParams,
) => _pdfjsGetDocument(
  _getParams(jsParams).jsify() as JSObject,
).promise.toDart.then((value) => value as PdfjsDocument);

Future<PdfjsDocument> pdfjsGetDocument(String url, {String? password}) =>
    _pdfjsGetDocumentJsParams({'url': url, 'password': password});

Future<PdfjsDocument> pdfjsGetDocumentFromData(
  ByteBuffer data, {
  String? password,
}) => _pdfjsGetDocumentJsParams({
  'data': data.asUint8List().toJS,
  'password': password,
});

extension type PdfjsDocument._(JSObject _) implements JSObject {
  external JSPromise getPage(int pageNumber);

  external int get numPages;

  external void destroy();
}

extension type PdfjsPage._(JSObject _) implements JSObject {
  external PdfjsViewport getViewport(PdfjsViewportParams params);

  /// `viewport` for [PdfjsViewport] and `transform` for
  external PdfjsRender render(PdfjsRenderContext params);

  external int get pageNumber;

  external JSArray<JSNumber> get view;
}

extension type PdfjsViewportParams._(JSObject _) implements JSObject {
  external factory PdfjsViewportParams({
    double scale,
    int rotation, // 0, 90, 180, 270
    double offsetX,
    double offsetY,
    bool dontFlip,
  });

  external double get scale;
  external set scale(double scale);

  external int get rotation;
  external set rotation(int rotation);

  external double get offsetX;
  external set offsetX(double offsetX);

  external double get offsetY;
  external set offsetY(double offsetY);

  external bool get dontFlip;
  external set dontFlip(bool dontFlip);
}

extension type PdfjsViewport._(JSObject _) implements JSObject {
  external JSArray<JSNumber> get viewBox;
  external set viewBox(JSArray<JSNumber> viewBox);

  external double get scale;
  external set scale(double scale);

  /// 0, 90, 180, 270
  external int get rotation;
  external set rotation(int rotation);

  external double get offsetX;
  external set offsetX(double offsetX);

  external double get offsetY;
  external set offsetY(double offsetY);

  external bool get dontFlip;
  external set dontFlip(bool dontFlip);

  external double get width;
  external set width(double w);

  external double get height;
  external set height(double h);

  external JSArray<JSNumber>? get transform;
  external set transform(JSArray<JSNumber>? m);
}

extension type PdfjsRenderContext._(JSObject _) implements JSObject {
  external factory PdfjsRenderContext({
    required web.CanvasRenderingContext2D canvasContext,
    required PdfjsViewport viewport,
    String intent,
    bool enableWebGL,
    bool renderInteractiveForms,
    JSArray<JSNumber>? transform,
    JSObject? imageLayer,
    JSObject? canvasFactory,
    JSObject? background,
  });

  external web.CanvasRenderingContext2D get canvasContext;
  external set canvasContext(web.CanvasRenderingContext2D ctx);

  external PdfjsViewport get viewport;
  external set viewport(PdfjsViewport viewport);

  external String get intent;

  /// `display` or `print`
  external set intent(String intent);

  external bool get enableWebGL;
  external set enableWebGL(bool enableWebGL);

  external bool get renderInteractiveForms;
  external set renderInteractiveForms(bool renderInteractiveForms);

  external JSArray<JSNumber>? get transform;
  external set transform(JSArray<JSNumber>? transform);

  external JSObject? get imageLayer;
  external set imageLayer(JSObject? imageLayer);

  external JSObject? get canvasFactory;
  external set canvasFactory(JSObject? canvasFactory);

  external JSObject? get background;
  external set background(JSObject? background);
}

extension type PdfjsRender._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> get promise;
}
