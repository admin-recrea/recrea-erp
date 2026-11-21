import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class AutoCollapseFab extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData expandedIcon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Duration collapseDelay;

  const AutoCollapseFab({
    super.key,
    required this.label,
    required this.onPressed,
    this.expandedIcon = Icons.add_rounded,
    this.backgroundColor = RecreaTheme.rosa,
    this.foregroundColor = RecreaTheme.blanco,
    this.collapseDelay = const Duration(seconds: 2),
  });

  @override
  State<AutoCollapseFab> createState() => _AutoCollapseFabState();
}

class _AutoCollapseFabState extends State<AutoCollapseFab> {
  bool _isExpanded = true;
  Timer? _collapseTimer;

  @override
  void initState() {
    super.initState();
    _collapseTimer = Timer(widget.collapseDelay, () {
      if (mounted) {
        setState(() => _isExpanded = false);
      }
    });
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.backgroundColor,
      elevation: 4,
      shadowColor: widget.backgroundColor.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onPressed,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _isExpanded ? 18 : 15,
              vertical: 15,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isExpanded ? widget.expandedIcon : Icons.add_rounded,
                  color: widget.foregroundColor,
                  size: 24,
                ),
                if (_isExpanded) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.foregroundColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}