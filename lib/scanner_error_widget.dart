import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerErrorWidget extends StatelessWidget {
  final MobileScannerException error;
  const ScannerErrorWidget({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4444), size: 48),
          const SizedBox(height: 12),
          Text(
            _message(error.errorCode),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _message(MobileScannerErrorCode code) {
    switch (code) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Camera permission denied.\nGrant it in Settings.';
      case MobileScannerErrorCode.unsupported:
        return 'Scanner not supported on this device.';
      default:
        return 'Scanner error. Restart the app.';
    }
  }
}