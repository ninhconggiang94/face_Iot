import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite/tflite.dart';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import 'models.dart';

typedef void Callback(List<dynamic> list, int h, int w);

class Camera extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Callback setRecognitions;

  final String model;

  Camera(
    this.cameras,
    this.model,
    this.setRecognitions,
  );

  @override
  _CameraState createState() => new _CameraState();
}

class _CameraState extends State<Camera> {
  CameraController controller;
  bool isDetecting = false;
  CameraImage _savedImage;
  // CameraImage imagetest;
  Iterable<int> imagetest = [];
  bool _cameraInitialized = false;
  static const shift = (0xFF << 24);
  void _processCameraImage(CameraImage availableImage) async {
    try {
      final int width = availableImage.width;
      final int height = availableImage.height;
      final int uvRowStride = availableImage.planes[1].bytesPerRow;
      final int uvPixelStride = availableImage.planes[1].bytesPerPixel;

      // imgLib -> Image package from https://pub.dartlang.org/packages/image
      final image = img.Image(width, height); // Create Image buffer

      // Fill image buffer with plane[0] from YUV420_888
      for (int x = 0; x < width; x++) {
        for (int y = 0; y < height; y++) {
          final int uvIndex =
              uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
          final int index = y * width + x;

          final yp = availableImage.planes[0].bytes[index];
          final up = availableImage.planes[1].bytes[uvIndex];
          final vp = availableImage.planes[2].bytes[uvIndex];
          // Calculate pixel color
          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
              .round()
              .clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
          // color: 0x FF  FF  FF  FF
          //           A   B   G   R
          image.data[index] = shift | (b << 16) | (g << 8) | r;
        }
      }

      final png = img.encodePng(image);
      String base64Image = base64Encode(png);
      log("base64Image ${base64Image}");
      // final bytes = Uint8List.fromList(png);
      // final codec = await instantiateImageCodec(bytes);
      // final frameInfo = await codec.getNextFrame();

      this.setState(() {
        imagetest = png;
      });
    } catch (e) {
      print(">>>>>>>>>>>> ERROR:" + e.toString());
    }
    return null;
  }

  void _cameraImage(availableImage) async {
    return null;
  }

  @override
  void initState() {
    super.initState();

    if (widget.cameras == null || widget.cameras.length < 1) {
      print('No camera is found');
    } else {
      controller = new CameraController(
        widget.cameras[1],
        ResolutionPreset.high,
      );
      controller.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});

        controller.startImageStream((CameraImage img) async {
          if (!isDetecting) {
            isDetecting = true;

            int startTime = new DateTime.now().millisecondsSinceEpoch;

            log("img ${img.planes[0]}");
            Tflite.detectObjectOnFrame(
              bytesList: img.planes.map((plane) {
                return plane.bytes;
              }).toList(),
              model: widget.model == yolo ? "YOLO" : "SSDMobileNet",
              imageHeight: img.height,
              imageWidth: img.width,
              imageMean: widget.model == yolo ? 0 : 127.5,
              imageStd: widget.model == yolo ? 255.0 : 127.5,
              numResultsPerClass: 1,
              threshold: widget.model == yolo ? 0.2 : 0.4,
            ).then((recognitions) {
              int endTime = new DateTime.now().millisecondsSinceEpoch;
              print("Detection took ${endTime - startTime}");
              // var future = new Future.delayed(const Duration(milliseconds: 1000));

              _processCameraImage(img);
              // _cameraImage(recognitions);
              setState(() {
                _cameraInitialized = true;
              });
              widget.setRecognitions(recognitions, img.height, img.width);
              controller.stopImageStream();
              isDetecting = false;
            });
          }
        });
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller.value.isInitialized) {
      return Container();
    }

    var tmp = MediaQuery.of(context).size;
    var screenH = math.max(tmp.height, tmp.width);
    var screenW = math.min(tmp.height, tmp.width);
    tmp = controller.value.previewSize;
    var previewH = math.max(tmp.height, tmp.width);
    var previewW = math.min(tmp.height, tmp.width);
    var screenRatio = screenH / screenW - 200;
    var previewRatio = previewH / previewW - 200;

    return OverflowBox(
        maxHeight: screenRatio > previewRatio
            ? screenH
            : screenW / previewW * previewH,
        maxWidth: screenRatio > previewRatio
            ? screenH / previewH * previewW
            : screenW,
        child: CameraPreview(
          controller,
        ));
    // child: Column(
    //     mainAxisAlignment: MainAxisAlignment.center,
    //     children: <Widget>[
    //       CameraPreview(
    //         controller,
    //       ),
    //       Image.memory(this.imagetest)
    //     ]));
  }
}
