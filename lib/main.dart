import 'package:algolia/algolia.dart';
import 'package:core/core.dart';
import 'config.dart';
import 'GWUParser.dart';

void main() async {
  const season = Season.Summer2019;
  final courses = await GWUParser.scrapeCourses(season);
  await uploadCourses(courses, season);
  print('Done!');
  return;
}

uploadCourses(List<Course> courses, Season season) async {
  print('Uploading courses for season: $season');
  final Algolia algolia = await Algolia.init(
      applicationId: '4AISU681XR', apiKey: AlgoliaConfig.apiKey);
  final index = 'gwu-${GWUParser.getSeasonCode(season)}';
  await algolia.instance.index(index).clearIndex();
  AlgoliaBatch batch = algolia.instance.index(index).batch();
  batch.clearIndex();
  for (final course in courses) {
    batch.addObject(course.toJson());
  }
  await batch.commit();
}
