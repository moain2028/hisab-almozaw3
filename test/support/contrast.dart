// أداة فحص التباين المشتركة (WCAG) — تُستخدم في contrast_test و ui_audit_test.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _blend(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// يمسح الشجرة: لون النص الفعلي مقابل أقرب خلفية معتمة
List<String> scanContrast(Color scaffoldBg) {
  final bad = <String>[];
  for (final el in find.byType(RichText).evaluate()) {
    final rt = el.widget as RichText;
    final text = rt.text.toPlainText().trim();
    if (text.isEmpty) continue;
    // عنصر معطّل (onPressed == null) مستثنى في WCAG 1.4.3
    var disabled = false;
    el.visitAncestorElements((a) {
      final w = a.widget;
      if (w is IconButton && w.onPressed == null) disabled = true;
      if (w is ButtonStyleButton && !w.enabled) disabled = true;
      return !disabled && w is! Scaffold;
    });
    if (disabled) continue;
    // لون كل مقطع نصي فعلي (Text.rich: الأب بلا لون والأبناء ملوّنون). null = أسود المحرك (خطأ 2.2.0)
    final colors = <Color>[];
    void walk(InlineSpan sp, Color? inherited) {
      final c = sp.style?.color ?? inherited;
      if (sp is TextSpan) {
        if ((sp.text ?? '').trim().isNotEmpty) colors.add(c ?? const Color(0xFF000000));
        for (final ch in sp.children ?? const <InlineSpan>[]) {
          walk(ch, c);
        }
      }
    }

    walk(rt.text, null);
    if (colors.isEmpty) continue;
    final fg = colors.first;
    var bg = scaffoldBg;
    final layers = <Color>[];
    el.visitAncestorElements((a) {
      final w = a.widget;
      Color? c;
      if (w is Material && w.type != MaterialType.transparency) c = w.color;
      if (w is DecoratedBox && w.decoration is BoxDecoration) c = (w.decoration as BoxDecoration).color;
      if (w is Container && w.decoration is BoxDecoration) c = (w.decoration as BoxDecoration).color;
      if (w is Container && w.color != null) c = w.color;
      if (w is ColoredBox) c = w.color;
      if (w is Ink && w.decoration is BoxDecoration) c = (w.decoration as BoxDecoration).color;
      // تدرّج (البطاقة البطلة): نأخذ أسوأ حالة = لون التدرّج الأقرب للون النص
      final dec = w is DecoratedBox ? w.decoration : (w is Ink ? w.decoration : (w is Container ? w.decoration : null));
      if (c == null && dec is BoxDecoration && dec.gradient != null) {
        final cols = dec.gradient!.colors;
        c = cols.reduce((a, b) => contrast(fg, a) <= contrast(fg, b) ? a : b);
      }
      if (c != null && c.a > 0) {
        layers.add(c);
        if (c.a >= 0.99) return false;
      }
      return true;
    });
    for (final c in layers.reversed) {
      bg = _blend(c, bg);
    }
    for (final f in colors) {
      final r = contrast(_blend(f, bg), bg);
      if (r < 3.0) {
        bad.add('"$text" ${r.toStringAsFixed(2)}:1 fg=${_hex(_blend(f, bg))} bg=${_hex(bg)}');
        break;
      }
    }
  }
  return bad;
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
