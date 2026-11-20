import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class OtpInputWidget extends StatefulWidget {
  final int fieldCount;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final FocusNode? firstFocusNode;
  final TextEditingController? controller;
  final VoidCallback? onSubmitted;
  final bool obscure;
  final bool alphanumeric;

  const OtpInputWidget({
    super.key,
    this.fieldCount = 6,
    required this.onCompleted,
    this.onChanged,
    this.firstFocusNode,
    this.controller,
    this.onSubmitted,
    this.obscure = false,
    this.alphanumeric = false,
  });

  @override
  State<OtpInputWidget> createState() => _OtpInputWidgetState();
}

class _OtpInputWidgetState extends State<OtpInputWidget>
    with SingleTickerProviderStateMixin {
  TextEditingController? _internalController;
  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  FocusNode? _internalFocusNode;
  FocusNode get _effectiveFocusNode =>
      widget.firstFocusNode ?? (_internalFocusNode ??= FocusNode());

  late AnimationController _cursorAnimController;
  late Animation<double> _cursorOpacity;
  late List<String> _values;
  int _activeIndex = -1;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _values = List.generate(widget.fieldCount, (_) => '');

    _cursorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _cursorOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _cursorAnimController,
        curve: Curves.easeInOut,
      ),
    );

    _effectiveController.addListener(_syncFromController);
    _effectiveFocusNode.addListener(_onFocusChanged);

    _syncFromController();
    _isFocused = _effectiveFocusNode.hasFocus;
    if (_isFocused) {
      final len = _effectiveController.text.length;
      _activeIndex =
          len < widget.fieldCount ? len : widget.fieldCount - 1;
      _cursorAnimController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(OtpInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstFocusNode != widget.firstFocusNode) {
      oldWidget.firstFocusNode?.removeListener(_onFocusChanged);
      _effectiveFocusNode.addListener(_onFocusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncFromController);
      _effectiveController.addListener(_syncFromController);
    }
  }

  @override
  void dispose() {
    _cursorAnimController.dispose();
    _effectiveFocusNode.removeListener(_onFocusChanged);
    _effectiveController.removeListener(_syncFromController);
    _internalFocusNode?.dispose();
    _internalController?.dispose();
    super.dispose();
  }

  void _syncFromController() {
    if (!mounted) return;
    final text = _effectiveController.text;
    setState(() {
      for (int i = 0; i < widget.fieldCount; i++) {
        _values[i] = text.length > i ? text[i] : '';
      }
      if (_effectiveFocusNode.hasFocus) {
        _activeIndex =
            text.length < widget.fieldCount ? text.length : widget.fieldCount - 1;
      } else {
        _activeIndex = -1;
      }
    });
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {
      _isFocused = _effectiveFocusNode.hasFocus;
      if (_isFocused) {
        final len = _effectiveController.text.length;
        _activeIndex =
            len < widget.fieldCount ? len : widget.fieldCount - 1;
        _cursorAnimController.repeat(reverse: true);
      } else {
        _activeIndex = -1;
        _cursorAnimController.stop();
      }
    });
  }

  void _focusHidden() {
    if (!_effectiveFocusNode.hasFocus) {
      _effectiveFocusNode.requestFocus();
    }
    _effectiveController.selection = TextSelection.fromPosition(
      TextPosition(offset: _effectiveController.text.length),
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _effectiveFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
        setState(() {
          _isFocused = true;
          final len = _effectiveController.text.length;
          _activeIndex =
              len < widget.fieldCount ? len : widget.fieldCount - 1;
          _cursorAnimController.repeat(reverse: true);
        });
      }
    });
  }

  void _notifyChanged() {
    final code = _values.join();
    widget.onChanged?.call(code);
    if (code.length == widget.fieldCount) {
      widget.onCompleted(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth * 0.03;
        final fieldSize =
            (constraints.maxWidth - spacing * (widget.fieldCount - 1)) /
                widget.fieldCount;
        final clampedSize = fieldSize.clamp(28.0, 60.0);
        final radius = clampedSize * 0.35;
        final fontSize = clampedSize * 0.5;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _focusHidden,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(widget.fieldCount, (index) {
                    final isFilled = _values[index].isNotEmpty;
                    final isActive = index == _activeIndex;

                    return Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: index < widget.fieldCount - 1 ? spacing : 0,
                      ),
                      child: SizedBox(
                        width: clampedSize,
                        height: clampedSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              width: clampedSize,
                              height: clampedSize,
                              decoration: BoxDecoration(
                                color: const Color(0xFF102A1C),
                                borderRadius: BorderRadius.circular(radius),
                                border: Border.all(
                                  color: isActive && _isFocused
                                      ? AppTheme.emeraldPrimary
                                      : isFilled
                                          ? Colors.white.withValues(alpha: 0.8)
                                          : Colors.white.withValues(alpha: 0.25),
                                  width: isActive && _isFocused ? 2 : 1.5,
                                ),
                                boxShadow: isActive && _isFocused
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.emeraldPrimary
                                              .withValues(alpha: 0.4),
                                          blurRadius: 14,
                                          spreadRadius: 1.5,
                                        ),
                                      ]
                                    : (isFilled
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.emeraldPrimary
                                                  .withValues(alpha: 0.18),
                                              blurRadius: 10,
                                              spreadRadius: 0.5,
                                            ),
                                          ]
                                        : null),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                              child: _values[index].isEmpty
                                  ? (isActive && _isFocused
                                      ? FadeTransition(
                                          key: const ValueKey('cursor'),
                                          opacity: _cursorOpacity,
                                          child: Container(
                                            width: 2.0,
                                            height: clampedSize * 0.45,
                                            decoration: BoxDecoration(
                                              color: AppTheme.emeraldPrimary,
                                              borderRadius:
                                                  BorderRadius.circular(1),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.emeraldPrimary
                                                      .withValues(alpha: 0.6),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(
                                          key: ValueKey('empty'),
                                        ))
                                  : Text(
                                      widget.obscure ? '●' : _values[index],
                                      key: ValueKey(
                                          '${_values[index]}_$index'),
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // Hidden TextField to trigger soft keyboard on mobile
              Opacity(
                opacity: 0,
                child: SizedBox(
                  height: 1,
                  width: 1,
                  child: TextField(
                    controller: _effectiveController,
                    focusNode: _effectiveFocusNode,
                    keyboardType: widget.alphanumeric
                        ? TextInputType.text
                        : TextInputType.number,
                    inputFormatters: [
                      if (!widget.alphanumeric)
                        FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.fieldCount),
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => widget.onSubmitted?.call(),
                    enableInteractiveSelection: false,
                    onChanged: (value) {
                      setState(() {
                        for (int i = 0; i < widget.fieldCount; i++) {
                          _values[i] = value.length > i ? value[i] : '';
                        }
                        _activeIndex = value.length < widget.fieldCount
                            ? value.length
                            : widget.fieldCount - 1;
                      });
                      _notifyChanged();
                    },
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
