// lib/models/process_slip_model.dart

class ProcessSlip {
  final String batteryCode;
  final String batteryFrom;
  final String batteryTo;
  final String pidNumber;
  final String clnNumber;
  final List<ProcessSlipRow> rows;
  final List<String> workstationRoles;

  ProcessSlip({
    required this.batteryCode,
    required this.batteryFrom,
    required this.batteryTo,
    required this.pidNumber,
    required this.clnNumber,
    required this.rows,
    this.workstationRoles = const [],
  });

  factory ProcessSlip.fromJson(Map<String, dynamic> json) {
    return ProcessSlip(
      batteryCode: json['batteryCode']?.toString() ?? '',
      batteryFrom: json['batteryFrom']?.toString() ?? '',
      batteryTo: json['batteryTo']?.toString() ?? '',
      pidNumber: json['pidNumber']?.toString() ?? '',
      clnNumber: json['clnNumber']?.toString() ?? '',
      rows: (json['rows'] as List? ?? [])
          .map((r) => ProcessSlipRow.fromJson(r))
          .toList(),
      workstationRoles: (json['workstation_roles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class ProcessSlipRow {
  final String type;
  final String name;
  final String lot;
  final String dia;
  final String wtT;
  final String wtTol;
  final String thT;
  final String thTol;
  final String press;
  final String time;

  ProcessSlipRow({
    required this.type,
    required this.name,
    required this.lot,
    required this.dia,
    required this.wtT,
    required this.wtTol,
    required this.thT,
    required this.thTol,
    required this.press,
    required this.time,
  });

  factory ProcessSlipRow.fromJson(Map<String, dynamic> json) {
    return ProcessSlipRow(
      type: json['type']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      lot: json['lot']?.toString() ?? '',
      dia: json['dia']?.toString() ?? '',
      wtT: json['wtT']?.toString() ?? '',
      wtTol: json['wtTol']?.toString() ?? '',
      thT: json['thT']?.toString() ?? '',
      thTol: json['thTol']?.toString() ?? '',
      press: json['press']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
    );
  }
}
