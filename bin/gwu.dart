import 'dart:math';

import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;

import 'package:course_gnome/model/Course.dart';

final courses = List<Course>();

void main() async {
  const url = 'https://my.gwu.edu/mod/pws/searchresults.cfm';

  final client = http.Client();

  var startIndex = 1000;
  var endIndex = 1100;

  while (endIndex < 2000) {
    print('$startIndex, $endIndex');
    var pageNum = 1;
    do {
      final options = {
        'term': '201901',
        'Submit': 'Search',
        'campus': '1',
        'srchType': 'All',
        'courseNumSt': startIndex.toString(),
        'courseNumEn': endIndex.toString(),
        'pageNum': pageNum.toString(),
      };
      try {
        final response = await client.post(url, body: options);
        parseResponse(await client.post(url, body: options));
      } catch (e) {
        print(e);
        return;
      }
      print(courses);
      break;
      ++pageNum;
    } while (true);
    break;
  }
  client.close();
}

parseResponse(http.Response response) {
  final results = parse(response.body).getElementsByClassName('courseListing');
  for (final result in results) {
    final resultRows = result.getElementsByClassName('coursetable');
    final course = parseCourse(resultRows[0]);
    final offering = parseOfferingRows(resultRows);
    if (offering == null) continue;
    course.offerings.add(offering);
  }
}

Course parseCourse(Element elm) {
  final cells = elm.querySelectorAll('td');
  final depAcr = cells[2].querySelector('span').text.trim();
  final depNumber = cells[2].querySelector('a').text.trim();
  final courseIndex = courses.indexWhere(
      (c) => c.departmentNumber == depNumber && c.departmentAcronym == depAcr);
  if (courseIndex != -1) {
    return courses[courseIndex];
  } else {
    final course = Course(
      name: cells[4].text.trim(),
      departmentAcronym: depAcr,
      departmentNumber: depNumber,
      credit: cells[5].text.trim(),
      bulletinLink: cells[2].querySelector('a').attributes['href'],
      offerings: [],
    );
    courses.add(course);
    return course;
  }
}

Offering parseOfferingRows(List<Element> resultRows) {
  if (resultRows[0].querySelectorAll('td')[10].text.trim() != 'Linked') {
    return parseOffering(resultRows, 0, resultRows.length);
  } else {
    var offeringIndices = List<int>();
    for (int i = 0; i < resultRows.length; ++i) {
      if (resultRows[i].classes.contains('crseRow1')) {
        offeringIndices.add(i);
      }
    }
    final offering = parseOffering(resultRows, 0, offeringIndices[1]);
    offering.linkedOfferings = List<Offering>();
    for (var i = 1; i < offeringIndices.length; ++i) {
      final end = i == offeringIndices.length - 1
          ? resultRows.length
          : offeringIndices[i + 1];
      final linkedOffering = parseOffering(resultRows, offeringIndices[i], end);
      if (linkedOffering == null) continue;
      offering.linkedOfferingsName = resultRows[offeringIndices[i]].querySelectorAll('td')[4].text.trim();
      offering.linkedOfferings.add(linkedOffering);
    }
    return offering;
  }
}

Offering parseOffering(List<Element> resultRows, int start, int end) {
  final rowOneCells = resultRows[start].querySelectorAll('td');

  final offering = Offering();
  switch (rowOneCells[0].text.trim()) {
    case 'OPEN':
      offering.status = Status.Open;
      break;
    case 'CLOSED':
      offering.status = Status.Closed;
      break;
    case 'WAITLIST':
      offering.status = Status.Closed;
      break;
    // CANCELLED
    default:
      return null;
  }
  offering.crn = rowOneCells[1].text.trim();
  offering.sectionNumber = rowOneCells[3].text.trim();
  if (rowOneCells[6].text.trim().isNotEmpty) {
    offering.instructors = rowOneCells[6].text.trim().split(';');
    offering.instructors.forEach((i) => i.trim());
  }
  offering.classTimes = parseClassTimes(rowOneCells);

  return offering;
}

List<ClassTime> parseClassTimes(List<Element> rowOneCells) {
  final classTimes = List<ClassTime>();
  final locations = rowOneCells[7].text.trim().split('AND');
  final dayTimes = rowOneCells[8].text.trim().split('AND');
  final count = min(locations.length, dayTimes.length);

  for (var i = 0; i < count; ++i) {
    final classTime = ClassTime();
    // TODO: figure out why some locations and times are dif length
    classTime.location = locations[i];
    final dayTime = dayTimes[i];
    final index = dayTime.indexOf(RegExp('[0-9]'));
    final days = dayTime.substring(0, index);
    final timeRange = dayTime.substring(index, dayTime.length).split('-');

    classTime.sun = days.contains('U');
    classTime.mon = days.contains('M');
    classTime.tues = days.contains('T');
    classTime.weds = days.contains('W');
    classTime.thur = days.contains('R');
    classTime.fri = days.contains('F');
    classTime.sat = days.contains('S');

    classTime.startTime = parseTime(timeRange[0]);
    classTime.endTime = parseTime(timeRange[1]);

    classTimes.add(classTime);
  }
  return classTimes;
}

TimeOfDay parseTime(String time) {
  final split = time.trim().split(':');
  var hours = int.parse(split[0]);
  var minutes = int.parse(split[1].substring(0, 2));
  final amPm = split[1].substring(2, 4);
  if (amPm == 'PM' && hours != 12) {
    hours += 12;
  }
  return TimeOfDay(hour: hours, minute: minutes);
}
