import 'dart:convert';

import 'package:course_gnome_data/models.dart';
import 'package:course_gnome_data/parsers.dart';
import 'config.dart';

Future<void> main() async {
  print('Scraping GWU courses');
  final List<SearchOffering> offerings =
      await scrape(school: School.gwu, season: Season.summer2019);
  offerings.addAll(await scrape(school: School.gwu, season: Season.fall2019));
  await uploadOfferings(offerings);
  print('Done!');
}

Future<void> uploadOfferings(List<SearchOffering> offerings) async {
  print('Uploading offerings');
  final List<Map<String, dynamic>> objects = offerings
      .map<Map<String, dynamic>>((offering) => jsonDecode(jsonEncode(offering)))
      .toList();
  await algolia.index(index).replaceAllObjects(objects);
}
