import 'dart:io';
import 'dart:math';

import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;

import 'package:core/core.dart';

String getSeasonCode(Season season) {
  switch (season) {
    case Season.summer2019:
      return '201902';
    case Season.fall2019:
      return '201903';
    default:
      return '201903';
  }
}

Future<List<Course>> scrapeCourses(Season season) async {
  print('Scraping courses for season: ${season.id}');

  const String url =
      'https://us-central1-course-gnome.cloudfunctions.net/getHTML';
  final String seasonCode = getSeasonCode(season);
  const int maxEndIndex = 10000;
  final http.Client client = http.Client();
  final int indexIncrement = season == Season.summer2019 ? 500 : 100;
  int startIndex = 1000;
  int endIndex = season == Season.summer2019 ? 1499 : 1099;

  final Stopwatch stopwatch = Stopwatch()..start();

  // Set up cache
  final Directory cacheDir = Directory('lib/cache/gwu/${season.id}')..create();

  List<Course> courses = <Course>[];

  while (endIndex < maxEndIndex) {
    print('Range: $startIndex, $endIndex');
    int pageNum = 1;
    bool lastPage = false;
    do {
      print('Page: $pageNum');
      final Map<String, dynamic> body = <String, dynamic>{
        'term': seasonCode,
        'start': startIndex.toString(),
        'end': endIndex.toString(),
        'page': pageNum.toString(),
      };
      try {
        String html;
        final File file = File('${cacheDir.path}/$startIndex - $pageNum.html');
        if (false) {
          final http.Response response = await client.post(url, body: body);
          file.writeAsString(response.body);
          html = response.body;
        } else {
          html = file.readAsStringSync();
        }
        courses = await parseResponse(html, courses, season);
        lastPage = html.contains('Next Page');
      } catch (e) {
        print(e);
        return null;
      }
      ++pageNum;
      if (pageNum > 3) {
        return courses;
      }
    } while (lastPage);
    return courses;
    startIndex += indexIncrement;
    endIndex += indexIncrement;
    print('Time elapsed: ${stopwatch.elapsed.inSeconds} seconds');
  }
  client.close();
  return courses;
}

Future<List<Course>> parseResponse(
    String response, List<Course> courses, Season season) async {
  final List<Element> results =
      parse(response).getElementsByClassName('courseListing');
  for (Element result in results) {
    courses = await parseCourse(
      result.getElementsByClassName('coursetable'),
      courses,
      season,
    );
    print(
        'Parsed: ${courses.last.name} - ${courses.last.offerings.last.sectionNumber}');
  }
  return courses;
}

Future<List<Course>> parseCourse(
  List<Element> resultRows,
  List<Course> courses,
  Season season,
) async {
  final List<Element> cells = resultRows.first.querySelectorAll('td');
  final String depAcr = cells[2].querySelector('span').text.trim();
  final String depNumber = cells[2].querySelector('a').text.trim();
  final String name = cells[4].text.trim();
  final String bulletinLink = cells[2].querySelector('a').attributes['href'];
  final int courseIndex = courses.indexWhere((Course c) =>
      c.departmentNumber == depNumber &&
      c.departmentAcronym == depAcr &&
      c.name == name);
  //final String description = await requestDescription(bulletinLink);
  String description;

  Course course;
  final Offering offering = parseOffering(resultRows, false);
  if (courseIndex != -1) {
    courses[courseIndex].offerings.add(offering);
    offering.parent = courses[courseIndex];
  } else {
    course = Course(
      school: School.gwu,
      season: season,
      description: description,
      name: name,
      departmentAcronym: depAcr,
      departmentNumber: depNumber,
      credit: cells[5].text.trim(),
      bulletinLink: bulletinLink,
      offerings: <Offering>[offering],
    );
    courses.add(course);
    offering.parent = course;
  }
  return courses;
}

Future<String> requestDescription(String bulletinLink) async {
  final http.Response response = await http.post(bulletinLink);
  return parse(response.body)
      .getElementsByClassName('courseblockdesc')
      .first
      .text
      .trim();
}

