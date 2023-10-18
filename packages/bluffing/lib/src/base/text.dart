// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:bluffing/src/base/color.dart';
import 'package:bluffing/src/base/hash_values.dart';
import 'package:bluffing/src/base/lerp.dart';
import 'package:bluffing/src/base/locale.dart';

const String _kEllipsis = '\u2026';

// If we actually run on big endian machines, we'll need to do something smarter
// here. We don't use [Endian.Host] because it's not a compile-time
// constant and can't propagate into the set/get calls.
const Endian _kFakeHostEndian = Endian.little;

// This encoding must match the C++ version ParagraphBuilder::build.
//
// The encoded array buffer has 6 elements.
//
//  - Element 0: A bit mask indicating which fields are non-null.
//    Bit 0 is unused. Bits 1-n are set if the corresponding index in the
//    encoded array is non-null.  The remaining bits represent fields that
//    are passed separately from the array.
//
//  - Element 1: The enum index of the |textAlign|.
//
//  - Element 2: The enum index of the |textDirection|.
//
//  - Element 3: The index of the |fontWeight|.
//
//  - Element 4: The enum index of the |fontStyle|.
//
//  - Element 5: The value of |maxLines|.
//
Int32List _encodeParagraphStyle(
  TextAlign? textAlign,
  TextDirection? textDirection,
  int? maxLines,
  String? fontFamily,
  double? fontSize,
  double? height,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  StrutStyle? strutStyle,
  String? ellipsis,
  Locale? locale,
) {
  final Int32List result = Int32List(6); // also update paragraph_builder.cc
  if (textAlign != null) {
    result[0] |= 1 << 1;
    result[1] = textAlign.index;
  }
  if (textDirection != null) {
    result[0] |= 1 << 2;
    result[2] = textDirection.index;
  }
  if (fontWeight != null) {
    result[0] |= 1 << 3;
    result[3] = fontWeight.index;
  }
  if (fontStyle != null) {
    result[0] |= 1 << 4;
    result[4] = fontStyle.index;
  }
  if (maxLines != null) {
    result[0] |= 1 << 5;
    result[5] = maxLines;
  }
  if (fontFamily != null) {
    result[0] |= 1 << 6;
    // Passed separately to native.
  }
  if (fontSize != null) {
    result[0] |= 1 << 7;
    // Passed separately to native.
  }
  if (height != null) {
    result[0] |= 1 << 8;
    // Passed separately to native.
  }
  if (strutStyle != null) {
    result[0] |= 1 << 9;
    // Passed separately to native.
  }
  if (ellipsis != null) {
    result[0] |= 1 << 10;
    // Passed separately to native.
  }
  if (locale != null) {
    result[0] |= 1 << 11;
    // Passed separately to native.
  }
  return result;
}

// Serialize strut properties into ByteData. This encoding errs towards
// compactness. The first 8 bits is a bitmask that records which properties
// are null. The rest of the values are encoded in the same order encountered
// in the bitmask. The final returned value truncates any unused bytes
// at the end.
//
// We serialize this more thoroughly than ParagraphStyle because it is
// much more likely that the strut is empty/null and we wish to add
// minimal overhead for non-strut cases.
ByteData _encodeStrut(
    String? fontFamily,
    List<String>? fontFamilyFallback,
    double? fontSize,
    double? height,
    double? leading,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    bool? forceStrutHeight) {
  if (fontFamily == null &&
      fontSize == null &&
      height == null &&
      leading == null &&
      fontWeight == null &&
      fontStyle == null &&
      forceStrutHeight == null) return ByteData(0);

  final ByteData data = ByteData(15); // Max size is 15 bytes
  int bitmask = 0; // 8 bit mask
  int byteCount = 1;
  if (fontWeight != null) {
    bitmask |= 1 << 0;
    data.setInt8(byteCount, fontWeight.index);
    byteCount += 1;
  }
  if (fontStyle != null) {
    bitmask |= 1 << 1;
    data.setInt8(byteCount, fontStyle.index);
    byteCount += 1;
  }
  if (fontFamily != null || (fontFamilyFallback != null && fontFamilyFallback.isNotEmpty)) {
    bitmask |= 1 << 2;
    // passed separately to native
  }
  if (fontSize != null) {
    bitmask |= 1 << 3;
    data.setFloat32(byteCount, fontSize, _kFakeHostEndian);
    byteCount += 4;
  }
  if (height != null) {
    bitmask |= 1 << 4;
    data.setFloat32(byteCount, height, _kFakeHostEndian);
    byteCount += 4;
  }
  if (leading != null) {
    bitmask |= 1 << 5;
    data.setFloat32(byteCount, leading, _kFakeHostEndian);
    byteCount += 4;
  }
  if (forceStrutHeight != null) {
    bitmask |= 1 << 6;
    // We store this boolean directly in the bitmask since there is
    // extra space in the 16 bit int.
    bitmask |= (forceStrutHeight ? 1 : 0) << 7;
  }

  data.setInt8(0, bitmask);

  return ByteData.view(data.buffer, 0, byteCount);
}

// This encoding must match the C++ version of ParagraphBuilder::pushStyle.
//
// The encoded array buffer has 8 elements.
//
//  - Element 0: A bit field where the ith bit indicates whether the ith element
//    has a non-null value. Bits 8 to 12 indicate whether |fontFamily|,
//    |fontSize|, |letterSpacing|, |wordSpacing|, and |height| are non-null,
//    respectively. Bit 0 is unused.
//
//  - Element 1: The |color| in ARGB with 8 bits per channel.
//
//  - Element 2: A bit field indicating which text decorations are present in
//    the |textDecoration| list. The ith bit is set if there's a TextDecoration
//    with enum index i in the list.
//
//  - Element 3: The |decorationColor| in ARGB with 8 bits per channel.
//
//  - Element 4: The bit field of the |decorationStyle|.
//
//  - Element 5: The index of the |fontWeight|.
//
//  - Element 6: The enum index of the |fontStyle|.
//
//  - Element 7: The enum index of the |textBaseline|.
//
Int32List _encodeTextStyle(
  Color color,
  TextDecoration decoration,
  Color decorationColor,
  TextDecorationStyle decorationStyle,
  double decorationThickness,
  FontWeight fontWeight,
  FontStyle fontStyle,
  TextBaseline textBaseline,
  String fontFamily,
  List<String> fontFamilyFallback,
  double fontSize,
  double letterSpacing,
  double wordSpacing,
  double height,
  Locale locale,
  List<FontFeature> fontFeatures,
) {
  final Int32List result = Int32List(8);
  result[0] |= 1 << 1;
  result[1] = color.value;
  result[0] |= 1 << 2;
  result[2] = decoration._mask;
  result[0] |= 1 << 3;
  result[3] = decorationColor.value;
  result[0] |= 1 << 4;
  result[4] = decorationStyle.index;
  result[0] |= 1 << 5;
  result[5] = fontWeight.index;
  result[0] |= 1 << 6;
  result[6] = fontStyle.index;
  result[0] |= 1 << 7;
  result[7] = textBaseline.index;
  result[0] |= 1 << 8;
  if ((fontFamilyFallback.isNotEmpty)) {
    result[0] |= 1 << 9;
    // Passed separately to native.
  }
  result[0] |= 1 << 10;
  // Passed separately to native.
  result[0] |= 1 << 11;
  // Passed separately to native.
  result[0] |= 1 << 12;
  // Passed separately to native.
  result[0] |= 1 << 13;
  // Passed separately to native.
  result[0] |= 1 << 14;
  // Passed separately to native.
  result[0] |= 1 << 18;
  // Passed separately to native.
  return result;
}

