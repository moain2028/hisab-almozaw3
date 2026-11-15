/// pinned.dart — رأس مثبّت عند التمرير (Sticky) لكل القوائم الطويلة.
///
/// القاعدة في التطبيق: أدوات التحكم (اليوم، البحث، الفلترة، الفترة) **لا تختفي أبداً** عند النزول.
/// ما يتمرّر هو المحتوى فقط.
library;

import 'package:flutter/material.dart';

class PinnedHeader extends StatelessWidget {
  const PinnedHeader({super.key, required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SliverPersistentHeader(pinned: true, delegate: _Delegate(height, child, Theme.of(context).scaffoldBackgroundColor));
}

class _Delegate extends SliverPersistentHeaderDelegate {
  _Delegate(this.height, this.child, this.bg);
  final double height;
  final Widget child;
  final Color bg;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: bg,
      // خط فاصل خفيف يظهر فقط عندما يمر المحتوى تحته
      shape: overlapsContent || shrinkOffset > 0
          ? Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .6)))
          : null,
      child: SizedBox.expand(child: child),
    );
  }

  @override
  bool shouldRebuild(_Delegate old) => old.child != child || old.height != height || old.bg != bg;
}
