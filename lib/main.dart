import 'package:algolia/algolia.dart';
import 'package:core/core.dart';
import 'GWUParser.dart' as gwu;
import 'config.dart';

Future<void> main() async {
  const gwu.Season season = gwu.Season.Summer2019;
  final List<Course> courses = await gwu.scrapeCourses(season);
//  await uploadCourses(courses, season);
  print('Done!');
  return;
}

Future<void> uploadCourses(List<Course> courses, gwu.Season season) async {
  print('Uploading courses for season: $season');
  final String index = 'gwu-${gwu.getSeasonCode(season)}';

  final Algolia algolia = const Algolia.init(
    applicationId: '4AISU681XR',
    apiKey: algoliaApiKey,
  )..instance.index(index).clearIndex();
  final AlgoliaBatch batch = algolia.instance.index(index).batch()
    ..clearIndex();
  for (final Course course in courses) {
    batch.addObject(course.toJson());
  }
  await batch.commit();
}
