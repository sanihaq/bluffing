// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'color.dart';
import 'edge_insets.dart';
import 'hash_values.dart';
import 'lerp.dart';

/// A side of a border of a box.
///
/// A [Border] consists of four [BorderSide] objects: [Border.top],
/// [Border.left], [Border.right], and [Border.bottom].
///
/// Note that setting [BorderSide.width] to 0.0 will result in hairline
/// rendering. A more involved explanation is present in [BorderSide.width].
///
/// {@tool sample}
///
/// This sample shows how [BorderSide] objects can be used in a [Container], via
/// a [BoxDecoration] and a [Border], to decorate some [Text]. In this example,
/// the text has a thick bar above it that is light blue, and a thick bar below
/// it that is a darker shade of blue.
///
/// ```dart
/// Container(
///   padding: EdgeInsets.all(8.0),
///   decoration: BoxDecoration(
///     border: Border(
///       top: BorderSide(width: 16.0, color: Colors.lightBlue.shade50),
///       bottom: BorderSide(width: 16.0, color: Colors.lightBlue.shade900),
///     ),
///   ),
///   child: Text('Flutter in the sky', textAlign: TextAlign.center),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [Border], which uses [BorderSide] objects to represent its sides.
///  * [BoxDecoration], which optionally takes a [Border] object.
///  * [TableBorder], which is similar to [Border] but has two more sides
///    ([TableBorder.horizontalInside] and [TableBorder.verticalInside]), both
///    of which are also [BorderSide] objects.
@immutable
class BorderSide {
  /// A hairline black border that is not rendered.
  static const BorderSide none = BorderSide(width: 0.0, style: BorderStyle.none);

  /// The color of this side of the border.
  final Color color;

  /// The width of this side of the border, in logical pixels.
  ///
  /// Setting width to 0.0 will result in a hairline border. This means that
  /// the border will have the width of one physical pixel. Also, hairline
  /// rendering takes shortcuts when the path overlaps a pixel more than once.
  /// This means that it will render faster than otherwise, but it might
  /// double-hit pixels, giving it a slightly darker/lighter result.
  ///
  /// To omit the border entirely, set the [style] to [BorderStyle.none].
  final double width;

  /// The style of this side of the border.
  ///
  /// To omit a side, set [style] to [BorderStyle.none]. This skips
  /// painting the border, but the border still has a [width].
  final BorderStyle style;

  /// Creates the side of a border.
  ///
  /// By default, the border is 1.0 logical pixels wide and solid black.
  const BorderSide({
    this.color = const Color(0xFF000000),
    this.width = 1.0,
    this.style = BorderStyle.solid,
  });

