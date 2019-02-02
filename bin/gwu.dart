import 'dart:math';

import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:algolia/algolia.dart';

import 'package:course_gnome/model/Course.dart';
import 'config.dart';

final courses = List<Course>();

void main() async {
//  const url = 'https://my.gwu.edu/mod/pws/searchresults.cfm';
  const url = 'https://us-central1-course-gnome.cloudfunctions.net/getHTML';
  const spring2019Code = '201901';
  const summer2019Code = '201902';
  const mainCampusCode = '1';
  const maxEndIndex = 10000;
  const currentCode = summer2019Code;

  final client = http.Client();

  var startIndex = 1000;
  var endIndex = 1499;

  while (endIndex < maxEndIndex) {
    print('Range: $startIndex, $endIndex');
    var pageNum = 1;
    var lastPage = false;
    do {
      print('Page: $pageNum');
//      final body = {
//        'srchType': 'All',
//        'term': summer2019Code,
//        'campus': mainCampusCode,
//        'courseNumSt': startIndex.toString(),
//        'courseNumEn': endIndex.toString(),
//        'pageNum': pageNum.toString(),
//      };
      final body = {
        'term': currentCode,
        'start': startIndex.toString(),
        'end': endIndex.toString(),
        'page': pageNum.toString(),
      };
      try {
        final response = await client.post(url, body: body);
        lastPage = parseResponse(response);
      } catch (e) {
        print(e);
        return;
      }
      ++pageNum;
    } while (lastPage);
    startIndex += 500;
    endIndex += 500;
  }
  print('Done scraping!');
  client.close();
  uploadCourses();
}

bool parseResponse(http.Response response) {
  final results = parse(response.body).getElementsByClassName('courseListing');
  for (final result in results) {
    final resultRows = result.getElementsByClassName('coursetable');
    final course = parseCourse(resultRows[0]);
    final offering = parseOfferingRows(resultRows);
    if (offering == null) continue;
    course.offerings.add(offering);
  }
  return response.body.contains('Next Page');
}

Course parseCourse(Element elm) {
  final cells = elm.querySelectorAll('td');
  final depAcr = cells[2].querySelector('span').text.trim();
  final depNumber = cells[2].querySelector('a').text.trim();
  final name = cells[4].text.trim();
  final courseIndex = courses.indexWhere((c) =>
      c.departmentNumber == depNumber &&
      c.departmentAcronym == depAcr &&
      c.name == name);
  if (courseIndex != -1) {
    return courses[courseIndex];
  } else {
    final course = Course(
      name: name,
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
      offering.linkedOfferingsName =
          resultRows[offeringIndices[i]].querySelectorAll('td')[4].text.trim();
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

  final rowTwoCells = resultRows[start+1].children;

  final leftCells = rowTwoCells[0].querySelectorAll('div');
  for (final cell in leftCells) {
    if (cell.text.contains('Comments:')) {
      final comment = cell.text.trim();
      offering.comments = comment.substring(10, comment.length);
      continue;
    }
    if (cell.querySelector('tbody') != null) {
      offering.courseAttributes = [];
      final attributes = cell.querySelector('tbody').querySelectorAll('tr');
      for (final attr in attributes) {
        offering.courseAttributes.add(attr.text.trim().split(':').first);
      }
    }
  }

  if (rowTwoCells.length == 3) {
    offering.findBooksLink = rowTwoCells[2].querySelector('a').attributes['href'];
  }

  if (start+2 == end) {
    return offering;
  }

  final feeRows = resultRows[start+2].querySelectorAll('td');
  offering.fee = feeRows[1].text.trim() + ' ' + feeRows[2].text.trim();

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
    if (dayTime.isEmpty) {
      classTimes.add(classTime);
      continue;
    }
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

uploadCourses() async {
  final Algolia algolia = await Algolia.init(
    applicationId: '4AISU681XR',
    apiKey: AlgoliaConfig.apiKey
  );
  await algolia.instance.index('gwu').clearIndex();
  AlgoliaBatch batch = algolia.instance.index('gwu').batch();
  batch.clearIndex();
  for (final course in courses) {
    batch.addObject(course.toJson());
  }
  await batch.commit();
  print('Done uploading!');
}