/// Determines if lists [a] and [b] are deep equivalent.
///
/// Returns true if the lists are both null, or if they are both non-null, have
/// the same length, and contain the same elements in the same order. Returns
/// false otherwise.
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Defines various ways to vertically bound the boxes returned by
/// [Paragraph.getBoxesForRange].
enum BoxHeightStyle {
  /// Provide tight bounding boxes that fit heights per run. This style may result
  /// in uneven bounding boxes that do not nicely connect with adjacent boxes.
  tight,

  /// The height of the boxes will be the maximum height of all runs in the
  /// line. All boxes in the same line will be the same height.
  ///
  /// This does not guarantee that the boxes will cover the entire vertical height of the line
  /// when there is additional line spacing.
  ///
  /// See [RectHeightStyle.includeLineSpacingTop], [RectHeightStyle.includeLineSpacingMiddle],
  /// and [RectHeightStyle.includeLineSpacingBottom] for styles that will cover
  /// the entire line.
  max,

  /// Extends the top and bottom edge of the bounds to fully cover any line
  /// spacing.
  ///
  /// The top and bottom of each box will cover half of the
  /// space above and half of the space below the line.
  ///
  /// {@template flutter.dart:ui.boxHeightStyle.includeLineSpacing}
  /// The top edge of each line should be the same as the bottom edge
  /// of the line above. There should be no gaps in vertical coverage given any
  /// amount of line spacing. Line spacing is not included above the first line
  /// and below the last line due to no additional space present there.
  /// {@endtemplate}
  includeLineSpacingMiddle,

  /// Extends the top edge of the bounds to fully cover any line spacing.
  ///
  /// The line spacing will be added to the top of the box.
  ///
  /// {@macro flutter.dart:ui.rectHeightStyle.includeLineSpacing}
  includeLineSpacingTop,

  /// Extends the bottom edge of the bounds to fully cover any line spacing.
  ///
  /// The line spacing will be added to the bottom of the box.
  ///
  /// {@macro flutter.dart:ui.boxHeightStyle.includeLineSpacing}
  includeLineSpacingBottom,

  /// Calculate box heights based on the metrics of this paragraph's [StrutStyle].
  ///
  /// Boxes based on the strut will have consistent heights throughout the
  /// entire paragraph.  The top edge of each line will align with the bottom
  /// edge of the previous line.  It is possible for glyphs to extend outside
  /// these boxes.
  strut,
}

/// Defines various ways to horizontally bound the boxes returned by
/// [Paragraph.getBoxesForRange].
enum BoxWidthStyle {
  /// Provide tight bounding boxes that fit widths to the runs of each line
  /// independently.
  tight,

  /// Adds up to two additional boxes as needed at the beginning and/or end
  /// of each line so that the widths of the boxes in line are the same width
  /// as the widest line in the paragraph.
  ///
  /// The additional boxes on each line are only added when the relevant box
  /// at the relevant edge of that line does not span the maximum width of
  /// the paragraph.
  max,
}

/// A feature tag and value that affect the selection of glyphs in a font.
///
/// {@tool sample}
///
/// This example shows usage of several OpenType font features, including
/// Small Caps (smcp), old-style figures, fractional ligatures and stylistic
/// sets.
///
/// ```dart
///class TypePage extends StatelessWidget {
///  // The Cardo, Milonga and Raleway Dots fonts can be downloaded from
///  // Google Fonts (https://www.google.com/fonts).
///
///  final titleStyle = TextStyle(
///    fontSize: 18,
///    fontFeatures: [FontFeature.enable('smcp')],
///    color: Colors.blueGrey[600],
///  );
///
///  @override
///  Widget build(BuildContext context) {
///    return Scaffold(
///      body: Center(
///        child: Column(
///          mainAxisAlignment: MainAxisAlignment.center,
///          children: <Widget>[
///            Spacer(flex: 5),
///            Text('regular numbers have their place:', style: titleStyle),
///            Text('The 1972 cup final was a 1-1 draw.',
///                style: TextStyle(
///                  fontFamily: 'Cardo',
///                  fontSize: 24,
///                )),
///            Spacer(),
///            Text('but old-style figures blend well with lower case:',
///                style: titleStyle),
///            Text('The 1972 cup final was a 1-1 draw.',
///                style: TextStyle(
///                    fontFamily: 'Cardo',
///                    fontSize: 24,
///                    fontFeatures: [FontFeature.oldstyleFigures()])),
///            Spacer(),
///            Divider(),
///            Spacer(),
///            Text('fractions look better with a custom ligature:',
///                style: titleStyle),
///            Text('Add 1/2 tsp of flour and stir.',
///                style: TextStyle(
///                    fontFamily: 'Milonga',
///                    fontSize: 24,
///                    fontFeatures: [FontFeature.enable('frac')])),
///            Spacer(),
///            Divider(),
///            Spacer(),
///            Text('multiple stylistic sets in one font:', style: titleStyle),
///            Text('Raleway Dots',
///                style: TextStyle(fontFamily: 'Raleway Dots', fontSize: 48)),
///            Text('Raleway Dots',
///                style: TextStyle(
///                  fontFeatures: [FontFeature.stylisticSet(1)],
///                  fontFamily: 'Raleway Dots',
///                  fontSize: 48,
///                )),
///            Spacer(flex: 5),
///          ],
///        ),
///      ),
///    );
///  }
///}
/// ```
/// {@end-tool}
class FontFeature {
  static const int _kEncodedSize = 8;

  /// The tag that identifies the effect of this feature.  Must consist of 4
  /// ASCII characters (typically lowercase letters).
  ///
  /// See <https://docs.microsoft.com/en-us/typography/opentype/spec/featuretags>
  final String feature;

  /// The value assigned to this feature.
  ///
  /// Must be a positive integer.  Many features are Boolean values that accept
  /// values of either 0 (feature is disabled) or 1 (feature is enabled).
  final int value;

  /// Creates a [FontFeature] object, which can be added to a [TextStyle] to
  /// change how the engine selects glyphs when rendering text.
  ///
  /// `feature` is the four-character tag that identifies the feature.
  /// These tags are specified by font formats such as OpenType.
  ///
  /// `value` is the value that the feature will be set to.  The behavior
  /// of the value depends on the specific feature.  Many features are
  /// flags whose value can be 1 (when enabled) or 0 (when disabled).
  ///
  /// See <https://docs.microsoft.com/en-us/typography/opentype/spec/featuretags>
  const FontFeature(this.feature, [this.value = 1])
      : assert(feature.length == 4),
        assert(value >= 0);

  /// Create a [FontFeature] object that disables the feature with the given tag.
  const FontFeature.disable(String feature) : this(feature, 0);

  /// Create a [FontFeature] object that enables the feature with the given tag.
  const FontFeature.enable(String feature) : this(feature, 1);

  /// Use oldstyle figures.
  ///
  /// Some fonts have variants of the figures (e.g. the digit 9) that, when
  /// this feature is enabled, render with descenders under the baseline instead
  /// of being entirely above the baseline.
  ///
  /// This overrides [FontFeature.slashedZero].
  ///
  /// See also:
  ///
  ///  * <https://docs.microsoft.com/en-us/typography/opentype/spec/features_ko#onum>
  const FontFeature.oldstyleFigures()
      : feature = 'onum',
        value = 1;

