import 'dart:convert';
import 'package:core/core.dart';
import 'GWUParser.dart' as gwu;
import 'config.dart';

Future<void> main() async {
  final List<SearchOffering> offerings =
      await gwu.scrapeCourses(Season.summer2019);
  offerings.addAll(await gwu.scrapeCourses(Season.fall2019));
  await uploadOfferings(offerings);
  print('Done!');
}

Future<void> uploadOfferings(List<SearchOffering> offerings) async {
  print('Uploading offerings');
  final List<Map<String, dynamic>> objects = offerings
      .map<Map<String,dynamic>>((offering) => jsonDecode(jsonEncode(offering)))
      .toList();
  await algolia.index(index).replaceAllObjects(objects);
}
