import 'dart:async';

import 'package:bluffing/src/base/keys.dart';
import 'package:universal_html/html.dart' as html;

import '../build_context.dart';
import 'widget.dart';

class SizedBox extends Widget {
  final Widget? child;
  final double? width;
  final double? height;

  const SizedBox({
    Key? key,
    this.child,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  FutureOr<html.CssStyleDeclaration> renderCss(BuildContext context) {
    final style = html.DivElement().style;
    if (width != null) style.width = '${width}px';
    if (height != null) style.height = '${height}px';
    style.flexShrink = '0';
    return style;
  }

  @override
  FutureOr<html.HtmlElement> renderHtml(BuildContext context) {
    if (child == null) {
      return html.DivElement();
    }
    return child!.render(context);
  }
}