  /// Use proportional (varying width) figures.
  ///
  /// For fonts that have both proportional and tabular (monospace) figures,
  /// this enables the proportional figures.
  ///
  /// This is mutually exclusive with [FontFeature.tabularFigures].
  ///
  /// The default behavior varies from font to font.
  ///
  /// See also:
  ///
  ///  * <https://docs.microsoft.com/en-us/typography/opentype/spec/features_pt#pnum>
  const FontFeature.proportionalFigures()
      : feature = 'pnum',
        value = 1;

  /// Randomize the alternate forms used in text.
  ///
  /// For example, this can be used with suitably-prepared handwriting fonts to
  /// vary the forms used for each character, so that, for instance, the word
  /// "cross-section" would be rendered with two different "c"s, two different "o"s,
  /// and three different "s"s.
  ///
  /// See also:
  ///
  ///  * <https://docs.microsoft.com/en-us/typography/opentype/spec/features_pt#rand>
  const FontFeature.randomize()
      : feature = 'rand',
        value = 1;

  /// Use the slashed zero.
  ///
  /// Some fonts contain both a circular zero and a zero with a slash. This
  /// enables the use of the latter form.
  ///
  /// This is overridden by [FontFeature.oldstyleFigures].
  ///
  /// See also:
  ///
  ///  * <https://docs.microsoft.com/en-us/typography/opentype/spec/features_uz#zero>
  const FontFeature.slashedZero()
      : feature = 'zero',
        value = 1;

  /// Select a stylistic set.
  ///
  /// Fonts may have up to 20 stylistic sets, numbered 1 through 20.
  ///
  /// See also:
  ///
  ///  * <https://docs.microsoft.com/en-us/typography/opentype/spec/features_pt#ssxx>
  factory FontFeature.stylisticSet(int value) {
    assert(value >= 1);
    assert(value <= 20);
    return FontFeature('ss${value.toString().padLeft(2, "0")}');
  }

  /// Use tabular (monospace) figures.
  ///
  /// For fonts that have both proportional (varying width) and tabular figures,
  /// this enables the tabular figures.
  ///
  /// This is mutually exclusive with [FontFeature.proportionalFigures].
  ///
  /// The default behavior varies from font to font.
  ///
  /// See also:
  ///
  ///  * <https://docs.microsoft.com/en-us/typography/opentype/spec/features_pt#tnum>
  const FontFeature.tabularFigures()
      : feature = 'tnum',
        value = 1;

  @override
  int get hashCode => hashValues(feature, value);

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    final FontFeature typedOther = other;
    return feature == typedOther.feature && value == typedOther.value;
  }

  @override
  String toString() => 'FontFeature($feature, $value)';

  void _encode(ByteData byteData) {
    assert(feature.codeUnits.every((int c) => c >= 0x20 && c <= 0x7F));
    for (int i = 0; i < 4; i++) {
      byteData.setUint8(i, feature.codeUnitAt(i));
    }
    byteData.setInt32(4, value, _kFakeHostEndian);
  }
}

/// Whether to slant the glyphs in the font
enum FontStyle {
  /// Use the upright glyphs
  normal,

  /// Use glyphs designed for slanting
  italic,
}

/// The thickness of the glyphs used to draw the text
class FontWeight {
  /// Thin, the least thick
  static const FontWeight w100 = FontWeight._(0);

  /// Extra-light
  static const FontWeight w200 = FontWeight._(1);

  /// Light
  static const FontWeight w300 = FontWeight._(2);

  /// Normal / regular / plain
  static const FontWeight w400 = FontWeight._(3);

  /// Medium
  static const FontWeight w500 = FontWeight._(4);

  /// Semi-bold
  static const FontWeight w600 = FontWeight._(5);

  /// Bold
  static const FontWeight w700 = FontWeight._(6);

  /// Extra-bold
  static const FontWeight w800 = FontWeight._(7);

  /// Black, the most thick
  static const FontWeight w900 = FontWeight._(8);

  /// The default font weight.
  static const FontWeight normal = w400;

  /// A commonly used font weight that is heavier than normal.
  static const FontWeight bold = w700;

  /// A list of all the font weights.
  static const List<FontWeight> values = <FontWeight>[
    w100,
    w200,
    w300,
    w400,
    w500,
    w600,
    w700,
    w800,
    w900
  ];

  /// The encoded integer value of this font weight.
  final int index;

  const FontWeight._(this.index);

  @override
  String toString() {
    return const <int, String>{
      0: 'FontWeight.w100',
      1: 'FontWeight.w200',
      2: 'FontWeight.w300',
      3: 'FontWeight.w400',
      4: 'FontWeight.w500',
      5: 'FontWeight.w600',
      6: 'FontWeight.w700',
      7: 'FontWeight.w800',
      8: 'FontWeight.w900',
    }[index]!;
  }

  /// Linearly interpolates between two font weights.
  ///
  /// Rather than using fractional weights, the interpolation rounds to the
  /// nearest weight.
  ///
  /// If both `a` and `b` are null, then this method will return null. Otherwise,
  /// any null values for `a` or `b` are interpreted as equivalent to [normal]
  /// (also known as [w400]).
  ///
  /// The `t` argument represents position on the timeline, with 0.0 meaning
  /// that the interpolation has not started, returning `a` (or something
  /// equivalent to `a`), 1.0 meaning that the interpolation has finished,
  /// returning `b` (or something equivalent to `b`), and values in between
  /// meaning that the interpolation is at the relevant point on the timeline
  /// between `a` and `b`. The interpolation can be extrapolated beyond 0.0 and
  /// 1.0, so negative values and values greater than 1.0 are valid (and can
  /// easily be generated by curves such as [Curves.elasticInOut]). The result
  /// is clamped to the range [w100]–[w900].
  ///
  /// Values for `t` are usually obtained from an [Animation<double>], such as
  /// an [AnimationController].
  static FontWeight? lerp(FontWeight? a, FontWeight? b, double t) {
    if (a == null && b == null) return null;
    return values[
        lerpDouble(a?.index ?? normal.index, b?.index ?? normal.index, t)!.round().clamp(0, 8)];
  }
}

/// [LineMetrics] stores the measurements and statistics of a single line in the
/// paragraph.
///
/// The measurements here are for the line as a whole, and represent the maximum
/// extent of the line instead of per-run or per-glyph metrics. For more detailed
/// metrics, see [TextBox] and [Paragraph.getBoxesForRange].
///
/// [LineMetrics] should be obtained directly from the [Paragraph.computeLineMetrics]
/// method.
class LineMetrics {
  /// True if this line ends with an explicit line break (e.g. '\n') or is the end
  /// of the paragraph. False otherwise.
  final bool? hardBreak;

  /// The rise from the [baseline] as calculated from the font and style for this line.
  ///
  /// This is the final computed ascent and can be impacted by the strut, height, scaling,
  /// as well as outlying runs that are very tall.
  ///
  /// The [ascent] is provided as a positive value, even though it is typically defined
  /// in fonts as negative. This is to ensure the signage of operations with these
  /// metrics directly reflects the intended signage of the value. For example,
  /// the y coordinate of the top edge of the line is `baseline - ascent`.
  final double? ascent;

