// @no-integration-test: ImagePickerSheet drives image_picker camera/gallery
// MethodChannels and can only be exercised on a real device with live media
// access. Callers (support attach path, KYC FilePickerField) are unit-tested
// with injected XFiles above this boundary; the sheet itself is out of scope
// for widget tests.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/generated/i18n.dart';

class ImagePickerSheet {
  static Future<XFile?> show(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const .all(8.0),
          child: Column(
            mainAxisSize: .min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: Text(S.of(context).choosePhoto),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(S.of(context).choosePhotoLibrary),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return null;
    return ImagePicker().pickImage(source: source, imageQuality: 80);
  }
}
