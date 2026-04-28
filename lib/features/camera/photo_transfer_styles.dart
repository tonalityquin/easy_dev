

import 'package:flutter/material.dart';


class PhotoTransferColors {
  static const Color base = Color(0xFF00897B); 
  static const Color dark = Color(0xFF00695C); 
  static const Color light = Color(0xFF80CBC4); 
  static const Color fg = Color(0xFFFFFFFF); 
}


class PhotoTransferButtonStyles {
  static const double _radius = 8.0;

  
  static ButtonStyle primary({double minHeight = 55}) {
    return ElevatedButton.styleFrom(
      backgroundColor: PhotoTransferColors.base,
      foregroundColor: PhotoTransferColors.fg,
      minimumSize: Size(0, minHeight),
      padding: EdgeInsets.zero,
      side: const BorderSide(
        color: PhotoTransferColors.dark,
        width: 1.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      elevation: 0,
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed) ? PhotoTransferColors.dark.withOpacity(.10) : null,
      ),
    );
  }

  
  static ButtonStyle outlined({double minHeight = 55}) {
    return OutlinedButton.styleFrom(
      foregroundColor: PhotoTransferColors.dark,
      backgroundColor: Colors.white,
      side: const BorderSide(
        color: PhotoTransferColors.light,
        width: 1.0,
      ),
      minimumSize: Size(0, minHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed) ? PhotoTransferColors.light.withOpacity(.16) : null,
      ),
    );
  }

  static ButtonStyle smallPrimary() => primary(minHeight: 44);

  static ButtonStyle smallOutlined() => outlined(minHeight: 44);
}
