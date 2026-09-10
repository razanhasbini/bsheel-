import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/router/route_names.dart';

/// A draggable badge that opens the CAMARA demo from anywhere in the app.
///
/// This exists for the hackathon judges and for nobody else, so it is
/// deliberately not part of any user-facing screen: it is an overlay above
/// the whole app, `kDebugMode` only, and it cannot appear in a release
/// build even if someone forgets to remove it. Delete `lib/features/dev/`
/// and the one wrapper in app.dart when the demo is over.
///
/// It is draggable because it floats over real UI and would otherwise
/// cover whatever it happened to land on.
class DemoLauncherOverlay extends ConsumerStatefulWidget {
  const DemoLauncherOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DemoLauncherOverlay> createState() =>
      _DemoLauncherOverlayState();
}

class _DemoLauncherOverlayState extends ConsumerState<DemoLauncherOverlay> {
  // Bottom-right by default, clear of the nav bar.
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;

    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final position = _position ??
        Offset(size.width - 96, size.height - padding.bottom - 172);

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: position.dx,
          top: position.dy,
          // Plain pan rather than Draggable: this badge floats ABOVE the
          // app's Navigator, and Draggable needs an Overlay ancestor it
          // therefore does not have — it asserts on first build.
          child: GestureDetector(
            onPanUpdate: (details) => setState(() {
              _position = Offset(
                (position.dx + details.delta.dx).clamp(0.0, size.width - 84),
                (position.dy + details.delta.dy)
                    .clamp(padding.top, size.height - 84),
              );
            }),
            child: _Badge(
              // The router object, not Navigator.of(context). This overlay
              // is built by MaterialApp.builder, which sits ABOVE the
              // router's Navigator — so there is no Navigator and no
              // InheritedGoRouter to look up from here, and the tap did
              // nothing. Pushing on the router itself works from anywhere.
              onTap: () =>
                  ref.read(appRouterProvider).pushNamed(RouteNames.camaraDemo),
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Material, because this floats above the router's own Navigator and
    // must not inherit a page's text direction or theme surprises.
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFF6B3BFF),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF1A1330), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xFF1A1330), offset: Offset(0, 4)),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cell_tower_rounded, color: Colors.white, size: 26),
              SizedBox(height: 2),
              Text(
                'CAMARA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