  /// The drop from the [baseline] as calculated from the font and style for this line.
  ///
  /// This is the final computed ascent and can be impacted by the strut, height, scaling,
  /// as well as outlying runs that are very tall.
  ///
  /// The y coordinate of the bottom edge of the line is `baseline + descent`.
  final double? descent;

  /// The rise from the [baseline] as calculated from the font and style for this line
  /// ignoring the [TextStyle.height].
  ///
  /// The [unscaledAscent] is provided as a positive value, even though it is typically
  /// defined in fonts as negative. This is to ensure the signage of operations with
  /// these metrics directly reflects the intended signage of the value.
  final double? unscaledAscent;

  /// Total height of the line from the top edge to the bottom edge.
  ///
  /// This is equivalent to `round(ascent + descent)`. This value is provided
  /// separately due to rounding causing sub-pixel differences from the unrounded
  /// values.
  final double? height;

  /// Width of the line from the left edge of the leftmost glyph to the right
  /// edge of the rightmost glyph.
  ///
  /// This is not the same as the width of the pargraph.
  ///
  /// See also:
  ///
  ///  * [Paragraph.width], the max width passed in during layout.
  ///  * [Paragraph.longestLine], the width of the longest line in the paragraph.
  final double? width;

  /// The x coordinate of left edge of the line.
  ///
  /// The right edge can be obtained with `left + width`.
  final double? left;

  /// The y coordinate of the baseline for this line from the top of the paragraph.
  ///
  /// The bottom edge of the paragraph up to and including this line may be obtained
  /// through `baseline + descent`.
  final double? baseline;

  /// The number of this line in the overall paragraph, with the first line being
  /// index zero.
  ///
  /// For example, the first line is line 0, second line is line 1.
  final int? lineNumber;

  /// Creates a [LineMetrics] object with only the specified values.
  ///
  /// Omitted values will remain null. [Paragraph.computeLineMetrics] produces
  /// fully defined [LineMetrics] with no null values.
  LineMetrics({
    this.hardBreak,
    this.ascent,
    this.descent,
    this.unscaledAscent,
    this.height,
    this.width,
    this.left,
    this.baseline,
    this.lineNumber,
  });

  @pragma('vm:entry-point')
  LineMetrics._(
    this.hardBreak,
    this.ascent,
    this.descent,
    this.unscaledAscent,
    this.height,
    this.width,
    this.left,
    this.baseline,
    this.lineNumber,
  );
}

/// Layout constraints for [Paragraph] objects.
///
/// Instances of this class are typically used with [Paragraph.layout].
///
/// The only constraint that can be specified is the [width]. See the discussion
/// at [width] for more details.
class ParagraphConstraints {
  /// The width the paragraph should use whey computing the positions of glyphs.
  ///
  /// If possible, the paragraph will select a soft line break prior to reaching
  /// this width. If no soft line break is available, the paragraph will select
  /// a hard line break prior to reaching this width. If that would force a line
  /// break without any characters having been placed (i.e. if the next
  /// character to be laid out does not fit within the given width constraint)
  /// then the next character is allowed to overflow the width constraint and a
  /// forced line break is placed after it (even if an explicit line break
  /// follows).
  ///
  /// The width influences how ellipses are applied. See the discussion at
  /// [ParagraphStyle.new] for more details.
  ///
  /// This width is also used to position glyphs according to the [TextAlign]
  /// alignment described in the [ParagraphStyle] used when building the
  /// [Paragraph] with a [ParagraphBuilder].
  final double width;

  /// Creates constraints for laying out a paragraph.
  ///
  /// The [width] argument must not be null.
  const ParagraphConstraints({
    required this.width,
  });

  @override
  int get hashCode => width.hashCode;

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != runtimeType) return false;
    final ParagraphConstraints typedOther = other;
    return typedOther.width == width;
  }

  @override
  String toString() => 'ParagraphConstraints(width: $width)';
}

/// An opaque object that determines the configuration used by
/// [ParagraphBuilder] to position lines within a [Paragraph] of text.
class ParagraphStyle {
  final Int32List _encoded;

  final String? _fontFamily;
  final double? _fontSize;
  final double? _height;
  final StrutStyle? _strutStyle;
  final String? _ellipsis;
  final Locale? _locale;

  /// Creates a new ParagraphStyle object.
  ///
  /// * `textAlign`: The alignment of the text within the lines of the
  ///   paragraph. If the last line is ellipsized (see `ellipsis` below), the
  ///   alignment is applied to that line after it has been truncated but before
  ///   the ellipsis has been added.
  //   See: https://github.com/flutter/flutter/issues/9819
  ///
  /// * `textDirection`: The directionality of the text, left-to-right (e.g.
  ///   Norwegian) or right-to-left (e.g. Hebrew). This controls the overall
  ///   directionality of the paragraph, as well as the meaning of
  ///   [TextAlign.start] and [TextAlign.end] in the `textAlign` field.
  ///
  /// * `maxLines`: The maximum number of lines painted. Lines beyond this
  ///   number are silently dropped. For example, if `maxLines` is 1, then only
  ///   one line is rendered. If `maxLines` is null, but `ellipsis` is not null,
  ///   then lines after the first one that overflows the width constraints are
  ///   dropped. The width constraints are those set in the
  ///   [ParagraphConstraints] object passed to the [Paragraph.layout] method.
  ///
  /// * `fontFamily`: The name of the font family to apply when painting the text,
  ///   in the absence of a `textStyle` being attached to the span.
  ///
  /// * `fontSize`: The fallback size of glyphs (in logical pixels) to
  ///   use when painting the text. This is used when there is no [TextStyle].
  ///
  /// * `height`: The fallback height of the spans as a multiplier of the font
  ///   size. The fallback height is used when no height is provided through
  ///   [TextStyle.height]. Omitting `height` here and in [TextStyle] will allow
  ///   the line height to take the height as defined by the font, which may not
  ///   be exactly the height of the `fontSize`.
  ///
  /// * `fontWeight`: The typeface thickness to use when painting the text
  ///   (e.g., bold).
  ///
  /// * `fontStyle`: The typeface variant to use when drawing the letters (e.g.,
  ///   italics).
  ///
  /// * `strutStyle`: The properties of the strut. Strut defines a set of minimum
  ///   vertical line height related metrics and can be used to obtain more
  ///   advanced line spacing behavior.
  ///
  /// * `ellipsis`: String used to ellipsize overflowing text. If `maxLines` is
  ///   not null, then the `ellipsis`, if any, is applied to the last rendered
  ///   line, if that line overflows the width constraints. If `maxLines` is
  ///   null, then the `ellipsis` is applied to the first line that overflows
  ///   the width constraints, and subsequent lines are dropped. The width
  ///   constraints are those set in the [ParagraphConstraints] object passed to
  ///   the [Paragraph.layout] method. The empty string and the null value are
  ///   considered equivalent and turn off this behavior.
  ///
  /// * `locale`: The locale used to select region-specific glyphs.
  ParagraphStyle({
    TextAlign? textAlign,
    TextDirection? textDirection,
    int? maxLines,
    String? fontFamily,
    double? fontSize,
    double? height,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    StrutStyle? strutStyle,
    String? ellipsis,
    Locale? locale,
  })  : _encoded = _encodeParagraphStyle(
          textAlign,
          textDirection,
          maxLines,
          fontFamily,
          fontSize,
          height,
          fontWeight,
          fontStyle,
          strutStyle,
          ellipsis,
          locale,
        ),
        _fontFamily = fontFamily,
        _fontSize = fontSize,
        _height = height,
        _strutStyle = strutStyle,
        _ellipsis = ellipsis,
        _locale = locale;

