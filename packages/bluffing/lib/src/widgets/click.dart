import 'dart:async';

import 'package:bluffing/src/base/keys.dart';
import 'package:universal_html/html.dart' as html;

import '../build_context.dart';
import 'widget.dart';

class Click extends Widget {
  final String url;
  final WidgetValueBuilder<ClickState> builder;
  final bool newTab;

  Click({
    Key? key,
    this.newTab = false,
    required this.url,
    required this.builder,
  }) : super(
          key: key,
        );

  @override
  FutureOr<html.HtmlElement> renderHtml(BuildContext context) async {
    final result = html.AnchorElement();
    result.className = 'click';

    result.href = context.resolveUrl(url);
    if (newTab) {
      result.target = '_blank';
    }

    final inactive = await builder(context, ClickState.inactive).render(context);
    final active = await builder(context, ClickState.active).render(context);
    final hover = await builder(context, ClickState.hover).render(context);

    inactive.className += ' inactive';
    active.className += ' active';
    hover.className += ' hover';

    result.childNodes.add(inactive);
    result.childNodes.add(active);
    result.childNodes.add(hover);

    return result;
  }
}

enum ClickState {
  inactive,
  hover,
  active,
}
