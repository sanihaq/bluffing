import 'package:bluffing/src/widgets/widget.dart';
import 'package:path/path.dart' as path;
import 'package:universal_html/html.dart' as html;

import 'assets.dart';
import 'base/keys.dart';
import 'widgets/media_query.dart';

class BuildContext {
  static int lastKeyIndex = 0;
  final Map<Type, InheritedWidget> _inheritedWidgets = {};
  final Map<String, html.CssStyleDeclaration> styles;
  final Assets? assets;

  BuildContext({
    this.assets,
    Map<String, html.CssStyleDeclaration>? styles,
  }) : styles = styles ?? <String, html.CssStyleDeclaration>{};

  Key createDefaultKey() => Key('_w${lastKeyIndex++}');

  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget?>() {
    assert(
      _inheritedWidgets.containsKey(T),
      'No inherited widget with type $T found in tree',
    );
    return _inheritedWidgets[T] as T?;
  }

  String resolveUrl(String url) {
    if (url.startsWith('asset://')) {
      return path.join(assets!.local.path, url.replaceAll('asset://', ''));
    }

    if (url.startsWith('#')) {
      final media = MediaQuery.of(this)!;
      return url + '-${media.size.index}';
    }

    return url;
  }

  BuildContext withInherited(InheritedWidget widget) {
    final result = BuildContext(
      styles: styles,
      assets: assets,
    );
    result._inheritedWidgets.addAll(_inheritedWidgets);
    result._inheritedWidgets[widget.runtimeType] = widget;
    return result;
  }
}