  @override
  int get hashCode =>
      hashValues(hashList(_encoded), _fontFamily, _fontSize, _height, _ellipsis, _locale);

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    final ParagraphStyle typedOther = other;
    if (_fontFamily != typedOther._fontFamily ||
        _fontSize != typedOther._fontSize ||
        _height != typedOther._height ||
        _strutStyle != typedOther._strutStyle ||
        _ellipsis != typedOther._ellipsis ||
        _locale != typedOther._locale) return false;
    for (int index = 0; index < _encoded.length; index += 1) {
      if (_encoded[index] != typedOther._encoded[index]) return false;
    }
    return true;
  }

  @override
  String toString() {
    return 'ParagraphStyle('
        'textAlign: ${_encoded[0] & 0x002 == 0x002 ? TextAlign.values[_encoded[1]] : "unspecified"}, '
        'textDirection: ${_encoded[0] & 0x004 == 0x004 ? TextDirection.values[_encoded[2]] : "unspecified"}, '
        'fontWeight: ${_encoded[0] & 0x008 == 0x008 ? FontWeight.values[_encoded[3]] : "unspecified"}, '
        'fontStyle: ${_encoded[0] & 0x010 == 0x010 ? FontStyle.values[_encoded[4]] : "unspecified"}, '
        'maxLines: ${_encoded[0] & 0x020 == 0x020 ? _encoded[5] : "unspecified"}, '
        'fontFamily: ${_encoded[0] & 0x040 == 0x040 ? _fontFamily : "unspecified"}, '
        'fontSize: ${_encoded[0] & 0x080 == 0x080 ? _fontSize : "unspecified"}, '
        'height: ${_encoded[0] & 0x100 == 0x100 ? "${_height}x" : "unspecified"}, '
        'ellipsis: ${_encoded[0] & 0x200 == 0x200 ? "\"$_ellipsis\"" : "unspecified"}, '
        'locale: ${_encoded[0] & 0x400 == 0x400 ? _locale : "unspecified"}'
        ')';
  }
}

/// Where to vertically align the placeholder relative to the surrounding text.
///
/// Used by [ParagraphBuilder.addPlaceholder].
enum PlaceholderAlignment {
  /// Match the baseline of the placeholder with the baseline.
  ///
  /// The [TextBaseline] to use must be specified and non-null when using this
  /// alignment mode.
  baseline,

  /// Align the bottom edge of the placeholder with the baseline such that the
  /// placeholder sits on top of the baseline.
  ///
  /// The [TextBaseline] to use must be specified and non-null when using this
  /// alignment mode.
  aboveBaseline,

  /// Align the top edge of the placeholder with the baseline specified
  /// such that the placeholder hangs below the baseline.
  ///
  /// The [TextBaseline] to use must be specified and non-null when using this
  /// alignment mode.
  belowBaseline,

  /// Align the top edge of the placeholder with the top edge of the text.
  ///
  /// When the placeholder is very tall, the extra space will hang from
  /// the top and extend through the bottom of the line.
  top,

  /// Align the bottom edge of the placeholder with the bottom edge of the text.
  ///
  /// When the placeholder is very tall, the extra space will rise from the
  /// bottom and extend through the top of the line.
  bottom,

  /// Align the middle of the placeholder with the middle of the text.
  ///
  /// When the placeholder is very tall, the extra space will grow equally
  /// from the top and bottom of the line.
  middle,
}

/// See also:
///
///  * [StrutStyle](https://api.flutter.dev/flutter/painting/StrutStyle-class.html), the class in the [painting] library.
///
class StrutStyle {
  final ByteData _encoded; // Most of the data for strut is encoded.

  final String? _fontFamily;
  final List<String>? _fontFamilyFallback;

  /// Creates a new StrutStyle object.
  ///
  /// * `fontFamily`: The name of the font to use when painting the text (e.g.,
  ///   Roboto).
  ///
  /// * `fontFamilyFallback`: An ordered list of font family names that will be
  ///    searched for when the font in `fontFamily` cannot be found.
  ///
  /// * `fontSize`: The size of glyphs (in logical pixels) to use when painting
  ///   the text.
  ///
  /// * `height`: The minimum height of the line boxes, as a multiplier of the
  ///   font size. The lines of the paragraph will be at least
  ///   `(height + leading) * fontSize` tall when `fontSize` is not null. Omitting
  ///   `height` will allow the minimum line height to take the height as defined
  ///   by the font, which may not be exactly the height of the `fontSize`. When
  ///   `fontSize` is null, there is no minimum line height. Tall glyphs due to
  ///   baseline alignment or large [TextStyle.fontSize] may cause the actual line
  ///   height after layout to be taller than specified here. The `fontSize` must
  ///   be provided for this property to take effect.
  ///
  /// * `leading`: The minimum amount of leading between lines as a multiple of
  ///   the font size. `fontSize` must be provided for this property to take effect.
  ///
  /// * `fontWeight`: The typeface thickness to use when painting the text
  ///   (e.g., bold).
  ///
  /// * `fontStyle`: The typeface variant to use when drawing the letters (e.g.,
  ///   italics).
  ///
  /// * `forceStrutHeight`: When true, the paragraph will force all lines to be exactly
  ///   `(height + leading) * fontSize` tall from baseline to baseline.
  ///   [TextStyle] is no longer able to influence the line height, and any tall
  ///   glyphs may overlap with lines above. If a `fontFamily` is specified, the
  ///   total ascent of the first line will be the min of the `Ascent + half-leading`
  ///   of the `fontFamily` and `(height + leading) * fontSize`. Otherwise, it
  ///   will be determined by the Ascent + half-leading of the first text.
  StrutStyle({
    String? fontFamily,
    List<String>? fontFamilyFallback,
    double? fontSize,
    double? height,
    double? leading,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    bool? forceStrutHeight,
  })  : _encoded = _encodeStrut(
          fontFamily,
          fontFamilyFallback,
          fontSize,
          height,
          leading,
          fontWeight,
          fontStyle,
          forceStrutHeight,
        ),
        _fontFamily = fontFamily,
        _fontFamilyFallback = fontFamilyFallback;

  @override
  int get hashCode => hashValues(hashList(_encoded.buffer.asInt8List()), _fontFamily);

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    final StrutStyle typedOther = other;
    if (_fontFamily != typedOther._fontFamily) return false;
    final Int8List encodedList = _encoded.buffer.asInt8List();
    final Int8List otherEncodedList = typedOther._encoded.buffer.asInt8List();
    for (int index = 0; index < _encoded.lengthInBytes; index += 1) {
      if (encodedList[index] != otherEncodedList[index]) return false;
    }
    if (!_listEquals<String>(_fontFamilyFallback, typedOther._fontFamilyFallback)) return false;
    return true;
  }
}

