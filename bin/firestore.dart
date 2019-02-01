import 'dart:convert';
import 'package:meta/meta.dart';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class Firebase {
  final String projectId;
  final String apiKey;
  Firebase({@required this.projectId, @required this.apiKey});
}

class Firestore {
  final Firebase firebase;
  final baseUrl;
  Firestore({@required Firebase firebase})
      : firebase = firebase,
        baseUrl =
            'https://firestore.googleapis.com/v1beta1/projects/${firebase.projectId}/databases/(default)/documents/';

  Future<String> createDocument({
    @required String path,
    @required Map<String, dynamic> document,
    String docId = '',
  }) async {
    final url = '$baseUrl$path?documentId=$docId&key=${firebase.apiKey}';

    final fields = _parseMap(document);
    if (fields == null) {
      return null;
    }

    print(fields);

    final json = jsonEncode(fields);
    final response = await http.post(url, body: json);
    if (response.statusCode != 200) {
      print('Error: Upload unsuccesful');
      print(response.body);
      return null;
    }
    return response.body;
  }

  Map<String, dynamic> _parseMap(Map<String, dynamic> document) {
    var fields = {};
    var entries = document.entries;
    for (final entry in entries) {
      final json = _valueToJson(entry.value);
      if (json == null) {
        print('Error: Unsupported data type: ${entry.value}');
        return null;
      }
      fields[entry.key] = _valueToJson(entry.value);
    }
    return {'fields': fields};
  }

  Map<String, dynamic> _valueToJson(dynamic value) {
    if (value == null) {
      return {'nullValue': value};
    }
    if (value is bool) {
      return {'booleanValue': value};
    }
    if (value is int) {
      return {'integerValue': value};
    }
    if (value is double) {
      return {'doubleValue': value};
    }
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is String) {
      return {'stringValue': value};
    }
    // TODO: bytes parsing
//    if (value is Uint8List) {
//      return {'bytesValue': value.toString()};
//    }
    if (value is Reference) {
      return {'referenceValue': value.path};
    }
    if (value is LatLng) {
      return {
        'geoPointValue': {
          "latitude": value.lat,
          "longitude": value.lng,
        }
      };
    }
    if (value is Iterable) {
      final arr = value as List;
      final arrayValue = {'arrayValue': {'values': []}};
      for (final subVal in arr) {
        if (subVal.runtimeType == List) {
          print('Error: an array cannot directly contain another array value');
          return null;
        }
        arrayValue['arrayValue']['values'].add(_valueToJson(subVal));
      }
      return arrayValue;
    }
    if (value is Map) {
      return {'mapValue': _parseMap(value)};
    }
    return null;
  }
}

class Reference {
  final String path;
  Reference({@required this.path});
}

class LatLng {
  final double lat, lng;
  LatLng({@required this.lat, @required this.lng});
}

main() async {
  final fb = Firebase(projectId: 'course-gnome', apiKey: '2');
  final fs = Firestore(firebase: fb);

  final doc = {
    'bits': Uint8List(10),
  };

  final response = await fs.createDocument(path: 'cities', document: doc);
  if (response != null) {
    print('Document uploaded succesfully!');
  }
}
