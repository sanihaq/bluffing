import 'dart:async';

import 'package:bluffing/bluffing.dart';
import 'package:meta/meta.dart';
import 'package:universal_html/html.dart' as html;

typedef WidgetBuilder = Widget? Function(BuildContext context);

typedef WidgetChildBuilder = Widget Function(BuildContext context, Widget child);

typedef WidgetValueBuilder<T> = Widget Function(BuildContext context, T value);

class Builder extends StatelessWidget {
  final WidgetBuilder builder;

  Builder({
    Key? key,
    required this.builder,
  }) : super(
          key: key,
        );

  @override
  FutureOr<Widget>? build(BuildContext context) {
    return builder(context);
  }
}

abstract class InheritedWidget extends StatelessWidget {
  final Widget? child;

  const InheritedWidget({
    Key? key,
    required this.child,
  }) : super(
          key: key,
        );

  @override
  Widget? build(BuildContext context) => child;

  @override
  FutureOr<html.HtmlElement> render(BuildContext context) {
    return super.render(context.withInherited(this));
  }
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget({Key? key}) : super(key: key);

  FutureOr<Widget>? build(BuildContext context);

  @override
  FutureOr<html.HtmlElement> renderHtml(BuildContext context) async {
    final built = await build(context)!;
    return await built.render(context);
  }
}

@immutable
abstract class Widget {
  final Key? key;
  const Widget({this.key});

  FutureOr<html.HtmlElement> render(BuildContext context) async {
    final css = await renderCss(context);
    final html = await renderHtml(context);
    if (this.key != null) {
      final media = MediaQuery.of(context)!;
      html.id = this.key!.className + '-${media.size.index}';
    }
    final key = context.createDefaultKey();
    html.className += (html.className.isEmpty ? '' : ' ') + key.className;
    if (css != null) context.styles[key.className] = css;
    return html;
  }

  FutureOr<html.CssStyleDeclaration>? renderCss(BuildContext context) => null;
  FutureOr<html.HtmlElement> renderHtml(BuildContext context);
}
