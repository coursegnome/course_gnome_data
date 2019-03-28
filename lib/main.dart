import 'dart:convert';
import 'package:algolia/algolia.dart';
import 'package:core/core.dart';
import 'GWUParser.dart' as gwu;
import 'config.dart' as config;

Future<void> main() async {
  final List<SearchOffering> offerings =
      await gwu.scrapeCourses(Season.summer2019);
  offerings.addAll(await gwu.scrapeCourses(Season.fall2019));
  await uploadOfferings(offerings);
  print('Done!');
  return;
}

Future<void> uploadOfferings(List<SearchOffering> offerings) async {
  print('Uploading offerings');
  const Algolia algolia = Algolia.init(
    applicationId: config.appId,
    apiKey: config.algoliaApiKey,
  );
  final AlgoliaBatch batch = algolia.instance.index(config.index).batch()
    ..clearIndex();
  for (final SearchOffering offering in offerings) {
    batch.addObject(jsonDecode(jsonEncode(offering)));
  }
  await batch.commit();
  return;
}
