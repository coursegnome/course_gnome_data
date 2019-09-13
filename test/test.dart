@TestOn('vm')

import 'dart:io';

import 'package:test/test.dart';

import 'package:course_gnome_data/models.dart';
import 'package:course_gnome_data/parsers.dart' as parsers;

void main() {
  SearchOffering offering;
  test('Normal course', () async {
    final List<SearchOffering> offerings = await loadOfferings('normal.html');
    offering = offerings.first;
    expect(offering.deptAcr, 'ACCY');
    expect(offering.name, 'Introduction to Financial Accounting');
    expect(offering.credit, '3.00');
    expect(offering.deptNum, '2001');
    expect(offering.deptNumInt, 2001);
    expect(offering.status, Status.Open);
    expect(offering.id, '10704');
    expect(offering.teachers, <String>['Tarpley, R']);
    expect(offering.section, '10');
    expect(offering.sectionInt, 10);
    expect(offering.range.days,
        <bool>[false, false, true, false, true, false, false]);
    expect(offering.range.start, TimeOfDay(hour: 18, minute: 10));
    expect(offering.range.end, TimeOfDay(hour: 21, minute: 5));
    expect(offering.school, School.gwu.id);
    expect(offering.season, Season.fall2019.id);

    expect(offering.classTimes.length, 1);
    final ClassTime classTime = offering.classTimes.first;
    expect(
        classTime.days, <bool>[false, false, true, false, true, false, false]);
    expect(classTime.end, TimeOfDay(hour: 21, minute: 5));
    expect(classTime.start, TimeOfDay(hour: 18, minute: 10));
    expect(classTime.location, 'DUQUES 152');
  });

  test('toJson', () {
    offering.toJson();
  });

  test('Multiple class times', () async {
    final List<SearchOffering> offerings = await loadOfferings('multiday.html');
    final SearchOffering offering = offerings.first;
    expect(offering.range.days,
        <bool>[false, false, true, false, true, false, false]);
    expect(offering.range.start, TimeOfDay(hour: 11, minute: 10));
    expect(offering.range.end, TimeOfDay(hour: 17, minute: 0));
    expect(offering.classTimes.length, 2);
    expect(
        offering.classTimes.every((ClassTime ct) => ct.location == 'SEH 8750'),
        isTrue);
  });

  test('Linked offerings', () async {
    final List<SearchOffering> offerings =
        await loadOfferings('linkedofferings.html');
    final SearchOffering offering = offerings.first;
//    expect(offering.linkedOfferings.length, 4);
//    expect(offering.linkedOfferingsName, 'Laboratory');
//    expect(offering.linkedOfferings[0].sectionNumber, '40');
//    expect(offering.linkedOfferings[1].sectionNumber, '41');
//    expect(offering.linkedOfferings[2].sectionNumber, '42');
//    expect(offering.linkedOfferings[3].sectionNumber, '43');
  });

  test('Multiple offerings', () async {
    final List<SearchOffering> offerings =
        await loadOfferings('multioffering.html');
    final SearchOffering course = offerings.first;
    expect(offerings.length, 3);
    expect(course.name, 'Principles of Economics II');
  });

  test('Location but no times', () async {
    final List<SearchOffering> offerings = await loadOfferings('notimes.html');
    final ClassTime classTime = offerings.first.classTimes.first;
    expect(classTime.location, 'ON LINE');
    expect(classTime.start, isNull);
    expect(classTime.end, isNull);
    expect(classTime.timeIsTBA, isTrue);
  });
}

Future<List<SearchOffering>> loadOfferings(String fileSuffix) async {
  const String basePath = 'test/html/';
  final String courseString = await File(basePath + fileSuffix).readAsString();
  return await parsers.parse(
    response: courseString,
    season: Season.fall2019,
    school: School.gwu,
  );
}
