import 'dart:convert';
import 'package:algolia/algolia.dart';
import 'package:core/core.dart';
import 'GWUParser.dart' as gwu;
import 'config.dart' as config;

Future<void> main() async {
  const Season season = Season.fall2019;
  final List<SearchOffering> offerings = await gwu.scrapeCourses(season);
  await uploadOfferings(offerings);
  print('Done!');
  return;
}

Future<void> uploadOfferings(List<SearchOffering> courses) async {
  print('Uploading offerings');
  const Algolia algolia = Algolia.init(
    applicationId: config.appId,
    apiKey: config.algoliaApiKey,
  );
  final AlgoliaBatch batch = algolia.instance.index(config.index).batch()
    ..clearIndex();
  for (final SearchOffering offering in courses) {
    batch.addObject(jsonDecode(jsonEncode(offering)));
  }
  await batch.commit();
  return;
}
