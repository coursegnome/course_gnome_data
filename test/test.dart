@TestOn('vm')

import 'dart:io';

import 'package:test/test.dart';

import 'package:core/core.dart';
import 'package:course_gnome_scrape/GWUParser.dart';

void main() {
//  test('Function completes succesfully', () {
//    final courseResult =
//        parse(courseString).getElementsByClassName('courseListing')[0];
//    final resultRows = courseResult.getElementsByClassName('coursetable');
//    final course = parseCourse(resultRows[0]);
//    final offering = parseOfferingRows(resultRows);
//  });
  test('Normal course', () async {
    final List<Course> courses = await loadCourses('normal.html');
    final Course course = courses.first;
    expect(course.departmentAcronym, 'ACCY');
    expect(course.name, 'Introduction to Financial Accounting');
    expect(course.bulletinLink, 'http://bulletin.gwu.edu/search/?P=ACCY+2001');
    expect(course.credit, '3.00');
    expect(course.departmentNumber, '2001');
    expect(course.description,
        'Fundamental concepts underlying financial statements and the informed use of accounting information; analysis and recording of business transactions; preparation and understanding of financial statements; measurement of the profitability and financial position of a business. Restricted to sophomores.');
    expect(course.offerings.length, 1);

    final Offering offering = course.offerings.first;
    expect(offering.days, [false, false, true, false, true, false, false]);
    expect(offering.latestEndTime, TimeOfDay(hour: 21, minute: 5));
    expect(offering.earliestStartTime, TimeOfDay(hour: 18, minute: 10));
    expect(offering.linkedOfferings, isNull);
    expect(offering.linkedOfferingsName, isNull);
    expect(offering.status, Status.Open);
    expect(offering.crn, '10704');
    expect(offering.sectionNumber, '10');
    expect(offering.instructors, ['Tarpley, R']);
    expect(offering.fee, isNull);
    expect(offering.comments,
        'Once this course has closed, an electronic waitlist will be available. Please see: http://go.gwu.edu/waitlist for more information.');
    expect(offering.findBooksLink,
        'http://www.bkstr.com/webapp/wcs/stores/servlet/booklookServlet?bookstore_id-1=122&term_id-1=201902&div-1=&dept-1=ACCY&course-1=2001&section-1=10');
    expect(offering.courseAttributes, ['CCPR']);
    expect(offering.classTimes.length, 1);

    final ClassTime classTime = offering.classTimes.first;
    expect(classTime.days, [false, false, true, false, true, false, false]);
    expect(classTime.endTime, TimeOfDay(hour: 21, minute: 5));
    expect(classTime.startTime, TimeOfDay(hour: 18, minute: 10));
    expect(classTime.location, 'DUQUES 152');
  });

  test('Multiple class times', () async {
    final List<Course> courses = await loadCourses('multiday.html');
    final Offering offering = courses.first.offerings.first;
    expect(offering.days, [false, false, true, false, true, false, false]);
    expect(offering.earliestStartTime, TimeOfDay(hour: 11, minute: 10));
    expect(offering.latestEndTime, TimeOfDay(hour: 17, minute: 0));
    expect(offering.classTimes.length, 2);
    expect(
        offering.classTimes.every((ct) => ct.location == 'SEH 8750'), isTrue);
    expect(offering.fee, 'BiSc Lab Fee \$55.00');
  });

  test('Linked offerings', () async {
    final List<Course> courses = await loadCourses('linkedofferings.html');
    final Offering offering = courses.first.offerings.first;
    expect(offering.linkedOfferings.length, 4);
    expect(offering.linkedOfferingsName, 'Laboratory');
    expect(offering.linkedOfferings[0].sectionNumber, '40');
    expect(offering.linkedOfferings[1].sectionNumber, '41');
    expect(offering.linkedOfferings[2].sectionNumber, '42');
    expect(offering.linkedOfferings[3].sectionNumber, '43');
  });

  test('Multiple offerings', () async {
    final List<Course> courses = await loadCourses('multioffering.html');
    final Course course = courses.first;
    expect(course.offerings.length, 3);
    expect(course.name, 'Principles of Economics II');
  });

  test('Location but no times', () async {
    final List<Course> courses = await loadCourses('notimes.html');
    final ClassTime classTime = courses.first.offerings.first.classTimes.first;
    expect(classTime.location, 'ON LINE');
    expect(classTime.startTime, isNull);
    expect(classTime.endTime, isNull);
    expect(classTime.days, isNull);
  });
}

Future<List<Course>> loadCourses(String fileSuffix) async {
  const basePath = 'test/html/';
  final courseString = await File(basePath + fileSuffix).readAsString();
  return await GWUParser.parseResponse(courseString, []);
}