  @override
  int get hashCode => hashValues(color, width, style);

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    final BorderSide typedOther = other;
    return color == typedOther.color && width == typedOther.width && style == typedOther.style;
  }

  /// Creates a copy of this border but with the given fields replaced with the new values.
  BorderSide copyWith({
    Color? color,
    double? width,
    BorderStyle? style,
  }) {
    assert(width == null || width >= 0.0);
    return BorderSide(
      color: color ?? this.color,
      width: width ?? this.width,
      style: style ?? this.style,
    );
  }

  /// Creates a copy of this border side description but with the width scaled
  /// by the factor `t`.
  ///
  /// The `t` argument represents the multiplicand, or the position on the
  /// timeline for an interpolation from nothing to `this`, with 0.0 meaning
  /// that the object returned should be the nil variant of this object, 1.0
  /// meaning that no change should be applied, returning `this` (or something
  /// equivalent to `this`), and other values meaning that the object should be
  /// multiplied by `t`. Negative values are treated like zero.
  ///
  /// Since a zero width is normally painted as a hairline width rather than no
  /// border at all, the zero factor is special-cased to instead change the
  /// style to [BorderStyle.none].
  ///
  /// Values for `t` are usually obtained from an [Animation<double>], such as
  /// an [AnimationController].
  BorderSide scale(double t) {
    return BorderSide(
      color: color,
      width: math.max(0.0, width * t),
      style: t <= 0.0 ? BorderStyle.none : style,
    );
  }

  @override
  String toString() => '$runtimeType($color, ${width.toStringAsFixed(1)}, $style)';

  /// Whether the two given [BorderSide]s can be merged using [
  /// BorderSide.merge].
  ///
  /// Two sides can be merged if one or both are zero-width with
  /// [BorderStyle.none], or if they both have the same color and style.
  ///
  /// The arguments must not be null.
  static bool canMerge(BorderSide a, BorderSide b) {
    if ((a.style == BorderStyle.none && a.width == 0.0) ||
        (b.style == BorderStyle.none && b.width == 0.0)) return true;
    return a.style == b.style && a.color == b.color;
  }

  /// Linearly interpolate between two border sides.
  ///
  /// The arguments must not be null.
  ///
  /// {@macro dart.ui.shadow.lerp}
  static BorderSide lerp(BorderSide a, BorderSide b, double t) {
    if (t == 0.0) return a;
    if (t == 1.0) return b;
    final width = lerpDouble(a.width, b.width, t)!;
    if (width < 0.0) return BorderSide.none;
    if (a.style == b.style) {
      return BorderSide(
        color: Color.lerp(a.color, b.color, t)!,
        width: width,
        style: a.style, // == b.style
      );
    }
    Color? colorA, colorB;
    switch (a.style) {
      case BorderStyle.solid:
        colorA = a.color;
        break;
      case BorderStyle.none:
        colorA = a.color.withAlpha(0x00);
        break;
    }
    switch (b.style) {
      case BorderStyle.solid:
        colorB = b.color;
        break;
      case BorderStyle.none:
        colorB = b.color.withAlpha(0x00);
        break;
    }
    return BorderSide(
      color: Color.lerp(colorA, colorB, t)!,
      width: width,
      style: BorderStyle.solid,
    );
  }

  /// Creates a [BorderSide] that represents the addition of the two given
  /// [BorderSide]s.
  ///
  /// It is only valid to call this if [canMerge] returns true for the two
  /// sides.
  ///
  /// If one of the sides is zero-width with [BorderStyle.none], then the other
  /// side is return as-is. If both of the sides are zero-width with
  /// [BorderStyle.none], then [BorderSide.zero] is returned.
  ///
  /// The arguments must not be null.
  static BorderSide merge(BorderSide a, BorderSide b) {
    assert(canMerge(a, b));
    final bool aIsNone = a.style == BorderStyle.none && a.width == 0.0;
    final bool bIsNone = b.style == BorderStyle.none && b.width == 0.0;
    if (aIsNone && bIsNone) return BorderSide.none;
    if (aIsNone) return b;
    if (bIsNone) return a;
    assert(a.color == b.color);
    assert(a.style == b.style);
    return BorderSide(
      color: a.color, // == b.color
      width: a.width + b.width,
      style: a.style, // == b.style
    );
  }
}

/// The style of line to draw for a [BorderSide] in a [Border].
enum BorderStyle {
  /// Skip the border.
  none,

  /// Draw the border as a solid line.
  solid,

  // if you add more, think about how they will lerp
}

/// Base class for shape outlines.
///
/// This class handles how to add multiple borders together. Subclasses define
/// various shapes, like circles ([CircleBorder]), rounded rectangles
/// ([RoundedRectangleBorder]), continuous rectangles
/// ([ContinuousRectangleBorder]), or beveled rectangles
/// ([BeveledRectangleBorder]).
///
/// See also:
///
///  * [ShapeDecoration], which can be used with [DecoratedBox] to show a shape.
///  * [Material] (and many other widgets in the Material library), which takes
///    a [ShapeBorder] to define its shape.
///  * [NotchedShape], which describes a shape with a hole in it.
@immutable
abstract class ShapeBorder {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const ShapeBorder();

  /// The widths of the sides of this border represented as an [EdgeInsets].
  ///
  /// Specifically, this is the amount by which a rectangle should be inset so
  /// as to avoid painting over any important part of the border. It is the
  /// amount by which additional borders will be inset before they are drawn.
  ///
  /// This can be used, for example, with a [Padding] widget to inset a box by
  /// the size of these borders.
  ///
  /// Shapes that have a fixed ratio regardless of the area on which they are
  /// painted, or that change their rendering based on the size they are given
  /// when painting (for instance [CircleBorder]), will not return valid
  /// [dimensions] information because they cannot know their eventual size when
  /// computing their [dimensions].
  EdgeInsetsGeometry get dimensions;

  /// Creates a new border consisting of the two borders on either side of the
  /// operator.
  ///
  /// If the borders belong to classes that know how to add themselves, then
  /// this results in a new border that represents the intelligent addition of
  /// those two borders (see [add]). Otherwise, an object is returned that
  /// merely paints the two borders sequentially, with the left hand operand on
  /// the inside and the right hand operand on the outside.
  ShapeBorder operator +(ShapeBorder other) {
    return add(other) ??
        other.add(this, reversed: true) ??
        _CompoundBorder(<ShapeBorder>[other, this]);
  }

