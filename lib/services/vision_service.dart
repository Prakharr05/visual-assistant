import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Manages the rear camera and captures silent snapshots.
/// The image is returned as a base64-encoded JPEG string
/// ready to send to the GPT-4o Vision API.
class VisionService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  CameraController? get controller => _controller;

  /// Initialize the rear camera.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('[Vision] No cameras available');
        return;
      }

      // Pick the rear camera (first back-facing camera)
      final rearCamera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        rearCamera,
        ResolutionPreset.medium, // 720p — good enough for GPT-4o, fast to encode
        enableAudio: false, // no shutter sound
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
      debugPrint('[Vision] Camera ready');
    } catch (e) {
      debugPrint('[Vision] Failed to initialize camera: $e');
      rethrow;
    }
  }

  /// Capture a single frame and return it as a base64 JPEG string.
  ///
  /// This is the image that gets sent to GPT-4o alongside the user's question.
  /// Resized to max 512px on the longest side for fast upload and lower API cost.
  Future<String?> captureBase64Frame() async {
    if (!_isInitialized || _controller == null) {
      debugPrint('[Vision] Camera not initialized');
      return null;
    }

    try {
      final XFile file = await _controller!.takePicture();
      final Uint8List bytes = await file.readAsBytes();

      // Resize for speed + cost savings (GPT-4o handles 512px well)
      final resized = await compute(_resizeImage, bytes);
      final base64String = base64Encode(resized);

      debugPrint('[Vision] Captured frame: ${resized.length} bytes');
      return base64String;
    } catch (e) {
      debugPrint('[Vision] Capture failed: $e');
      return null;
    }
  }

  /// Resize image in an isolate to avoid blocking the UI thread.
  static Uint8List _resizeImage(Uint8List imageBytes) {
    final original = img.decodeImage(imageBytes);
    if (original == null) return imageBytes;

    // Resize so the longest side is 512px
    final int maxDim = 512;
    img.Image resized;
    if (original.width > original.height) {
      resized = img.copyResize(original, width: maxDim);
    } else {
      resized = img.copyResize(original, height: maxDim);
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  /// Clean up camera resources.
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }
}