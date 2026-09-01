import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/services/image_download_service.dart';

void main() {
  test('a saved picture keeps the name the storage object was given', () {
    expect(
      ImageDownloadService.fileNameFor(
        'https://xyz.supabase.co/storage/v1/object/public/media/chat/photo_1699999.jpg',
      ),
      'photo_1699999.jpg',
    );
  });

  test('a query string is not part of the name', () {
    expect(
      ImageDownloadService.fileNameFor(
        'https://xyz.supabase.co/storage/v1/object/public/media/chat/shot.png?token=abc',
      ),
      'shot.png',
    );
  });

  test('a name with no extension takes one from what was served', () {
    expect(
      ImageDownloadService.fileNameFor(
        'https://example.com/media/receipt',
        contentType: 'image/png; charset=utf-8',
      ),
      'receipt.png',
    );
    // Nothing to go on: a photograph is a jpeg until told otherwise.
    expect(
      ImageDownloadService.fileNameFor('https://example.com/media/receipt'),
      'receipt.jpg',
    );
  });

  test('a URL with no name of its own still saves under something', () {
    final String name = ImageDownloadService.fileNameFor('https://example.com/');
    expect(name, startsWith('image_'));
    expect(name, endsWith('.jpg'));
  });

  test('a name cannot carry a path out of the folder it is saved in', () {
    expect(
      ImageDownloadService.fileNameFor('https://example.com/a/%2E%2E%2Fetc%2Fpasswd'),
      '_etc_passwd.jpg',
    );
  });
}