  /// Attempts to create a new object that represents the amalgamation of `this`
  /// border and the `other` border.
  ///
  /// If the type of the other border isn't known, or the given instance cannot
  /// be reasonably added to this instance, then this should return null.
  ///
  /// This method is used by the [operator +] implementation.
  ///
  /// The `reversed` argument is true if this object was the right operand of
  /// the `+` operator, and false if it was the left operand.
  @protected
  ShapeBorder? add(ShapeBorder other, {bool reversed = false}) => null;

  /// Linearly interpolates from another [ShapeBorder] (possibly of another
  /// class) to `this`.
  ///
  /// When implementing this method in subclasses, return null if this class
  /// cannot interpolate from `a`. In that case, [lerp] will try `a`'s [lerpTo]
  /// method instead. If `a` is null, this must not return null.
  ///
  /// The base class implementation handles the case of `a` being null by
  /// deferring to [scale].
  ///
  /// The `t` argument represents position on the timeline, with 0.0 meaning
  /// that the interpolation has not started, returning `a` (or something
  /// equivalent to `a`), 1.0 meaning that the interpolation has finished,
  /// returning `this` (or something equivalent to `this`), and values in
  /// between meaning that the interpolation is at the relevant point on the
  /// timeline between `a` and `this`. The interpolation can be extrapolated
  /// beyond 0.0 and 1.0, so negative values and values greater than 1.0 are
  /// valid (and can easily be generated by curves such as
  /// [Curves.elasticInOut]).
  ///
  /// Values for `t` are usually obtained from an [Animation<double>], such as
  /// an [AnimationController].
  ///
  /// Instead of calling this directly, use [ShapeBorder.lerp].
  @protected
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a == null) return scale(t);
    return null;
  }

  /// Linearly interpolates from `this` to another [ShapeBorder] (possibly of
  /// another class).
  ///
  /// This is called if `b`'s [lerpTo] did not know how to handle this class.
  ///
  /// When implementing this method in subclasses, return null if this class
  /// cannot interpolate from `b`. In that case, [lerp] will apply a default
  /// behavior instead. If `b` is null, this must not return null.
  ///
  /// The base class implementation handles the case of `b` being null by
  /// deferring to [scale].
  ///
  /// The `t` argument represents position on the timeline, with 0.0 meaning
  /// that the interpolation has not started, returning `this` (or something
  /// equivalent to `this`), 1.0 meaning that the interpolation has finished,
  /// returning `b` (or something equivalent to `b`), and values in between
  /// meaning that the interpolation is at the relevant point on the timeline
  /// between `this` and `b`. The interpolation can be extrapolated beyond 0.0
  /// and 1.0, so negative values and values greater than 1.0 are valid (and can
  /// easily be generated by curves such as [Curves.elasticInOut]).
  ///
  /// Values for `t` are usually obtained from an [Animation<double>], such as
  /// an [AnimationController].
  ///
  /// Instead of calling this directly, use [ShapeBorder.lerp].
  @protected
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b == null) return scale(1.0 - t);
    return null;
  }

  /// Creates a copy of this border, scaled by the factor `t`.
  ///
  /// Typically this means scaling the width of the border's side, but it can
  /// also include scaling other artifacts of the border, e.g. the border radius
  /// of a [RoundedRectangleBorder].
  ///
  /// The `t` argument represents the multiplicand, or the position on the
  /// timeline for an interpolation from nothing to `this`, with 0.0 meaning
  /// that the object returned should be the nil variant of this object, 1.0
  /// meaning that no change should be applied, returning `this` (or something
  /// equivalent to `this`), and other values meaning that the object should be
  /// multiplied by `t`. Negative values are allowed but may be meaningless
  /// (they correspond to extrapolating the interpolation from this object to
  /// nothing, and going beyond nothing)
  ///
  /// Values for `t` are usually obtained from an [Animation<double>], such as
  /// an [AnimationController].
  ///
  /// See also:
  ///
  ///  * [BorderSide.scale], which most [ShapeBorder] subclasses defer to for
  ///    the actual computation.
  ShapeBorder scale(double t);

  @override
  String toString() {
    return '$runtimeType()';
  }

  /// Linearly interpolates between two [ShapeBorder]s.
  ///
  /// This defers to `b`'s [lerpTo] function if `b` is not null. If `b` is
  /// null or if its [lerpTo] returns null, it uses `a`'s [lerpFrom]
  /// function instead. If both return null, it returns `a` before `t=0.5`
  /// and `b` after `t=0.5`.
  ///
  /// {@macro dart.ui.shadow.lerp}
  static ShapeBorder lerp(ShapeBorder a, ShapeBorder b, double t) {
    ShapeBorder? result;
    result = b.lerpFrom(a, t);
    if (result == null) result = a.lerpTo(b, t);
    return result ?? (t < 0.5 ? a : b);
  }
}

