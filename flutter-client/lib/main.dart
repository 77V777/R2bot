import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'R2 Auto Upload',
      home: UploadPage(),
    );
  }
}

class UploadPage extends StatefulWidget {
  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final ImagePicker _picker = ImagePicker();
  String _status = 'idle';
  String presignServer = 'http://localhost:3000'; // change if needed
  final Dio _dio = Dio();

  Future<void> _takeAndUpload() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null) return;
    setState(() => _status = 'requesting presigned url');

    final mimeType = lookupMimeType(photo.path) ?? 'application/octet-stream';
    final ext = photo.path.split('.').last;

    setState(() => _status = 'requesting presigned url');
    Response presignRes;
    try {
      presignRes = await _dio.post('$presignServer/get-presigned-url', data: {'contentType': mimeType, 'ext': ext}, options: Options(headers: {'Content-Type': 'application/json'}));
    } catch (e) {
      setState(() => _status = 'presign request failed');
      return;
    }
    if (presignRes.statusCode != 200) {
      setState(() => _status = 'failed to get presign: ${presignRes.statusCode}');
      return;
    }
    final body = presignRes.data;
    final url = body['url'];
    final key = body['key'];

    setState(() => _status = 'uploading');
    final file = File(photo.path);
    final total = await file.length();

    int attempts = 0;
    const maxAttempts = 3;
    while (attempts < maxAttempts) {
      attempts += 1;
      try {
        final stream = file.openRead();
        final response = await _dio.put(url,
            data: Stream.fromIterable(await stream.toList()),
            options: Options(headers: {'content-type': mimeType}, contentType: mimeType),
            onSendProgress: (sent, _) {
              setState(() => _status = 'uploading: ${(sent / total * 100).toStringAsFixed(0)}%');
            });
        if (response.statusCode == 200 || response.statusCode == 201) {
          setState(() => _status = 'upload success: $key');
          break;
        } else {
          setState(() => _status = 'upload failed: ${response.statusCode}, attempt $attempts');
        }
      } catch (e) {
        setState(() => _status = 'upload error: $e, attempt $attempts');
      }
      await Future.delayed(Duration(seconds: 2 * attempts));
      // If presign might have expired, try to fetch a new presign URL
      if (attempts < maxAttempts) {
        try {
          presignRes = await _dio.post('$presignServer/get-presigned-url', data: {'contentType': mimeType, 'ext': ext}, options: Options(headers: {'Content-Type': 'application/json'}));
          if (presignRes.statusCode == 200) {
            final newBody = presignRes.data;
            // replace url only if provided
            if (newBody['url'] != null) {
              // update url variable for next loop
            }
          }
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('R2 Camera Upload')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_status),
          SizedBox(height: 12),
          ElevatedButton(onPressed: _takeAndUpload, child: Text('拍照并上传'))
        ]),
      ),
    );
  }
}
