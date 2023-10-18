import 'dart:async';

import 'package:bluffing/bluffing.dart';
import 'package:universal_html/html.dart' as html;

class Image extends Widget {
  final ImageProvider image;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final String? semanticsLabel;

  const Image({
    Key? key,
    this.fit = BoxFit.cover,
    required this.image,
    this.width,
    this.height,
    this.semanticsLabel,
  }) : super(key: key);

  Image.asset(
    String name, {
    Key? key,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    String? semanticsLabel,
  }) : this(
          key: key,
          fit: fit,
          width: width,
          height: height,
          semanticsLabel: semanticsLabel,
          image: ImageProvider.asset(name),
        );

  Image.network(
    String url, {
    Key? key,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    String? semanticsLabel,
  }) : this(
          key: key,
          fit: fit,
          width: width,
          height: height,
          semanticsLabel: semanticsLabel,
          image: ImageProvider.network(url),
        );

  @override
  FutureOr<html.CssStyleDeclaration> renderCss(BuildContext context) {
    final style = html.DivElement().style;

    style.display = 'flex';
    if (width != null) style.width = '${width}px';
    if (height != null) style.height = '${height}px';
    if (fit != null) {
      switch (fit) {
        case BoxFit.cover:
          style.objectFit = 'cover';
          break;
        case BoxFit.fill:
          style.objectFit = 'fill';
          break;
        case BoxFit.none:
          style.objectFit = 'none';
          break;
        case BoxFit.scaleDown:
          style.objectFit = 'scale-down';
          break;
        default:
          style.objectFit = 'contain';
          break;
      }
    }

    return style;
  }

  @override
  FutureOr<html.HtmlElement> renderHtml(BuildContext context) {
    final result = html.ImageElement();
    result.src = context.resolveUrl(image.url);
    if (semanticsLabel != null) {
      result.alt = semanticsLabel;
    }
    ;
    return result;
  }
}
