// Utopia "Space UI": shared colors, starfield background, cards, planets,
// the account dialog frame and the remote "launch sequence" screen.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

class SpaceColors {
  static const bg = Color(0xFF060A18);
  static const card = Color(0xB80E152E); // rgba(14,21,46,.72)
  static const cardSolid = Color(0xFF0E152E);
  static const border = Color(0x1ACFD8FF); // .10
  static const border2 = Color(0x2ECFD8FF); // .18
  static const divider = Color(0x14CFD8FF); // .08
  static const field = Color(0xB3060A18);
  static const gold = Color(0xFFD4AF37);
  static const goldHover = Color(0xFFF1D47A);
  static const goldLight = Color(0xFFF4E3A8);
  static const onGold = Color(0xFF141006);
  static const text = Color(0xFFE8ECF7);
  static const muted = Color(0xFF9AA3BF);
  static const faint = Color(0xFF7F89A8);
  static const success = Color(0xFF5BD6A0);
  static const successText = Color(0xFF8FE8C2);
}

const kSpaceFont = 'SpaceGrotesk';
const kMonoFont = 'JetBrainsMono';

TextStyle spaceMono(double size,
        {Color color = SpaceColors.text,
        FontWeight weight = FontWeight.w600,
        double spacing = 1}) =>
    TextStyle(
        fontFamily: kMonoFont,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color);

/// Small caps section label, e.g. "THIS STATION".
class SpaceLabel extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  const SpaceLabel(this.text,
      {Key? key, this.color = SpaceColors.muted, this.size = 13})
      : super(key: key);

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: size,
          letterSpacing: size * 0.18,
          fontWeight: FontWeight.w500,
          color: color));
}

class SpaceCard extends StatelessWidget {
  final Widget child;
  final bool gold;
  final EdgeInsets padding;
  final double radius;
  const SpaceCard(
      {Key? key,
      required this.child,
      this.gold = false,
      this.padding = const EdgeInsets.all(22),
      this.radius = 18})
      : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: gold ? null : SpaceColors.card,
          gradient: gold
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x24D4AF37), Color(0xC70E152E)],
                  stops: [0, 0.55])
              : null,
          border: Border.all(
              color: gold ? const Color(0x52D4AF37) : SpaceColors.border),
        ),
        child: child,
      );
}

/// 44x44 square icon button with a thin border (copy, show, refresh...).
class SpaceIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  const SpaceIconButton(
      {Key? key,
      required this.icon,
      required this.tooltip,
      this.onPressed,
      this.size = 44})
      : super(key: key);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: SizedBox(
          width: size,
          height: size,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              foregroundColor: SpaceColors.text,
              side: const BorderSide(color: Color(0x26CFD8FF)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Icon(icon, size: 18),
          ),
        ),
      );
}

ButtonStyle spaceGoldButtonStyle({double radius = 14}) =>
    ElevatedButton.styleFrom(
      backgroundColor: SpaceColors.gold,
      foregroundColor: SpaceColors.onGold,
      disabledBackgroundColor: const Color(0x55D4AF37),
      disabledForegroundColor: SpaceColors.onGold,
      elevation: 0,
      shadowColor: Colors.transparent,
      textStyle: const TextStyle(
          fontFamily: kSpaceFont, fontWeight: FontWeight.w700, fontSize: 15),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    );

ButtonStyle spaceOutlineButtonStyle({double radius = 14}) =>
    OutlinedButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: SpaceColors.text,
      side: const BorderSide(color: Color(0x33CFD8FF)),
      textStyle: const TextStyle(
          fontFamily: kSpaceFont, fontWeight: FontWeight.w500, fontSize: 14),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    );

/// Gold glow under the primary button, as in the mockup.
Widget spaceGlow({required Widget child, double radius = 14}) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
              color: Color(0x59D4AF37), blurRadius: 28, offset: Offset(0, 8))
        ],
      ),
      child: child,
    );

InputDecoration spaceInputDecoration(
        {String? hint, String? error, double radius = 12, Widget? suffix}) =>
    InputDecoration(
      hintText: hint,
      errorText: error,
      errorMaxLines: 3,
      filled: true,
      fillColor: SpaceColors.field,
      isDense: false,
      counterText: '',
      suffixIcon: suffix,
      hintStyle: const TextStyle(color: Color(0x669AA3BF)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: SpaceColors.border2)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: SpaceColors.border2)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: SpaceColors.gold)),
    );