Offering parseOffering(List<Element> resultRows, bool linked) {
  // If this is not a linkedOffering, calculate how many linked offerings there are.
  // Then map each of their starting indices to offerings, by calling parseOffering
  // using a sublist of the result rows, starting at their first row.
  List<Offering> linkedOfferings;
  String linkedOfferingsName;
  if (!linked) {
    final List<int> offeringStartIndices = <int>[];
    for (int i = 0; i < resultRows.length; ++i) {
      if (resultRows[i].classes.contains('crseRow1')) {
        offeringStartIndices.add(i);
      }
    }
    if (offeringStartIndices.length > 1) {
      linkedOfferingsName = resultRows[offeringStartIndices[1]]
          .querySelectorAll('td')[4]
          .text
          .trim();
      linkedOfferings = offeringStartIndices
          .sublist(1)
          .map((int i) => parseOffering(resultRows.sublist(i), true))
          .toList();
    }
  }

  final List<Element> rowOneCells = resultRows[0].querySelectorAll('td');
  final List<Element> rowTwoCells = resultRows[1].children;

  final String statusString = rowOneCells.first.text.trim();
  final Status status = statusString == 'OPEN'
      ? Status.Open
      : statusString == 'CLOSED' ? Status.Closed : Status.Waitlist;

  List<String> instructors;
  if (rowOneCells[6].text.trim().isNotEmpty) {
    instructors = rowOneCells[6].text.trim().split(';');
    for (String instructor in instructors) {
      instructor.trim();
    }
  }

  String comments;
  List<String> courseAttributes;
  for (Element cell in rowTwoCells.first.querySelectorAll('div')) {
    if (cell.text.contains('Comments:')) {
      comments = cell.text.trim().substring(10);
    }
    if (cell.querySelector('tbody') != null) {
      courseAttributes = <String>[];
      for (Element attribute
          in cell.querySelector('tbody').querySelectorAll('tr')) {
        courseAttributes.add(attribute.text.trim().split(':').first);
      }
    }
  }

  final String findBooksLink = rowTwoCells.length == 3
      ? rowTwoCells[2].querySelector('a').attributes['href']
      : null;

  final List<ClassTime> classTimes = parseClassTimes(rowOneCells);
  List<bool> days;
  TimeOfDay earliestStartTime;
  TimeOfDay latestEndTime;
  // Only consider ones where the days and times are not null
  final List<ClassTime> viableClassTimes =
      classTimes.where((ClassTime ct) => ct.days != null).toList();

  if (viableClassTimes.isNotEmpty) {
    days = List<bool>.generate(
        7, (int i) => viableClassTimes.any((ClassTime ct) => ct.days[i]));
    earliestStartTime = viableClassTimes.fold(viableClassTimes.first.startTime,
        (TimeOfDay v, ClassTime e) => v < e.startTime ? v : e.startTime);
    latestEndTime = viableClassTimes.fold(viableClassTimes.first.endTime,
        (TimeOfDay v, ClassTime e) => v < e.endTime ? e.endTime : v);
  }

  String fee;
  if (resultRows.length > 2 && resultRows[2].classes.contains('crseRow3')) {
    final List<Element> feeRows = resultRows[2].querySelectorAll('td');
    fee = feeRows[1].text.trim() + ' ' + feeRows[2].text.trim();
  }

  return Offering(
    earliestStartTime: earliestStartTime,
    latestEndTime: latestEndTime,
    days: days,
    instructors: instructors,
    courseAttributes: courseAttributes,
    classTimes: classTimes,
    linkedOfferings: linkedOfferings,
    status: status,
    sectionNumber: rowOneCells[3].text.trim(),
    id: rowOneCells[1].text.trim(),
    linkedOfferingsName: linkedOfferingsName,
    comments: comments,
    findBooksLink: findBooksLink,
    fee: fee,
  );
}

List<ClassTime> parseClassTimes(List<Element> rowOneCells) {
  final List<ClassTime> classTimes = <ClassTime>[];
  final List<String> locations = rowOneCells[7].text.trim().split('AND');
  final List<String> dayTimes = rowOneCells[8].text.trim().split('AND');
  final int count = min(locations.length, dayTimes.length);

  for (int i = 0; i < count; ++i) {
    final String location = locations[i];
    final String dayTime = dayTimes[i];
    if (dayTime.isEmpty && location.isEmpty) {
      continue;
    }
    if (dayTime.isEmpty) {
      classTimes.add(ClassTime(location: location));
      continue;
    }
    final int index = dayTime.indexOf(RegExp('[0-9]'));
    final String days = dayTime.substring(0, index);
    final List<String> timeRange =
        dayTime.substring(index, dayTime.length).split('-');

    const List<String> dayCodes = <String>['U', 'M', 'T', 'W', 'R', 'F', 'S'];
    final List<bool> dayList =
        dayCodes.map((String c) => days.contains(c)).toList();

    classTimes.add(
      ClassTime(
        startTime: parseTime(timeRange[0]),
        endTime: parseTime(timeRange[1]),
        location: location.isNotEmpty ? location : null,
        days: dayList,
      ),
    );
  }

  return classTimes;
}

TimeOfDay parseTime(String time) {
  final List<String> split = time.trim().split(':');
  final int minutes = int.parse(split[1].substring(0, 2));
  final String amPm = split[1].substring(2, 4);
  int hours = int.parse(split[0]);
  if (amPm == 'PM' && hours != 12) {
    hours += 12;
  }
  return TimeOfDay(hour: hours, minute: minutes);
}
