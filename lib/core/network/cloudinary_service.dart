import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

class CloudinaryService {
  static const String cloudName = 'xy3ecojw';
  static const String uploadPreset = 'recrea_vouchers';

  // 1. Subir Imágenes (Vouchers y Foto del Niño) con compresión automática
  static Future<String?> pickAndUploadImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image == null) return null;

      List<int> compressedBytes;

      if (kIsWeb) {
        compressedBytes = await image.readAsBytes();
      } else {
        final File file = File(image.path);
        final result = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 800,
          minHeight: 800,
          quality: 70,
        );
        if (result == null) return null;
        compressedBytes = result.toList();
      }

      return await _uploadToCloudinary(compressedBytes, image.name);
    } catch (e) {
      debugPrint('Error en pickAndUploadImage: $e');
      return null;
    }
  }

  // 2. Subir Documentos PDF o Imágenes (DNI ambos lados)
  static Future<String?> pickAndUploadDocument({
    List<String> allowedExtensions = const ['pdf', 'jpg', 'jpeg', 'png'],
  }) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );

      if (files.isEmpty) return null;
      final file = files.first;

      // Usamos readAsBytes() en lugar de readBytes()
      Uint8List? fileBytes = await file.readAsBytes();
      if (fileBytes.isEmpty && file.path != null) {
        fileBytes = await File(file.path!).readAsBytes();
      }

      if (fileBytes.isEmpty) return null;

      return await _uploadToCloudinary(fileBytes, file.name);
    } catch (e) {
      debugPrint('Error en pickAndUploadDocument: $e');
      return null;
    }
  }

  // Usando 'auto/upload' Cloudinary acepta tanto imágenes como archivos PDF
  static Future<String?> _uploadToCloudinary(List<int> fileBytes, String fileName) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/auto/upload');

    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );

    try {
      final response = await request.send();
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);

      if (response.statusCode == 200) {
        return jsonMap['secure_url'];
      } else {
        debugPrint('Error de Cloudinary: ${jsonMap['error']['message']}');
        return null;
      }
    } catch (e) {
      debugPrint('Error HTTP al subir a Cloudinary: $e');
      return null;
    }
  }
}