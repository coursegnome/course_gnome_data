import 'dart:math';

import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:algolia/algolia.dart';

import 'package:core/core.dart';
import 'config.dart';

enum Season {
  Spring2019,
  Summer2019,
}

class GWUParser {
  static getSeasonCode(Season season) {
    switch (season) {
      case Season.Spring2019:
        return '201901';
      case Season.Summer2019:
        return '201902';
    }
  }

  static Future<List<Course>> scrapeCourses(Season season) async {
    print('Scraping courses for season: $season');

    const url = 'https://us-central1-course-gnome.cloudfunctions.net/getHTML';
    final seasonCode = getSeasonCode(season);
    const maxEndIndex = 10000;
    final client = http.Client();
    var startIndex = 1000;
    var endIndex = 1499;

    List<Course> courses = [];

    while (endIndex < maxEndIndex) {
      print('Range: $startIndex, $endIndex');
      var pageNum = 1;
      var lastPage = false;
      do {
        print('Page: $pageNum');
        final body = {
          'term': seasonCode,
          'start': startIndex.toString(),
          'end': endIndex.toString(),
          'page': pageNum.toString(),
        };
        try {
          final response = await client.post(url, body: body);
          courses = parseResponse(response.body, courses);
          lastPage = isLastPage(response);
        } catch (e) {
          print(e);
          return null;
        }
        ++pageNum;
      } while (lastPage);
      startIndex += 500;
      endIndex += 500;
    }
    client.close();
    return courses;
  }

  static bool isLastPage(http.Response response) {
    return response.body.contains('Next Page');
  }

  static List<Course> parseResponse(String response, List<Course> courses) {
    parse(response).getElementsByClassName('courseListing').forEach((result) {
      courses = parseCourse(
        result.getElementsByClassName('coursetable'),
        courses,
      );
      print('Parsed: ${courses.last.name}');
    });
    return courses;
  }

  static List<Course> parseCourse(
      List<Element> resultRows, List<Course> courses) {
    final cells = resultRows[0].querySelectorAll('td');
    final depAcr = cells[2].querySelector('span').text.trim();
    final depNumber = cells[2].querySelector('a').text.trim();
    final name = cells[4].text.trim();
    final courseIndex = courses.indexWhere((c) =>
        c.departmentNumber == depNumber &&
        c.departmentAcronym == depAcr &&
        c.name == name);

    Course course;
    if (courseIndex != -1) {
      course = courses[courseIndex];
    } else {
      course = Course(
        name: name,
        departmentAcronym: depAcr,
        departmentNumber: depNumber,
        credit: cells[5].text.trim(),
        bulletinLink: cells[2].querySelector('a').attributes['href'],
        offerings: [],
      );
      courses.add(course);
    }
    course.offerings.add(parseOffering(resultRows, false));
    return courses;
  }

  static Offering parseOffering(List<Element> resultRows, bool linked) {
    // If this is not a linkedOffering, calculate how many linked offerings there are.
    // Then map each of their starting indices to offerings, by calling parseOffering
    // using a sublist of the result rows, starting at their first row.
    List<Offering> linkedOfferings;
    String linkedOfferingsName;
    if (!linked) {
      List<int> offeringStartIndices = [];
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
            .map((i) => parseOffering(resultRows.sublist(i), true))
            .toList();
      }
    }

    final rowOneCells = resultRows[0].querySelectorAll('td');
    final rowTwoCells = resultRows[1].children;

    final statusString = rowOneCells[0].text.trim();
    final Status status = statusString == 'OPEN'
        ? Status.Open
        : statusString == 'CLOSED' ? Status.Closed : Status.Waitlist;

    List<String> instructors = null;
    if (rowOneCells[6].text.trim().isNotEmpty) {
      instructors = rowOneCells[6].text.trim().split(';');
      instructors.forEach((i) => i.trim());
    }

    String comments;
    List<String> courseAttributes;
    rowTwoCells[0].querySelectorAll('div').forEach((cell) {
      if (cell.text.contains('Comments:')) {
        comments = cell.text.trim().substring(10);
      }
      ;
      if (cell.querySelector('tbody') != null) {
        courseAttributes = [];
        cell.querySelector('tbody').querySelectorAll('tr').forEach((attribute) {
          courseAttributes.add(attribute.text.trim().split(':').first);
        });
      }
    });

    String findBooksLink = rowTwoCells.length == 3
        ? rowTwoCells[2].querySelector('a').attributes['href']
        : null;

    final classTimes = parseClassTimes(rowOneCells);
    List<bool> days;
    TimeOfDay earliestStartTime;
    TimeOfDay latestEndTime;
    // Only consider ones where the days and times are not null
    List<ClassTime> viableClassTimes =
        classTimes.where((ct) => ct.days != null).toList();

    if (viableClassTimes.isNotEmpty) {
      days = List.generate(7, (i) => viableClassTimes.any((ct) => ct.days[i]));
      earliestStartTime = viableClassTimes.fold(
          viableClassTimes.first.startTime,
          (v, ClassTime e) => v < e.startTime ? v : e.startTime);
      latestEndTime = viableClassTimes.fold(viableClassTimes.first.endTime,
          (v, ClassTime e) => v < e.endTime ? e.endTime : v);
    }

    String fee;
    if (resultRows.length > 2 && resultRows[2].classes.contains('crseRow3')) {
      final feeRows = resultRows[2].querySelectorAll('td');
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
      crn: rowOneCells[1].text.trim(),
      linkedOfferingsName: linkedOfferingsName,
      comments: comments,
      findBooksLink: findBooksLink,
      fee: fee,
    );
  }

  static List<ClassTime> parseClassTimes(List<Element> rowOneCells) {
    final classTimes = List<ClassTime>();
    final locations = rowOneCells[7].text.trim().split('AND');
    final dayTimes = rowOneCells[8].text.trim().split('AND');
    final count = min(locations.length, dayTimes.length);

    for (var i = 0; i < count; ++i) {
      final location = locations[i];
      final dayTime = dayTimes[i];

      if (dayTime.isEmpty && location.isEmpty) continue;
      if (dayTime.isEmpty) {
        classTimes.add(ClassTime(location: location));
        continue;
      }

      final index = dayTime.indexOf(RegExp('[0-9]'));
      final days = dayTime.substring(0, index);
      final timeRange = dayTime.substring(index, dayTime.length).split('-');

      final dayList = [
        days.contains('U'),
        days.contains('M'),
        days.contains('T'),
        days.contains('W'),
        days.contains('R'),
        days.contains('F'),
        days.contains('S'),
      ];

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

  static TimeOfDay parseTime(String time) {
    final split = time.trim().split(':');
    var hours = int.parse(split[0]);
    var minutes = int.parse(split[1].substring(0, 2));
    final amPm = split[1].substring(2, 4);
    if (amPm == 'PM' && hours != 12) {
      hours += 12;
    }
    return TimeOfDay(hour: hours, minute: minutes);
  }
}
