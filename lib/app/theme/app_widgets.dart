import 'package:flutter/material.dart';
import 'app_colors.dart';

const _primaryNavy = AppColors.primaryNavy;
const _surface = AppColors.surface;
const _primaryText = AppColors.primaryText;
const _secondaryText = AppColors.secondaryText;
const _accentBlue = AppColors.accentBlue;
const _error = AppColors.error;

const _borderColor = Color(0xFFE2E8F0);
const _fieldFill = Color(0xFFF8FAFC);

// ─── 1. AppSectionHeader ──────────────────────────────────────────────────────

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _primaryText,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ─── 2. AppStatusBadge ────────────────────────────────────────────────────────

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─── 3. AppEmptyState ─────────────────────────────────────────────────────────

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 56,
            color: _secondaryText.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 14,
                color: _secondaryText.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 4. AppLoadingIndicator ───────────────────────────────────────────────────

class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.message,
  });

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_accentBlue),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: const TextStyle(
                fontSize: 14,
                color: _secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 5. AppCard ───────────────────────────────────────────────────────────────

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: child,
    );

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: content,
            )
          : content,
    );
  }
}

// ─── 6. AppTextField ──────────────────────────────────────────────────────────

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.decoration,
    this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.obscureText = false,
    this.enabled,
    this.autofocus = false,
    this.textDirection,
    this.maxLength,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final int? maxLines;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final bool obscureText;
  final bool? enabled;
  final bool autofocus;
  final TextDirection? textDirection;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  static const _defaultBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: _borderColor),
  );

  static const _focusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: _accentBlue, width: 1.5),
  );

  static const _errorBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: _error),
  );

  @override
  Widget build(BuildContext context) {
    const baseDecoration = InputDecoration(
      filled: true,
      fillColor: _fieldFill,
      border: _defaultBorder,
      enabledBorder: _defaultBorder,
      focusedBorder: _focusedBorder,
      errorBorder: _errorBorder,
      focusedErrorBorder: _errorBorder,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    final merged = decoration != null
        ? baseDecoration.copyWith(
            icon: decoration!.icon,
            iconColor: decoration!.iconColor,
            label: decoration!.label,
            labelText: decoration!.labelText,
            labelStyle: decoration!.labelStyle,
            floatingLabelStyle: decoration!.floatingLabelStyle,
            helperText: decoration!.helperText,
            helperStyle: decoration!.helperStyle,
            helperMaxLines: decoration!.helperMaxLines,
            hintText: decoration!.hintText,
            hintStyle: decoration!.hintStyle,
            hintTextDirection: decoration!.hintTextDirection,
            hintMaxLines: decoration!.hintMaxLines,
            errorText: decoration!.errorText,
            errorStyle: decoration!.errorStyle,
            errorMaxLines: decoration!.errorMaxLines,
            floatingLabelBehavior: decoration!.floatingLabelBehavior,
            isDense: decoration!.isDense,
            contentPadding: decoration!.contentPadding,
            prefixIcon: decoration!.prefixIcon,
            prefix: decoration!.prefix,
            prefixText: decoration!.prefixText,
            prefixStyle: decoration!.prefixStyle,
            prefixIconColor: decoration!.prefixIconColor,
            prefixIconConstraints: decoration!.prefixIconConstraints,
            suffixIcon: decoration!.suffixIcon,
            suffix: decoration!.suffix,
            suffixText: decoration!.suffixText,
            suffixStyle: decoration!.suffixStyle,
            suffixIconColor: decoration!.suffixIconColor,
            suffixIconConstraints: decoration!.suffixIconConstraints,
            counter: decoration!.counter,
            counterText: decoration!.counterText,
            counterStyle: decoration!.counterStyle,
            filled: decoration!.filled,
            fillColor: decoration!.fillColor,
            errorBorder: decoration!.errorBorder,
            focusedBorder: decoration!.focusedBorder,
            focusedErrorBorder: decoration!.focusedErrorBorder,
            disabledBorder: decoration!.disabledBorder,
            enabledBorder: decoration!.enabledBorder,
            border: decoration!.border,
            enabled: decoration!.enabled,
          )
        : baseDecoration;

    // If a validator is provided, use TextFormField; otherwise TextField.
    if (validator != null) {
      return TextFormField(
        controller: controller,
        decoration: merged,
        onChanged: onChanged,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        obscureText: obscureText,
        enabled: enabled,
        autofocus: autofocus,
        textDirection: textDirection,
        maxLength: maxLength,
        onFieldSubmitted: onSubmitted,
        focusNode: focusNode,
      );
    }

    return TextField(
      controller: controller,
      decoration: merged,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      autofocus: autofocus,
      textDirection: textDirection,
      maxLength: maxLength,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
    );
  }
}

// ─── 7. AppButton ─────────────────────────────────────────────────────────────

enum AppButtonVariant { primary, outlined, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final AppButtonVariant variant;

  static const _radius = BorderRadius.all(Radius.circular(10));
  static const _padding = EdgeInsets.symmetric(horizontal: 24, vertical: 14);

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;

    Widget child;
    if (isLoading) {
      child = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    } else if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
    } else {
      child = Text(label);
    }

    final textStyle = const TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
    );

    switch (variant) {
      case AppButtonVariant.primary:
        return ElevatedButton(
          onPressed: effectiveOnPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryNavy,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: _padding,
            shape: const RoundedRectangleBorder(borderRadius: _radius),
            textStyle: textStyle,
          ),
          child: child,
        );

      case AppButtonVariant.outlined:
        // Adjust loading indicator color for outlined variant.
        if (isLoading) {
          child = const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryNavy),
            ),
          );
        }
        return OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: _primaryNavy,
            side: const BorderSide(color: _primaryNavy),
            padding: _padding,
            shape: const RoundedRectangleBorder(borderRadius: _radius),
            textStyle: textStyle,
          ),
          child: child,
        );

      case AppButtonVariant.text:
        if (isLoading) {
          child = const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryNavy),
            ),
          );
        }
        return TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(
            foregroundColor: _primaryNavy,
            padding: _padding,
            shape: const RoundedRectangleBorder(borderRadius: _radius),
            textStyle: textStyle,
          ),
          child: child,
        );
    }
  }
}

// ─── 8. AppNavigationItem ─────────────────────────────────────────────────────

class AppNavigationItem extends StatefulWidget {
  const AppNavigationItem({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<AppNavigationItem> createState() => _AppNavigationItemState();
}

class _AppNavigationItemState extends State<AppNavigationItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;

    Color backgroundColor;
    Color textColor;
    FontWeight fontWeight;
    List<BoxShadow>? shadow;
    Border? border;

    if (isSelected) {
      backgroundColor = Colors.white;
      textColor = _accentBlue;
      fontWeight = FontWeight.w600;
      shadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
      border = Border.all(color: Colors.white, width: 2);
    } else if (_isHovered) {
      backgroundColor = Colors.white10;
      textColor = Colors.white;
      fontWeight = FontWeight.w400;
      shadow = null;
      border = null;
    } else {
      backgroundColor = Colors.transparent;
      textColor = Colors.white;
      fontWeight = FontWeight.w400;
      shadow = null;
      border = null;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: border,
            boxShadow: shadow,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
              fontWeight: fontWeight,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
