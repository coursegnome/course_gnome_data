import 'dart:io';
import 'dart:math';

import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;

import 'package:core/core.dart';

Future<List<SearchOffering>> scrapeCourses(Season season) async {
  print('Scraping courses for season: ${season.id}');

  const String url =
      'https://us-central1-course-gnome.cloudfunctions.net/getHTML';
  final String seasonCode = _getSeasonCode(season);
  const int maxEndIndex = 10000;
  final http.Client client = http.Client();
  final int indexIncrement = season == Season.summer2019 ? 500 : 100;
  int startIndex = 1000;
  int endIndex = season == Season.summer2019 ? 1499 : 1099;

  final Stopwatch stopwatch = Stopwatch()..start();

  // Set up cache
  final Directory cacheDir = Directory('lib/cache/gwu/${season.id}')..create();

  List<SearchOffering> offerings = <SearchOffering>[];

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
        if (true) {
          final http.Response response = await client.post(url, body: body);
          file.writeAsString(response.body);
          html = response.body;
        } else {
          html = file.readAsStringSync();
        }
        offerings.addAll(await parseResponse(html, season));
        lastPage = html.contains('Next Page');
      } catch (e) {
        print(e);
        return null;
      }
      ++pageNum;
    } while (lastPage);
    startIndex += indexIncrement;
    endIndex += indexIncrement;
    print('Time elapsed: ${stopwatch.elapsed.inSeconds} seconds');
  }
  client.close();
  return offerings;
}

String _getSeasonCode(Season season) {
  switch (season) {
    case Season.summer2019:
      return '201902';
    case Season.fall2019:
      return '201903';
    default:
      return '201903';
  }
}

Future<List<SearchOffering>> parseResponse(
    String response, Season season) async {
  final List<Element> results =
      parse(response).getElementsByClassName('courseListing');
  final List<SearchOffering> offerings =
      await Future.wait(results.map((Element result) async {
    final SearchOffering offering = await _parseCourse(
      result.getElementsByClassName('coursetable'),
      season,
    );
    print('Parsed: ${offering.name} - ${offering.section}');
    return offering;
  }).toList());
  return offerings;
}

Future<SearchOffering> _parseCourse(
  List<Element> resultRows,
  Season season,
) async {
  try {
    final List<Element> rowOneCells = resultRows.first.querySelectorAll('td');
    final String depAcr = rowOneCells[2].querySelector('span').text.trim();
    final String depNumberText = rowOneCells[2].querySelector('a').text.trim();
    final int depNumber =
        int.parse(depNumberText.replaceAll(RegExp('[A-Za-z]'), ''));
    final String name = rowOneCells[4].text.trim();
    final String credit = rowOneCells[5].text.trim();
    final String id = rowOneCells[1].text.trim();
    final String sectionText = rowOneCells[3].text.trim();
    final int section = _parseSection(sectionText);
    final String statusString = rowOneCells.first.text.trim();
    final Status status = statusString == 'OPEN'
        ? Status.Open
        : statusString == 'CLOSED' ? Status.Closed : Status.Waitlist;
    final List<String> instructors = _parseInstructors(rowOneCells);
    final List<ClassTime> classTimes = _parseClassTimes(rowOneCells);
    final ClassTime range = _calculateTimeRange(classTimes);
    return SearchOffering(
      name: name,
      deptAcr: depAcr,
      deptNum: depNumberText,
      credit: credit,
      status: status,
      id: id,
      teachers: instructors,
      section: sectionText,
      classTimes: classTimes,
      deptNumInt: depNumber,
      sectionInt: section,
      range: range,
      deptName: '',
      school: School.gwu.id,
      season: season.id,
    );
  } catch (e, s) {
    print(s.toString());
    exit(0);
  }
}

int _parseSection(String text) {
  final String cleaned = text.replaceAll(RegExp('[A-Za-z]'), '');
  if (cleaned.isEmpty) {
    return null;
  } else {
    return int.parse(cleaned);
  }
}

Future<String> _requestDescription(String bulletinLink) async {
  final http.Response response = await http.post(bulletinLink);
  return parse(response.body)
      .getElementsByClassName('courseblockdesc')
      .first
      .text
      .trim();
}

List<String> _parseInstructors(List<Element> rowOneCells) {
  List<String> instructors;
  if (rowOneCells[6].text.trim().isNotEmpty) {
    instructors = rowOneCells[6].text.trim().split(';');
    for (String instructor in instructors) {
      instructor.trim();
    }
  }
  return instructors;
}

List<ClassTime> _parseClassTimes(List<Element> rowOneCells) {
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
        start: _parseTime(timeRange[0]),
        end: _parseTime(timeRange[1]),
        location: location.isNotEmpty ? location : null,
        u: dayList[0],
        m: dayList[1],
        t: dayList[2],
        w: dayList[3],
        r: dayList[4],
        f: dayList[5],
        s: dayList[6],
      ),
    );
  }

  return classTimes;
}

TimeOfDay _parseTime(String time) {
  final List<String> split = time.trim().split(':');
  final int minutes = int.parse(split[1].substring(0, 2));
  final String amPm = split[1].substring(2, 4);
  int hours = int.parse(split[0]);
  if (amPm == 'PM' && hours != 12) {
    hours += 12;
  }
  return TimeOfDay(hour: hours, minute: minutes);
}

ClassTime _calculateTimeRange(List<ClassTime> classTimes) {
  List<bool> dayList;
  TimeOfDay earliestStartTime;
  TimeOfDay latestEndTime;
  // Only consider ones where the days and times are not null
  final List<ClassTime> viableClassTimes =
      classTimes.where((ClassTime ct) => !ct.timeIsTBA).toList();

  if (viableClassTimes.isNotEmpty) {
    dayList = List<bool>.generate(
        7, (int i) => viableClassTimes.any((ClassTime ct) => ct.days[i]));
    earliestStartTime = viableClassTimes.fold(viableClassTimes.first.start,
        (TimeOfDay v, ClassTime e) => v < e.start ? v : e.start);
    latestEndTime = viableClassTimes.fold(viableClassTimes.first.end,
        (TimeOfDay v, ClassTime e) => v < e.end ? e.end : v);
  }

  return ClassTime(
    start: earliestStartTime,
    end: latestEndTime,
    u: dayList == null ? null : dayList[0],
    m: dayList == null ? null : dayList[1],
    t: dayList == null ? null : dayList[2],
    w: dayList == null ? null : dayList[3],
    r: dayList == null ? null : dayList[4],
    f: dayList == null ? null : dayList[5],
    s: dayList == null ? null : dayList[6],
  );
}

int _parseExtras(List<Element> resultRows) {
  final List<Element> rowOneCells = resultRows[0].querySelectorAll('td');
  final List<Element> rowTwoCells = resultRows[1].children;
  final String bulletinLink =
      rowOneCells[2].querySelector('a').attributes['href'];
  //final String description = await requestDescription(bulletinLink);
  String description;
  String fee;
  if (resultRows.length > 2 && resultRows[2].classes.contains('crseRow3')) {
    final List<Element> feeRows = resultRows[2].querySelectorAll('td');
    fee = feeRows[1].text.trim() + ' ' + feeRows[2].text.trim();
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

  /*
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
  }*/
  return 0;
}
