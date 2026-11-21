/// scan_screen.dart — مسح باركود بكاميرا الجوال.
///
/// يُرجع النص المقروء عبر Navigator.pop. مصمم ليكون آمناً:
///   - أول قراءة صالحة فقط (يمنع فتح شاشات متعددة من إطارات متتالية).
///   - عند رفض إذن الكاميرا أو عدم وجودها: رسالة واضحة + إدخال يدوي بديل.
///   - الكاميرا تتوقف تلقائياً عند الخروج (dispose) — لا تستهلك بطارية في الخلفية.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/format.dart';
import '../ui/theme.dart';

/// يفتح الماسح ويُرجع الباركود أو null
Future<String?> scanBarcode(BuildContext context, {String title = 'مسح الباركود'}) => Navigator.push<String>(
  context,
  MaterialPageRoute(fullscreenDialog: true, builder: (_) => ScanScreen(title: title)),
);

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.title = 'مسح الباركود'});
  final String title;
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ctl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    // صيغ منتجات البقالة الشائعة فقط = معالجة أسرع وقراءات خاطئة أقل
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
  bool _done = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _finish(String code) {
    final c = normalizeDigits(code).trim();
    if (_done || c.isEmpty) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, c);
  }

  Future<void> _manual() async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدخال الباركود يدوياً'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'الأرقام تحت الخطوط'),
          onSubmitted: (t) => Navigator.pop(ctx, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('تم')),
        ],
      ),
    );
    ctl.dispose();
    if (v != null) _finish(v);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // نافذة المسح: 80% من العرض بحد أقصى 320، بنسبة باركود عرضي
    final w = (size.width * .8).clamp(200.0, 320.0);
    final h = w * .62;
    final window = Rect.fromCenter(center: Offset(size.width / 2, size.height * .4), width: w, height: h);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        actions: [
          ValueListenableBuilder(
            valueListenable: _ctl,
            builder: (_, st, _) => IconButton(
              tooltip: 'الفلاش',
              onPressed: st.torchState == TorchState.unavailable ? null : _ctl.toggleTorch,
              icon: Icon(st.torchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _ctl,
            scanWindow: window,
            onDetect: (cap) {
              for (final b in cap.barcodes) {
                final v = b.rawValue;
                if (v != null && v.trim().isNotEmpty) return _finish(v);
              }
            },
            errorBuilder: (ctx, e) => _ScanError(error: e, onManual: _manual),
          ),
          // تعتيم خارج نافذة المسح + إطار بزوايا
          IgnorePointer(child: CustomPaint(painter: _WindowPainter(window))),
          Positioned(
            left: Space.xl,
            right: Space.xl,
            top: window.bottom + Space.xl,
            child: const Text(
              'وجّه الكاميرا نحو الباركود داخل الإطار',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            left: Space.xl,
            right: Space.xl,
            bottom: MediaQuery.paddingOf(context).bottom + Space.xl,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: _manual,
              icon: const Icon(Icons.keyboard_rounded),
              label: const Text('إدخال الرقم يدوياً'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError({required this.error, required this.onManual});
  final MobileScannerException error;
  final VoidCallback onManual;
  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(denied ? Icons.no_photography_rounded : Icons.videocam_off_rounded, color: Colors.white70, size: 56),
              const SizedBox(height: Space.lg),
              Text(
                denied
                    ? 'لم يُسمح باستخدام الكاميرا.\nفعّل الإذن من إعدادات الجوال، أو أدخل الرقم يدوياً.'
                    : 'تعذّر تشغيل الماسح على هذا الجهاز.\n'
                          'يحتاج خدمات Google Play (وإنترنت لأول مرة فقط لتنزيل الماسح).\n'
                          'يمكنك إدخال رقم الباركود يدوياً.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: Space.lg),
              FilledButton.icon(
                onPressed: onManual,
                icon: const Icon(Icons.keyboard_rounded),
                label: const Text('إدخال يدوي'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(window, const Radius.circular(Radii.lg));
    final bg = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(r);
    canvas.drawPath(bg, Paint()..color = Colors.black.withValues(alpha: .55));
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    final (a, b, c, d) = (window.topLeft, window.topRight, window.bottomLeft, window.bottomRight);
    canvas
      ..drawLine(a, a + const Offset(l, 0), p)
      ..drawLine(a, a + const Offset(0, l), p)
      ..drawLine(b, b + const Offset(-l, 0), p)
      ..drawLine(b, b + const Offset(0, l), p)
      ..drawLine(c, c + const Offset(l, 0), p)
      ..drawLine(c, c + const Offset(0, -l), p)
      ..drawLine(d, d + const Offset(-l, 0), p)
      ..drawLine(d, d + const Offset(0, -l), p);
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}