/// A way to disambiguate a [TextPosition] when its offset could match two
/// different locations in the rendered string.
///
/// For example, at an offset where the rendered text wraps, there are two
/// visual positions that the offset could represent: one prior to the line
/// break (at the end of the first line) and one after the line break (at the
/// start of the second line). A text affinity disambiguates between these two
/// cases.
///
/// This affects only line breaks caused by wrapping, not explicit newline
/// characters. For newline characters, the position is fully specified by the
/// offset alone, and there is no ambiguity.
///
/// [TextAffinity] also affects bidirectional text at the interface between LTR
/// and RTL text. Consider the following string, where the lowercase letters
/// will be displayed as LTR and the uppercase letters RTL: "helloHELLO".  When
/// rendered, the string would appear visually as "helloOLLEH".  An offset of 5
/// would be ambiguous without a corresponding [TextAffinity].  Looking at the
/// string in code, the offset represents the position just after the "o" and
/// just before the "H".  When rendered, this offset could be either in the
/// middle of the string to the right of the "o" or at the end of the string to
/// the right of the "H".
enum TextAffinity {
  /// The position has affinity for the upstream side of the text position, i.e.
  /// in the direction of the beginning of the string.
  ///
  /// In the example of an offset at the place where text is wrapping, upstream
  /// indicates the end of the first line.
  ///
  /// In the bidirectional text example "helloHELLO", an offset of 5 with
  /// [TextAffinity] upstream would appear in the middle of the rendered text,
  /// just to the right of the "o". See the definition of [TextAffinity] for the
  /// full example.
  upstream,

  /// The position has affinity for the downstream side of the text position,
  /// i.e. in the direction of the end of the string.
  ///
  /// In the example of an offset at the place where text is wrapping,
  /// downstream indicates the beginning of the second line.
  ///
  /// In the bidirectional text example "helloHELLO", an offset of 5 with
  /// [TextAffinity] downstream would appear at the end of the rendered text,
  /// just to the right of the "H". See the definition of [TextAffinity] for the
  /// full example.
  downstream,
}

/// Whether and how to align text horizontally.
// The order of this enum must match the order of the values in RenderStyleConstants.h's ETextAlign.
enum TextAlign {
  /// Align the text on the left edge of the container.
  left,

  /// Align the text on the right edge of the container.
  right,

  /// Align the text in the center of the container.
  center,

  /// Stretch lines of text that end with a soft line break to fill the width of
  /// the container.
  ///
  /// Lines that end with hard line breaks are aligned towards the [start] edge.
  justify,

  /// Align the text on the leading edge of the container.
  ///
  /// For left-to-right text ([TextDirection.ltr]), this is the left edge.
  ///
  /// For right-to-left text ([TextDirection.rtl]), this is the right edge.
  start,

  /// Align the text on the trailing edge of the container.
  ///
  /// For left-to-right text ([TextDirection.ltr]), this is the right edge.
  ///
  /// For right-to-left text ([TextDirection.rtl]), this is the left edge.
  end,
}

/// A horizontal line used for aligning text.
enum TextBaseline {
  /// The horizontal line used to align the bottom of glyphs for alphabetic characters.
  alphabetic,

  /// The horizontal line used to align ideographic characters.
  ideographic,
}

/// A rectangle enclosing a run of text.
///
/// This is similar to [Rect] but includes an inherent [TextDirection].
@pragma('vm:entry-point')
class TextBox {
  /// The left edge of the text box, irrespective of direction.
  ///
  /// To get the leading edge (which may depend on the [direction]), consider [start].
  final double left;

  /// The top edge of the text box.
  final double top;

  /// The right edge of the text box, irrespective of direction.
  ///
  /// To get the trailing edge (which may depend on the [direction]), consider [end].
  final double right;

  /// The bottom edge of the text box.
  final double bottom;

  /// The direction in which text inside this box flows.
  final TextDirection direction;

  /// Creates an object that describes a box containing text.
  const TextBox.fromLTRBD(
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.direction,
  );

  @pragma('vm:entry-point')
  TextBox._(
    this.left,
    this.top,
    this.right,
    this.bottom,
    int directionIndex,
  ) : direction = TextDirection.values[directionIndex];

  /// The [right] edge of the box for left-to-right text; the [left] edge of the box for right-to-left text.
  ///
  /// See also:
  ///
  ///  * [direction], which specifies the text direction.
  double get end {
    return (direction == TextDirection.ltr) ? right : left;
  }

  @override
  int get hashCode => hashValues(left, top, right, bottom, direction);

  /// The [left] edge of the box for left-to-right text; the [right] edge of the box for right-to-left text.
  ///
  /// See also:
  ///
  ///  * [direction], which specifies the text direction.
  double get start {
    return (direction == TextDirection.ltr) ? left : right;
  }

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    final TextBox typedOther = other;
    return typedOther.left == left &&
        typedOther.top == top &&
        typedOther.right == right &&
        typedOther.bottom == bottom &&
        typedOther.direction == direction;
  }

  @override
  String toString() =>
      'TextBox.fromLTRBD(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, ${right.toStringAsFixed(1)}, ${bottom.toStringAsFixed(1)}, $direction)';
}

/// A linear decoration to draw near the text.
class TextDecoration {
  /// Do not draw a decoration
  static const TextDecoration none = TextDecoration._(0x0);

  /// Draw a line underneath each line of text
  static const TextDecoration underline = TextDecoration._(0x1);

  /// Draw a line above each line of text
  static const TextDecoration overline = TextDecoration._(0x2);

  /// Draw a line through each line of text
  static const TextDecoration lineThrough = TextDecoration._(0x4);

  final int _mask;

  /// Creates a decoration that paints the union of all the given decorations.
  factory TextDecoration.combine(List<TextDecoration> decorations) {
    int mask = 0;
    for (TextDecoration decoration in decorations) mask |= decoration._mask;
    return TextDecoration._(mask);
  }

  const TextDecoration._(this._mask);

  @override
  int get hashCode => _mask.hashCode;

  @override
  bool operator ==(dynamic other) {
    if (other is! TextDecoration) return false;
    final TextDecoration typedOther = other;
    return _mask == typedOther._mask;
  }

  /// Whether this decoration will paint at least as much decoration as the given decoration.
  bool contains(TextDecoration other) {
    return (_mask | other._mask) == _mask;
  }

  @override
  String toString() {
    if (_mask == 0) return 'TextDecoration.none';
    final List<String> values = <String>[];
    if (_mask & underline._mask != 0) values.add('underline');
    if (_mask & overline._mask != 0) values.add('overline');
    if (_mask & lineThrough._mask != 0) values.add('lineThrough');
    if (values.length == 1) return 'TextDecoration.${values[0]}';
    return 'TextDecoration.combine([${values.join(", ")}])';
  }
}

/// The style in which to draw a text decoration
enum TextDecorationStyle {
  /// Draw a solid line
  solid,

  /// Draw two lines
  double,

  /// Draw a dotted line
  dotted,

  /// Draw a dashed line
  dashed,

  /// Draw a sinusoidal line
  wavy
}

