import 'dart:convert';

import 'package:http/http.dart' as http;

class Firestore {

  // This will be needed for non-Algolia things
  createDocument() async {
    final url = 'https://firestore.googleapis.com/v1beta1/projects/course-gnome/databases/(default)/documents/cities?documentId=&key=';
    final body = {
      'fields': {
        'tim': {
          'doubleValue': 2
        }
      }
    };
    final json = jsonEncode(body);
    final response = await http.post(url, body: json);
  }
}