/// Represents the addition of two otherwise-incompatible borders.
///
/// The borders are listed from the outside to the inside.
class _CompoundBorder extends ShapeBorder {
  final List<ShapeBorder> borders;

  _CompoundBorder(this.borders)
      : assert(borders.length >= 2),
        assert(!borders.any((ShapeBorder border) => border is _CompoundBorder));

  @override
  EdgeInsetsGeometry get dimensions {
    return borders.fold<EdgeInsetsGeometry>(
      EdgeInsets.zero,
      (EdgeInsetsGeometry previousValue, ShapeBorder border) {
        return previousValue.add(border.dimensions);
      },
    );
  }

  @override
  int get hashCode => hashList(borders);

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    final _CompoundBorder typedOther = other;
    if (borders == typedOther.borders) return true;
    if (borders.length != typedOther.borders.length) return false;
    for (int index = 0; index < borders.length; index += 1) {
      if (borders[index] != typedOther.borders[index]) return false;
    }
    return true;
  }

  @override
  ShapeBorder add(ShapeBorder other, {bool reversed = false}) {
    // This wraps the list of borders with "other", or, if "reversed" is true,
    // wraps "other" with the list of borders.
    // If "reversed" is false, "other" should end up being at the start of the
    // list, otherwise, if "reversed" is true, it should end up at the end.
    // First, see if we can merge the new adjacent borders.
    if (other is! _CompoundBorder) {
      // Here, "ours" is the border at the side where we're adding the new
      // border, and "merged" is the result of attempting to merge it with the
      // new border. If it's null, it couldn't be merged.
      final ShapeBorder ours = reversed ? borders.last : borders.first;
      final ShapeBorder? merged =
          ours.add(other, reversed: reversed) ?? other.add(ours, reversed: !reversed);
      if (merged != null) {
        final List<ShapeBorder> result = <ShapeBorder>[...borders];
        result[reversed ? result.length - 1 : 0] = merged;
        return _CompoundBorder(result);
      }
    }
    // We can't, so fall back to just adding the new border to the list.
    final List<ShapeBorder> mergedBorders = <ShapeBorder>[
      if (reversed) ...borders,
      if (other is _CompoundBorder) ...other.borders else other,
      if (!reversed) ...borders,
    ];
    return _CompoundBorder(mergedBorders);
  }

  @override
  ShapeBorder lerpFrom(covariant ShapeBorder a, double t) {
    return _CompoundBorder.lerp(a, this, t);
  }

  @override
  ShapeBorder lerpTo(covariant ShapeBorder b, double t) {
    return _CompoundBorder.lerp(this, b, t);
  }

  @override
  ShapeBorder scale(double t) {
    return _CompoundBorder(
        borders.map<ShapeBorder>((ShapeBorder border) => border.scale(t)).toList());
  }

  @override
  String toString() {
    // We list them in reverse order because when adding two borders they end up
    // in the list in the opposite order of what the source looks like: a + b =>
    // [b, a]. We do this to make the painting code more optimal, and most of
    // the rest of the code doesn't care, except toString() (for debugging).
    return borders.reversed.map<String>((ShapeBorder border) => border.toString()).join(' + ');
  }

  static _CompoundBorder lerp(ShapeBorder a, ShapeBorder b, double t) {
    assert(a is _CompoundBorder ||
        b is _CompoundBorder); // Not really necessary, but all call sites currently intend this.
    final List<ShapeBorder> aList = a is _CompoundBorder ? a.borders : <ShapeBorder>[a];
    final List<ShapeBorder> bList = b is _CompoundBorder ? b.borders : <ShapeBorder>[b];
    final List<ShapeBorder> results = <ShapeBorder>[];
    final int length = math.max(aList.length, bList.length);
    for (int index = 0; index < length; index += 1) {
      final ShapeBorder? localA = index < aList.length ? aList[index] : null;
      final ShapeBorder? localB = index < bList.length ? bList[index] : null;
      if (localA != null && localB != null) {
        final ShapeBorder? localResult = localA.lerpTo(localB, t) ?? localB.lerpFrom(localA, t);
        if (localResult != null) {
          results.add(localResult);
          continue;
        }
      }
      // If we're changing from one shape to another, make sure the shape that is coming in
      // is inserted before the shape that is going away, so that the outer path changes to
      // the new border earlier rather than later. (This affects, among other things, where
      // the ShapeDecoration class puts its background.)
      if (localB != null) results.add(localB.scale(t));
      if (localA != null) results.add(localA.scale(1.0 - t));
    }
    return _CompoundBorder(results);
  }
}
