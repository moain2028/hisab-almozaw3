/// pinned.dart — رأس مثبّت عند التمرير (Sticky) لكل القوائم الطويلة.
///
/// القاعدة في التطبيق: أدوات التحكم (اليوم، البحث، الفلترة، الفترة) **لا تختفي أبداً** عند النزول.
/// ما يتمرّر هو المحتوى فقط.
///
/// الارتفاع **يُحسب من المحتوى** (PinnedHeaderSliver) وليس رقماً ثابتاً: الرقم الثابت كان يسبب
/// overflow عند تكبير خط النظام (×1.25) أو على الشاشات الصغيرة — انظر LESSONS.md (2.3.0).
library;

import 'package:flutter/material.dart';

class PinnedHeader extends StatefulWidget {
  const PinnedHeader({super.key, required this.child});
  final Widget child;

  @override
  State<PinnedHeader> createState() => _PinnedHeaderState();
}

class _PinnedHeaderState extends State<PinnedHeader> {
  ScrollPosition? _pos;
  bool _scrolled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _pos) {
      _pos?.removeListener(_onScroll);
      _pos = p?..addListener(_onScroll);
    }
  }

  void _onScroll() {
    final s = (_pos?.pixels ?? 0) > 0;
    if (s != _scrolled) setState(() => _scrolled = s);
  }

  @override
  void dispose() {
    _pos?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PinnedHeaderSliver(
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        // خط فاصل خفيف يظهر فقط عندما يمر المحتوى تحته
        shape: _scrolled ? Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))) : null,
        child: Padding(padding: const EdgeInsets.only(bottom: 8), child: widget.child),
      ),
    );
  }
}