/// Planet colors (light, dark, glow) picked per device from its ID.
const _planetPalette = [
  [Color(0xFFF1D47A), Color(0xFF7A5A10), Color(0x73D4AF37)],
  [Color(0xFF9FD3FF), Color(0xFF1E3F7A), Color(0x6678B4FF)],
  [Color(0xFFC9B6FF), Color(0xFF3B2A7A), Color(0x59A082FF)],
  [Color(0xFFFFB38A), Color(0xFF7A3416), Color(0x59FF9664)],
  [Color(0xFF8FE8C2), Color(0xFF1B5E48), Color(0x595BD6A0)],
  [Color(0xFFFFB3D9), Color(0xFF7A1E4F), Color(0x59FF82BE)],
];

class SpacePlanet extends StatelessWidget {
  final String seed;
  final double size;
  final bool dim;
  const SpacePlanet(
      {Key? key, required this.seed, this.size = 40, this.dim = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = _planetPalette[seed.codeUnits.fold<int>(0, (a, b) => a + b) %
        _planetPalette.length];
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
              center: const Alignment(-0.4, -0.4),
              radius: 0.95,
              colors: [c[0], c[1]],
              stops: const [0, 0.7]),
          boxShadow: [BoxShadow(color: c[2], blurRadius: 14)],
        ),
      ),
    );
  }
}

/// Starfield (and optionally the big planet with orbit rings, bottom-right).
class SpaceBackground extends StatelessWidget {
  final bool planet;
  const SpaceBackground({Key? key, this.planet = false}) : super(key: key);

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _SpacePainter(planet),
          child: const SizedBox.expand(),
        ),
      );
}

// (x, y, radius, color) per tile, from the mockup's CSS starfield.
const _stars1 = [
  [23.0, 41.0, .7, 0xFFFFFFFF],
  [141.0, 97.0, .7, 0xFFCFD8FF],
  [260.0, 22.0, 1.0, 0xFFFFFFFF],
  [77.0, 188.0, .7, 0xFFFFFFFF],
  [199.0, 233.0, .7, 0xFFFFE9B0],
  [305.0, 160.0, 1.0, 0xFFFFFFFF],
  [12.0, 290.0, .7, 0xFFCFD8FF],
  [330.0, 300.0, .7, 0xFFFFFFFF],
];
const _stars2 = [
  [60.0, 70.0, .7, 0xFFFFFFFF],
  [400.0, 120.0, 1.3, 0xFFFFFFFF],
  [250.0, 380.0, .7, 0xFFFFE9B0],
  [480.0, 440.0, .7, 0xFFFFFFFF],
];

class _SpacePainter extends CustomPainter {
  final bool planet;
  _SpacePainter(this.planet);

  void _tile(Canvas canvas, Size size, double tw, double th, List<List<num>> s,
      double opacity) {
    final p = Paint();
    for (double ox = 0; ox < size.width; ox += tw) {
      for (double oy = 0; oy < size.height; oy += th) {
        for (final st in s) {
          p.color = Color(st[3].toInt()).withOpacity(opacity);
          canvas.drawCircle(Offset(ox + st[0], oy + st[1]), st[2].toDouble(), p);
        }
      }
    }
  }

