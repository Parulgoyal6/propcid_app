import 'package:flutter/material.dart';

class SizeUtils {
  SizeUtils._();

  static double getWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  static double getHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  static double getStatusBarHeight(BuildContext context) {
    return MediaQuery.of(context).padding.top;
  }

  static double getBottomNavBarHeight(BuildContext context) {
    return MediaQuery.of(context).padding.bottom;
  }

  static double getSafeAreaHeight(BuildContext context) {
    return getHeight(context) -
        getStatusBarHeight(context) -
        getBottomNavBarHeight(context);
  }

  static bool isTablet(BuildContext context) {
    return getWidth(context) > 600;
  }

  static bool isMobile(BuildContext context) {
    return getWidth(context) <= 600;
  }

  static double getResponsiveWidth(BuildContext context, double percentage) {
    return getWidth(context) * percentage;
  }

  static double getResponsiveHeight(BuildContext context, double percentage) {
    return getHeight(context) * percentage;
  }
}