/// A direction in which text flows.
///
/// Some languages are written from the left to the right (for example, English,
/// Tamil, or Chinese), while others are written from the right to the left (for
/// example Aramaic, Hebrew, or Urdu). Some are also written in a mixture, for
/// example Arabic is mostly written right-to-left, with numerals written
/// left-to-right.
///
/// The text direction must be provided to APIs that render text or lay out
/// boxes horizontally, so that they can determine which direction to start in:
/// either right-to-left, [TextDirection.rtl]; or left-to-right,
/// [TextDirection.ltr].
///
/// ## Design discussion
///
/// Flutter is designed to address the needs of applications written in any of
/// the world's currently-used languages, whether they use a right-to-left or
/// left-to-right writing direction. Flutter does not support other writing
/// modes, such as vertical text or boustrophedon text, as these are rarely used
/// in computer programs.
///
/// It is common when developing user interface frameworks to pick a default
/// text direction — typically left-to-right, the direction most familiar to the
/// engineers working on the framework — because this simplifies the development
/// of applications on the platform. Unfortunately, this frequently results in
/// the platform having unexpected left-to-right biases or assumptions, as
/// engineers will typically miss places where they need to support
/// right-to-left text. This then results in bugs that only manifest in
/// right-to-left environments.
///
/// In an effort to minimize the extent to which Flutter experiences this
/// category of issues, the lowest levels of the Flutter framework do not have a
/// default text reading direction. Any time a reading direction is necessary,
/// for example when text is to be displayed, or when a
/// writing-direction-dependent value is to be interpreted, the reading
/// direction must be explicitly specified. Where possible, such as in `switch`
/// statements, the right-to-left case is listed first, to avoid the impression
/// that it is an afterthought.
///
/// At the higher levels (specifically starting at the widgets library), an
/// ambient [Directionality] is introduced, which provides a default. Thus, for
/// instance, a [Text] widget in the scope of a [MaterialApp] widget does not
/// need to be given an explicit writing direction. The [Directionality.of]
/// static method can be used to obtain the ambient text direction for a
/// particular [BuildContext].
///
/// ### Known left-to-right biases in Flutter
///
/// Despite the design intent described above, certain left-to-right biases have
/// nonetheless crept into Flutter's design. These include:
///
///  * The [Canvas] origin is at the top left, and the x-axis increases in a
///    left-to-right direction.
///
///  * The default localization in the widgets and material libraries is
///    American English, which is left-to-right.
///
/// ### Visual properties vs directional properties
///
/// Many classes in the Flutter framework are offered in two versions, a
/// visually-oriented variant, and a text-direction-dependent variant. For
/// example, [EdgeInsets] is described in terms of top, left, right, and bottom,
/// while [EdgeInsetsDirectional] is described in terms of top, start, end, and
/// bottom, where start and end correspond to right and left in right-to-left
/// text and left and right in left-to-right text.
///
/// There are distinct use cases for each of these variants.
///
/// Text-direction-dependent variants are useful when developing user interfaces
/// that should "flip" with the text direction. For example, a paragraph of text
/// in English will typically be left-aligned and a quote will be indented from
/// the left, while in Arabic it will be right-aligned and indented from the
/// right. Both of these cases are described by the direction-dependent
/// [TextAlign.start] and [EdgeInsetsDirectional.start].
///
/// In contrast, the visual variants are useful when the text direction is known
/// and not affected by the reading direction. For example, an application
/// giving driving directions might show a "turn left" arrow on the left and a
/// "turn right" arrow on the right — and would do so whether the application
/// was localized to French (left-to-right) or Hebrew (right-to-left).
///
/// In practice, it is also expected that many developers will only be
/// targeting one language, and in that case it may be simpler to think in
/// visual terms.
// The order of this enum must match the order of the values in TextDirection.h's TextDirection.
enum TextDirection {
  /// The text flows from right to left (e.g. Arabic, Hebrew).
  rtl,

  /// The text flows from left to right (e.g., English, French).
  ltr,
}

/// How overflowing text should be handled.
///
/// A [TextOverflow] can be passed to [Text] and [RichText] via their
/// [Text.overflow] and [RichText.overflow] properties respectively.
enum TextOverflow {
  /// Clip the overflowing text to fix its container.
  clip,

  /// Fade the overflowing text to transparent.
  fade,

  /// Use an ellipsis to indicate that the text has overflowed.
  ellipsis,

  /// Render overflowing text outside of its container.
  visible,
}

/// A position in a string of text.
///
/// A TextPosition can be used to locate a position in a string in code (using
/// the [offset] property), and it can also be used to locate the same position
/// visually in a rendered string of text (using [offset] and, when needed to
/// resolve ambiguity, [affinity]).
///
/// The location of an offset in a rendered string is ambiguous in two cases.
/// One happens when rendered text is forced to wrap. In this case, the offset
/// where the wrap occurs could visually appear either at the end of the first
/// line or the beginning of the second line. The second way is with
/// bidirectional text.  An offset at the interface between two different text
/// directions could have one of two locations in the rendered text.
///
/// See the documentation for [TextAffinity] for more information on how
/// TextAffinity disambiguates situations like these.
class TextPosition {
  /// The index of the character that immediately follows the position in the
  /// string representation of the text.
  ///
  /// For example, given the string `'Hello'`, offset 0 represents the cursor
  /// being before the `H`, while offset 5 represents the cursor being just
  /// after the `o`.
  final int offset;

  /// Disambiguates cases where the position in the string given by [offset]
  /// could represent two different visual positions in the rendered text. For
  /// example, this can happen when text is forced to wrap, or when one string
  /// of text is rendered with multiple text directions.
  ///
  /// See the documentation for [TextAffinity] for more information on how
  /// TextAffinity disambiguates situations like these.
  final TextAffinity affinity;

  /// Creates an object representing a particular position in a string.
  ///
  /// The arguments must not be null (so the [offset] argument is required).
  const TextPosition({
    required this.offset,
    this.affinity = TextAffinity.downstream,
  });

  @override
  int get hashCode => hashValues(offset, affinity);

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != runtimeType) return false;
    final TextPosition typedOther = other;
    return typedOther.offset == offset && typedOther.affinity == affinity;
  }

  @override
  String toString() {
    return 'TextPosition(offset: $offset, affinity: $affinity)';
  }
}

/// A range of characters in a string of text.
class TextRange {
  /// A text range that contains nothing and is not in the text.
  static const TextRange empty = TextRange(start: -1, end: -1);

  /// The index of the first character in the range.
  ///
  /// If [start] and [end] are both -1, the text range is empty.
  final int? start;

  /// The next index after the characters in this range.
  ///
  /// If [start] and [end] are both -1, the text range is empty.
  final int? end;

  /// Creates a text range.
  ///
  /// The [start] and [end] arguments must not be null. Both the [start] and
  /// [end] must either be greater than or equal to zero or both exactly -1.
  ///
  /// The text included in the range includes the character at [start], but not
  /// the one at [end].
  ///
  /// Instead of creating an empty text range, consider using the [empty]
  /// constant.
  const TextRange({
    this.start,
    this.end,
  })  : assert(start != null && start >= -1),
        assert(end != null && end >= -1);

  /// A text range that starts and ends at offset.
  ///
  /// The [offset] argument must be non-null and greater than or equal to -1.
  const TextRange.collapsed(int offset)
      : assert(offset >= -1),
        start = offset,
        end = offset;

  @override
  int get hashCode => hashValues(
        start.hashCode,
        end.hashCode,
      );

  /// Whether this range is empty (but still potentially placed inside the text).
  bool get isCollapsed => start == end;

  /// Whether the start of this range precedes the end.
  bool get isNormalized => end! >= start!;