  void _ring(Canvas canvas, Offset c, double w, double h, Paint p,
      {bool dashed = false}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-14 * math.pi / 180);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    if (!dashed) {
      canvas.drawOval(rect, p);
    } else {
      final path = Path()..addOval(rect);
      for (final m in path.computeMetrics()) {
        for (double d = 0; d < m.length; d += 8) {
          canvas.drawPath(m.extractPath(d, d + 4), p);
        }
      }
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = SpaceColors.bg);
    _tile(canvas, size, 340, 320, _stars1, .75);
    _tile(canvas, size, 520, 500, _stars2, .5);
    if (!planet) return;
    final w = size.width, h = size.height;
    final c = Offset(w - 80, h + 40);
    const r = 380.0;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = const Color(0x38D4AF37)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
              center: Alignment(-0.36, -0.44),
              radius: 1.0,
              colors: [Color(0xFF2C3C70), Color(0xFF121B3D), Color(0xFF070B1C)],
              stops: [0, 0.38, 0.7]).createShader(rect));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
              center: Alignment(-0.25, -0.3),
              radius: 0.75,
              colors: [Colors.transparent, Color(0xB3000000)],
              stops: [0.65, 1]).createShader(rect));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _ring(canvas, Offset(w - 70, h - 90), 1100, 300,
        ring..color = const Color(0x59D4AF37));
    _ring(canvas, Offset(w - 50, h - 70), 1300, 380,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x24CFD8FF),
        dashed: true);
    final dot = Offset(w - 475, h - 193);
    canvas.drawCircle(
        dot,
        9,
        Paint()
          ..color = const Color(0x99D4AF37)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(dot, 5, Paint()..color = SpaceColors.gold);
  }

  @override
  bool shouldRepaint(_SpacePainter old) => old.planet != planet;
}

