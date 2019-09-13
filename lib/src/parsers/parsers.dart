import 'package:course_gnome_data/src/models/course.dart';
import 'package:course_gnome_data/src/parsers/gwu/gwu_parser.dart' as gwu;

Future<List<SearchOffering>> scrape({
  School school,
  Season season,
}) async {
  switch (school) {
    case School.gwu:
      return await gwu.scrapeCourses(season);
    default:
      return null;
  }
}

Future<List<SearchOffering>> parse({
  String response,
  Season season,
  School school,
}) {
  switch (school) {
    case School.gwu:
      return gwu.parseResponse(response, season);
    default:
      return null;
  }
}
