import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../services/chat_outbox_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/receipt_outbox_service.dart';
import '../../presentation/expense/controller/expense_controller.dart';

/// The strip across the very top of the app that says the device is offline —
/// and, just as importantly, what that means: what gets added or deleted now
/// is kept on the device and goes out by itself once there is a connection.
/// When the connection returns it turns green for a moment ("Back online") and
/// slides away.
///
/// Wraps the whole app from `GetMaterialApp.builder`, so it is on every
/// screen, pushed routes included, without any screen knowing about it. It
/// takes over the status bar area while it is showing, the way system-level
/// notices do, and hands that padding back to the page underneath as it
/// leaves — the two are driven off one animation, so the page slides rather
/// than jumps.
class ConnectionBanner extends StatefulWidget {
  final Widget child;

  const ConnectionBanner({super.key, required this.child});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner>
    with SingleTickerProviderStateMixin {
  final ConnectivityService _connectivity = Get.find<ConnectivityService>();

  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  StreamSubscription<bool>? _transitions;
  Timer? _backOnlineTimer;
  bool _showingBackOnline = false;

  /// What the banner says. Kept while it animates out, so the words do not
  /// vanish before the strip has gone.
  _BannerContent? _content;

  /// How long the green "back online" strip stays before sliding away.
  static const Duration _backOnlineFor = Duration(milliseconds: 2600);

  @override
  void initState() {
    super.initState();
    _transitions = _connectivity.onStatusChanged.listen(_onTransition);
    // The reason can change without a transition (no network → no internet);
    // the title follows it.
    _connectivity.addListener(_sync);
    // Already offline when the app comes up: shown from the first frame, no
    // slide-in over the splash.
    _sync(animate: false);
  }

  @override
  void dispose() {
    _transitions?.cancel();
    _backOnlineTimer?.cancel();
    _connectivity.removeListener(_sync);
    _reveal.dispose();
    super.dispose();
  }

  void _onTransition(bool online) {
    _backOnlineTimer?.cancel();
    _showingBackOnline = online;
    if (online) {
      _backOnlineTimer = Timer(_backOnlineFor, () {
        _showingBackOnline = false;
        _sync();
      });
    }
    _sync();
  }

  void _sync({bool animate = true}) {
    if (!mounted) return;

    final bool show;
    if (_connectivity.isOffline) {
      _showingBackOnline = false;
      _backOnlineTimer?.cancel();
      _content = _BannerContent.offline(_connectivity.status);
      show = true;
    } else if (_showingBackOnline) {
      _content = _BannerContent.backOnline(_hasPendingSync());
      show = true;
    } else {
      // Keep the last words while the strip slides away.
      show = false;
    }

    if (animate) {
      setState(() {});
      show ? _reveal.forward() : _reveal.reverse();
    } else {
      _reveal.value = show ? 1 : 0;
    }
  }

  /// Whether anything saved offline is still on its way out — the green strip
  /// says "syncing" rather than "up to date" then.
  bool _hasPendingSync() {
    if (Get.isRegistered<ReceiptOutboxService>() &&
        Get.find<ReceiptOutboxService>().isNotEmpty) {
      return true;
    }
    if (Get.isRegistered<ChatOutboxService>() &&
        Get.find<ChatOutboxService>().isNotEmpty) {
      return true;
    }
    // `isPrepared` is a lazy registration nobody has resolved yet — nothing to
    // read there, and finding it would only build the controller for no reason.
    return Get.isRegistered<ExpenseController>() &&
        !Get.isPrepared<ExpenseController>() &&
        Get.find<ExpenseController>().pendingCount > 0;
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double statusBar = media.padding.top;

    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final double t = _t.value;

        return Column(
          children: [
            if (t > 0 && _content != null)
              ClipRect(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: t,
                  // Crossfade between wordings — offline to back online, or
                  // one offline reason to the other — instead of a hard swap.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: _BannerStrip(
                      key: ValueKey<String>(
                        '${_content!.positive}|${_content!.title}|${_content!.body}',
                      ),
                      content: _content!,
                      topInset: statusBar,
                    ),
                  ),
                ),
              ),
            Expanded(
              // The strip owns the status bar area while it is up; the page
              // gets its top padding back in step with the strip leaving.
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(top: statusBar * (1 - t)),
                  viewPadding:
                      media.viewPadding.copyWith(top: statusBar * (1 - t)),
                ),
                child: child!,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What the strip shows — its colours and words for one connection state.
class _BannerContent {
  final bool positive;
  final IconData icon;
  final String title;
  final String body;

  const _BannerContent({
    required this.positive,
    required this.icon,
    required this.title,
    required this.body,
  });

  factory _BannerContent.offline(ConnectionStatus status) => _BannerContent(
        positive: false,
        icon: status == ConnectionStatus.noInternet
            ? Icons.wifi_off_rounded
            : Icons.cloud_off_rounded,
        title: status == ConnectionStatus.noInternet
            ? 'banner_no_internet_title'.tr
            : 'banner_offline_title'.tr,
        body: 'banner_offline_body'.tr,
      );

  factory _BannerContent.backOnline(bool syncing) => _BannerContent(
        positive: true,
        icon: syncing ? Icons.cloud_sync_rounded : Icons.cloud_done_rounded,
        title: 'banner_back_online_title'.tr,
        body: syncing
            ? 'banner_back_online_syncing'.tr
            : 'banner_back_online_body'.tr,
      );
}

class _BannerStrip extends StatelessWidget {
  final _BannerContent content;
  final double topInset;

  const _BannerStrip(
      {super.key, required this.content, required this.topInset});

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    // Warm amber for offline, green for back online — each in a light and a
    // dark cut, so the status bar icons the page already chose for its theme
    // stay readable over the strip.
    final Color background;
    final Color title;
    final Color body;
    final Color bubble;
    if (content.positive) {
      background = dark ? const Color(0xFF16351F) : const Color(0xFFE3F5E7);
      title = dark ? const Color(0xFFB7E4BF) : const Color(0xFF14532D);
      body = dark ? const Color(0xFF9CCDA5) : const Color(0xFF2F6B44);
      bubble = dark ? const Color(0x2680E19A) : const Color(0xFFBFE8C8);
    } else {
      background = dark ? const Color(0xFF3B2A12) : const Color(0xFFFFF1DE);
      title = dark ? const Color(0xFFFFD79A) : const Color(0xFF7A3E00);
      body = dark ? const Color(0xFFE6BF83) : const Color(0xFF8C5A1E);
      bubble = dark ? const Color(0x33FFC46B) : const Color(0xFFFFD9A8);
    }

    // The strip covers the status bar, so it — not the page below — decides
    // how the clock and battery icons are drawn over it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: Material(
        color: background,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: title.withOpacity(dark ? 0.18 : 0.14),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: bubble, shape: BoxShape.circle),
                  child: Icon(content.icon, size: 18, color: title),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        content.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                          color: title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        content.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: body,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