/// Space-styled dialog shell: dark rounded panel, Esc cancels, Enter submits.
/// Extends CustomAlertDialog because OverlayDialogManager.show expects one.
class SpaceDialogFrame extends CustomAlertDialog {
  final Widget child;
  const SpaceDialogFrame(
      {Key? key,
      required this.child,
      VoidCallback? onCancel,
      VoidCallback? onSubmit})
      : super(
            key: key,
            content: child,
            onCancel: onCancel,
            onSubmit: onSubmit);

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.escape) {
          onCancel?.call();
          return KeyEventResult.handled;
        }
        if (onSubmit != null &&
            (e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          onSubmit!.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(20),
        child: Theme(
          data: MyTheme.darkTheme,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
                fontFamily: kSpaceFont, color: SpaceColors.text),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(children: [
                const Positioned.fill(child: SpaceBackground()),
                child,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in a remote window until the first frame arrives.
/// Steps follow real states: connection_ready (route + keys), peer info
/// (logged in / accepted), first image (docked).
class LaunchSequence extends StatelessWidget {
  final String id;
  final FFI ffi;
  final VoidCallback onAbort;
  const LaunchSequence(
      {Key? key, required this.id, required this.ffi, required this.onAbort})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // A render-mode switch re-waits for an image over the old frame: keep it visible.
    if (ffi.ffiModel.isRefreshing) return Container(color: Colors.transparent);
    ConnectionType? ct;
    try {
      ct = ConnectionTypeState.find(id);
    } catch (_) {}
    var name = '';
    try {
      name = bind.mainGetPeerOptionSync(id: id, key: 'alias');
    } catch (_) {}
    if (name.isEmpty) name = formatID(id);
    return Theme(
      data: MyTheme.darkTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: kSpaceFont, color: SpaceColors.text),
        child: Stack(children: [
          const Positioned.fill(child: SpaceBackground()),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 900,
                child: Obx(() {
                  final secure = ct?.secure.value ?? kInvalidValueStr;
                  final direct = ct?.direct.value ?? kInvalidValueStr;
                  final routed = secure != kInvalidValueStr;
                  final opened = ffi.ffiModel.pi.isSet.isTrue;
                  final docked = opened && ffi.ffiModel.waitForFirstImage.isFalse;
                  final done = [routed, routed, opened, docked];
                  final cur = done.indexOf(false);
                  final isSecure = secure == ConnectionType.strSecure;
                  final details = [
                    [translate('Utopia network'), translate('Searching…')],
                    [
                      translate(isSecure ? 'Keys verified' : 'Not encrypted'),
                      translate('Exchanging keys…')
                    ],
                    [translate('Accepted'), translate('Waiting for accept')],
                    [translate('Docked'), translate('Receiving screen…')],
                  ];
                  final labels = [
                    'Station located',
                    'Handshake',
                    'Opening channel',
                    'Docked'
                  ];
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    SpaceLabel(translate('Launch sequence'),
                        color: SpaceColors.gold, size: 12),
                    const SizedBox(height: 10),
                    Text(translate('Docking with {$name}'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(formatID(id),
                        style: spaceMono(14,
                            color: SpaceColors.muted,
                            weight: FontWeight.w500)),
                    const SizedBox(
                        width: 900,
                        height: 300,
                        child: CustomPaint(painter: _DockingPainter())),
                    SizedBox(
                      width: 820,
                      child: Row(
                        children: List.generate(4, (i) {
                          final isDone = done[i];
                          final isNow = i == cur;
                          return Expanded(
                            child: Container(
                              margin: EdgeInsets.only(left: i == 0 ? 0 : 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: isDone
                                    ? const Color(0x145BD6A0)
                                    : isNow
                                        ? const Color(0x1FD4AF37)
                                        : SpaceColors.card,
                                border: Border.all(
                                    color: isDone
                                        ? const Color(0x4D5BD6A0)
                                        : isNow
                                            ? const Color(0x8CD4AF37)
                                            : SpaceColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('0${i + 1}${isDone ? ' ✓' : ''}',
                                      style: spaceMono(12,
                                          weight: FontWeight.w500,
                                          spacing: 0,
                                          color: isDone
                                              ? SpaceColors.successText
                                              : isNow
                                                  ? SpaceColors.gold
                                                  : SpaceColors.muted)),
                                  const SizedBox(height: 4),
                                  Text(translate(labels[i]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(details[i][isDone ? 0 : 1],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: SpaceColors.muted)),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 26),
                    DefaultTextStyle.merge(
                      style: const TextStyle(
                          fontSize: 13, color: SpaceColors.muted),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${translate('Route')}: '),
                          Text(
                              !routed
                                  ? '…'
                                  : translate(direct == ConnectionType.strDirect
                                      ? 'Direct (P2P)'
                                      : 'Relay'),
                              style: const TextStyle(color: SpaceColors.text)),
                          const SizedBox(width: 28),
                          Text('${translate('Encryption')}: '),
                          Text(
                              !routed
                                  ? '…'
                                  : translate(
                                      isSecure ? 'end-to-end' : 'Not encrypted'),
                              style: const TextStyle(color: SpaceColors.text)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: onAbort,
                        style: spaceOutlineButtonStyle()
                            .copyWith(
                                padding: const MaterialStatePropertyAll(
                                    EdgeInsets.symmetric(horizontal: 28))),
                        child: Text(translate('Abort')),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DockingPainter extends CustomPainter {
  const _DockingPainter();

  void _planet(Canvas canvas, Offset c, double r, Color a, Color b, double stop,
      Color glow, double blur) {
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = glow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur));
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.4),
              radius: 0.95,
              colors: [a, b],
              stops: [0, stop]).createShader(rect));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
              center: Alignment(-0.3, -0.3),
              radius: 0.8,
              colors: [Colors.transparent, Color(0x99000000)],
              stops: [0.6, 1]).createShader(rect));
  }

  void _ring(Canvas canvas, Offset c, double w, double h, Color color) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-12 * math.pi / 180);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // dashed orbit between the planets
    final orbit = Path()
      ..addOval(Rect.fromCenter(
          center: const Offset(450, 150), width: 300, height: 180));
    final op = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x1FCFD8FF);
    for (final m in orbit.computeMetrics()) {
      for (double d = 0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, d + 4), op);
      }
    }
    _planet(canvas, const Offset(160, 150), 70, const Color(0xFF33457E),
        const Color(0xFF0E1636), 0.7, const Color(0x4D78A0FF), 30);
    _ring(canvas, const Offset(160, 150), 220, 64, const Color(0x40CFD8FF));
    _planet(canvas, const Offset(750, 150), 80, const Color(0xFFF1D47A),
        const Color(0xFF6E500E), 0.72, const Color(0x73D4AF37), 40);
    _ring(canvas, const Offset(750, 153), 260, 70, const Color(0x80D4AF37));
    final beam = Paint()
      ..color = const Color(0xE6D4AF37)
      ..strokeWidth = 2;
    for (double x = 240; x < 660; x += 20) {
      canvas.drawLine(Offset(x, 150), Offset(x + 10, 150), beam);
    }
    canvas.drawCircle(
        const Offset(442, 150),
        20,
        Paint()
          ..color = const Color(0x8CD4AF37)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawCircle(
        const Offset(442, 150), 12, Paint()..color = SpaceColors.gold);
  }

  @override
  bool shouldRepaint(_DockingPainter old) => false;
}
