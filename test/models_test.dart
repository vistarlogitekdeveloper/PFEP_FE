/// Parsing and derived-value tests for the models the API fills in.
///
/// These are the places where a backend field rename fails quietly: the JSON
/// key stops matching, the value falls back to its default, and the UI shows a
/// confident zero instead of an error. Each test below pins one of those.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pfep_frontend/models/models.dart';

void main() {
  group('Customer', () {
    // The exact payload GET /customers and GET /auth/me return. Note the mix of
    // snake_case columns and camelCase computed fields - that is the server's
    // shape, not a tidy-up waiting to happen.
    Map<String, dynamic> json({Map<String, dynamic>? over}) => {
          'id': 'AXN',
          'name': 'Axion Motors - Plant 2, Chennai',
          'program': 'SUV-X1',
          'status': 'Live',
          'start_date': '2026-08-24',
          'target_date': '2026-09-20',
          'plan_per_day': 300,
          'work_days': 26,
          'shift_hrs': 8,
          'totalRecords': 21,
          'byStatus': {'Approved': 9, 'Submitted': 4, 'Pending': 4, 'In Progress': 3, 'Rejected': 1},
          ...?over,
        };

    test('parses the record counts the progress bars read', () {
      final c = Customer.fromJson(json());
      expect(c.totalRecords, 21);
      expect(c.approved, 9);
      expect(c.planPerDay, 300);
      expect(c.workDays, 26);
    });

    test('progress counts approved and submitted as captured', () {
      // 9 approved + 4 submitted of 21 = 61.9% -> 62
      expect(Customer.fromJson(json()).progressPct, 62);
    });

    test('a customer with no records reports 0%, not a division by zero', () {
      final c = Customer.fromJson(json(over: {'totalRecords': 0, 'byStatus': <String, dynamic>{}}));
      expect(c.totalRecords, 0);
      expect(c.approved, 0);
      expect(c.progressPct, 0);
    });

    test('missing counts default to zero rather than throwing', () {
      final c = Customer.fromJson({'id': 'HMX', 'name': 'Helix', 'status': 'Setup'});
      expect(c.totalRecords, 0);
      expect(c.approved, 0);
      expect(c.progressPct, 0);
    });
  });

  group('PartVendor assignment lock', () {
    PartVendor v({String? assignedTo}) => PartVendor.fromJson({
          'id': 'V-1155',
          'name': 'Everest Diecast',
          'city': 'Coimbatore',
          'distanceKm': 500,
          'recordId': 'rec_1',
          'recordStatus': 'Pending',
          'assignedTo': assignedTo,
          'assignedName': assignedTo == null ? null : 'Priya Nair',
        });

    test('a row assigned to someone else is locked', () {
      expect(v(assignedTo: 'u_priya').lockedFor('u_sandeep'), isTrue);
    });

    test('my own row is not locked', () {
      expect(v(assignedTo: 'u_sandeep').lockedFor('u_sandeep'), isFalse);
    });

    test('an unassigned row is open to anyone', () {
      expect(v().lockedFor('u_sandeep'), isFalse);
    });

    test('an unknown viewer does not lock rows (nothing to compare against)', () {
      expect(v(assignedTo: 'u_priya').lockedFor(null), isFalse);
    });

    test('carries the name so the UI can say who holds it', () {
      expect(v(assignedTo: 'u_priya').assignedName, 'Priya Nair');
    });
  });

  group('FieldSection', () {
    test('parses fields and the wider-PFEP presets separately', () {
      final s = FieldSection.fromJson({
        'key': 'vendor',
        'label': 'Vendor / Supplier',
        'photo': 'supplier',
        'fields': [
          {'key': 'vloc', 'label': 'Vendor Location / City', 'type': 'text', 'required': 1, 'enabled': 1},
          {'key': 'km', 'label': 'Distance from Plant', 'type': 'number', 'unit': 'km', 'required': 1, 'enabled': 1},
        ],
        'availableExtras': [
          {'key': 'unload', 'label': 'Unloading Method', 'type': 'select',
           'options': ['Manual', 'MHE', 'Forklift', 'Reach Truck', 'Crane']},
        ],
      });

      expect(s.fields.length, 2);
      expect(s.availableExtras.length, 1);
      expect(s.availableExtras.first.key, 'unload');
      expect(s.availableExtras.first.options, hasLength(5));
    });

    test('a section with no presets left still parses', () {
      final s = FieldSection.fromJson({
        'key': 'line', 'label': 'Line-Side Supply', 'photo': 'lineside', 'fields': [],
      });
      expect(s.availableExtras, isEmpty);
    });
  });

  group('FieldDef', () {
    test('renders label with unit the way the prototype writes it', () {
      final f = FieldDef.fromJson(
        {'key': 'km', 'label': 'Distance from Plant', 'type': 'number', 'unit': 'km', 'required': 1, 'enabled': 1},
      );
      expect(f.labelWithUnit, 'Distance from Plant (km)');
    });

    test('a field without a unit is left alone', () {
      final f = FieldDef.fromJson(
        {'key': 'vloc', 'label': 'Vendor Location / City', 'type': 'text', 'required': 1, 'enabled': 1},
      );
      expect(f.labelWithUnit, 'Vendor Location / City');
    });

    test('booleans parse from the API shape', () {
      final f = FieldDef.fromJson(
        {'key': 'vloc', 'label': 'Vendor Location', 'type': 'text', 'required': true, 'enabled': true},
      );
      expect(f.required, isTrue);
      expect(f.enabled, isTrue);
    });

    // The server maps these to real booleans, but anything handing over a raw
    // SQLite row sends 0/1. Parsing only one shape would quietly report every
    // field as optional, which is worse than failing.
    test('booleans also parse from SQLite 0/1', () {
      final on = FieldDef.fromJson(
        {'key': 'km', 'label': 'Distance', 'type': 'number', 'required': 1, 'enabled': 1},
      );
      expect(on.required, isTrue);
      expect(on.enabled, isTrue);

      final off = FieldDef.fromJson(
        {'key': 'pallets', 'label': 'Pallets per Truck', 'type': 'number', 'required': 0, 'enabled': 0},
      );
      expect(off.required, isFalse);
      expect(off.enabled, isFalse);
    });

    test('a field with no enabled key defaults to enabled, not hidden', () {
      final f = FieldDef.fromJson({'key': 'x', 'label': 'X', 'type': 'text'});
      expect(f.enabled, isTrue);
      expect(f.required, isFalse);
    });
  });
}