  /// Whether this range represents a valid position in the text.
  bool get isValid => start! >= 0 && end! >= 0;

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (other is! TextRange) return false;
    final TextRange typedOther = other;
    return typedOther.start == start && typedOther.end == end;
  }

  /// The text after this range.
  String textAfter(String text) {
    assert(isNormalized);
    return text.substring(end!);
  }

  /// The text before this range.
  String textBefore(String text) {
    assert(isNormalized);
    return text.substring(0, start);
  }

  /// The text inside this range.
  String textInside(String text) {
    assert(isNormalized);
    return text.substring(start!, end);
  }

  @override
  String toString() => 'TextRange(start: $start, end: $end)';
}

/// An opaque object that determines the size, position, and rendering of text.
///
/// See also:
///
///  * [TextStyle](https://api.flutter.dev/flutter/painting/TextStyle-class.html), the class in the [painting] library.
///
class TextStyle {
  final FontStyle? fontStyle;

  final Color? color;

  final Color? decorationColor;
  final TextDecoration? decoration;
  final TextDecorationStyle? decorationStyle;
  final FontWeight? fontWeight;
  final TextBaseline? textBaseline;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final double? fontSize;
  final double? letterSpacing;
  final double? wordSpacing;
  final double? height;
  final double? decorationThickness;
  final Locale? locale;

  /// Creates a new TextStyle object.
  ///
  /// * `color`: The color to use when painting the text. If this is specified, `foreground` must be null.
  /// * `decoration`: The decorations to paint near the text (e.g., an underline).
  /// * `decorationColor`: The color in which to paint the text decorations.
  /// * `decorationStyle`: The style in which to paint the text decorations (e.g., dashed).
  /// * `decorationThickness`: The thickness of the decoration as a muliplier on the thickness specified by the font.
  /// * `fontWeight`: The typeface thickness to use when painting the text (e.g., bold).
  /// * `fontStyle`: The typeface variant to use when drawing the letters (e.g., italics).
  /// * `fontFamily`: The name of the font to use when painting the text (e.g., Roboto). If a `fontFamilyFallback` is
  ///   provided and `fontFamily` is not, then the first font family in `fontFamilyFallback` will take the position of
  ///   the preferred font family. When a higher priority font cannot be found or does not contain a glyph, a lower
  ///   priority font will be used.
  /// * `fontFamilyFallback`: An ordered list of the names of the fonts to fallback on when a glyph cannot
  ///   be found in a higher priority font. When the `fontFamily` is null, the first font family in this list
  ///   is used as the preferred font. Internally, the 'fontFamily` is concatenated to the front of this list.
  ///   When no font family is provided through 'fontFamilyFallback' (null or empty) or `fontFamily`, then the
  ///   platform default font will be used.
  /// * `fontSize`: The size of glyphs (in logical pixels) to use when painting the text.
  /// * `letterSpacing`: The amount of space (in logical pixels) to add between each letter.
  /// * `wordSpacing`: The amount of space (in logical pixels) to add at each sequence of white-space (i.e. between each word).
  /// * `textBaseline`: The common baseline that should be aligned between this text span and its parent text span, or, for the root text spans, with the line box.
  /// * `height`: The height of this text span, as a multiplier of the font size. Omitting `height` will allow the line height
  ///   to take the height as defined by the font, which may not be exactly the height of the fontSize.
  /// * `locale`: The locale used to select region-specific glyphs.
  /// * `background`: The paint drawn as a background for the text.
  /// * `foreground`: The paint used to draw the text. If this is specified, `color` must be null.
  /// * `fontFeatures`: The font features that should be applied to the text.
  const TextStyle({
    this.color,
    this.decoration,
    this.decorationColor,
    this.decorationStyle,
    this.decorationThickness,
    this.fontWeight,
    this.fontStyle,
    this.textBaseline,
    this.fontFamily,
    this.fontFamilyFallback,
    this.fontSize,
    this.letterSpacing,
    this.wordSpacing,
    this.height,
    this.locale,
  });
  // : assert(
  //           color == null,
  //           'Cannot provide both a color and a foreground\n'
  //           'The color argument is just a shorthand for "foreground: Paint()..color = color".');
  @override
  int get hashCode => hashValues(
      color,
      fontWeight,
      fontStyle,
      decorationColor,
      decoration,
      decorationStyle,
      fontFamily,
      fontFamilyFallback,
      fontSize,
      letterSpacing,
      wordSpacing,
      height,
      locale,
      decorationThickness);

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (other is! TextStyle) return false;
    final TextStyle typedOther = other;
    if (fontFamily != typedOther.fontFamily ||
        fontSize != typedOther.fontSize ||
        letterSpacing != typedOther.letterSpacing ||
        wordSpacing != typedOther.wordSpacing ||
        height != typedOther.height ||
        decorationThickness != typedOther.decorationThickness ||
        locale != typedOther.locale ||
        color != typedOther.color ||
        fontStyle != typedOther.fontStyle ||
        decorationColor != typedOther.decorationColor ||
        decoration != typedOther.decoration ||
        decorationStyle != typedOther.decorationStyle ||
        fontWeight != typedOther.fontWeight) return false;

    if (!_listEquals<String>(fontFamilyFallback, typedOther.fontFamilyFallback)) return false;
    return true;
  }

  TextStyle merge(
    TextStyle other,
  ) =>
      TextStyle(
        fontFamily: other.fontFamily ?? this.fontFamily,
        color: other.color ?? this.color,
        decoration: other.decoration ?? this.decoration,
        decorationColor: other.decorationColor ?? this.decorationColor,
        decorationStyle: other.decorationStyle ?? this.decorationStyle,
        decorationThickness: other.decorationThickness ?? this.decorationThickness,
        fontFamilyFallback: other.fontFamilyFallback ?? this.fontFamilyFallback,
        fontSize: other.fontSize ?? this.fontSize,
        fontStyle: other.fontStyle ?? this.fontStyle,
        fontWeight: other.fontWeight ?? this.fontWeight,
        height: other.height ?? this.height,
        letterSpacing: other.letterSpacing ?? this.letterSpacing,
        locale: other.locale ?? this.locale,
        textBaseline: other.textBaseline ?? this.textBaseline,
        wordSpacing: other.wordSpacing ?? this.wordSpacing,
      );

  @override
  String toString() {
    return 'TextStyle('
        'color: ${color?.toString() ?? "unspecified"}, '
        'decoration: ${decoration?.toString() ?? "unspecified"}, '
        'decorationColor: ${decorationColor ?? "unspecified"}, '
        'decorationStyle: ${decorationStyle ?? "unspecified"}, '
        // The decorationThickness is not in encoded order in order to keep it near the other decoration properties.
        'decorationThickness: ${decorationThickness ?? "unspecified"}, '
        'fontWeight: ${fontWeight ?? "unspecified"}, '
        'fontStyle: ${fontStyle ?? "unspecified"}, '
        'textBaseline: ${textBaseline ?? "unspecified"}, '
        'fontFamily: ${fontFamily ?? "unspecified"}, '
        'fontFamilyFallback: ${fontFamilyFallback != null && fontFamilyFallback!.isNotEmpty ? fontFamilyFallback : "unspecified"}, '
        'fontSize: ${fontSize ?? "unspecified"}, '
        'letterSpacing: ${letterSpacing != null ? "${letterSpacing}x" : "unspecified"}, '
        'wordSpacing: ${wordSpacing != null ? "${wordSpacing}x" : "unspecified"}, '
        'height: ${height != null ? "${height}x" : "unspecified"}, '
        'locale: ${locale ?? "unspecified"}, '
        ')';
  }
}
