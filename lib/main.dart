import 'package:algolia/algolia.dart';
import 'package:core/core.dart';
import 'GWUParser.dart' as gwu;
import 'config.dart';

Future<void> main() async {
  const Season season = Season.fall2019;
  final List<Course> courses = await gwu.scrapeCourses(season);
  await uploadCourses(courses);
  print('Done!');
  return;
}

Future<void> uploadCourses(List<Course> courses) async {
  print('Uploading courses');
  print(courses.length);
  const String index = 'courses';
  final Algolia algolia = const Algolia.init(
    applicationId: '4AISU681XR',
    apiKey: algoliaApiKey,
  )..instance.index(index).clearIndex();
  final AlgoliaBatch batch = algolia.instance.index(index).batch()
    ..clearIndex();
  for (final Course course in courses) {
    for (final Offering offering in course.offerings) {
      Map<String, dynamic> map = <String, dynamic>{
        'course': course.toJson(),
        'offering': offering.toJson(),
      };
      batch.addObject(map);
    }
  }
  await batch.commit();
  return;
}
