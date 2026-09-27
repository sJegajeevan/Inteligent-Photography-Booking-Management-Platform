const workflowLabels = <String, String>{
  'Submitted': 'Processing',
  'StudioMatching': 'Processing',
  'PackageRecommendation': 'Processing',
  'Scheduling': 'Processing',
  'Validation': 'Processing',
  'AwaitingApproval': 'Awaiting Approval',
  'Approved': 'Approved',
  'Rejected': 'Rejected',
  'RevalidationRequired': 'Revalidation Required',
  'Failed': 'Failed',
  'NeedsInput': 'More information needed',
  'Cancelled': 'Cancelled',
  'Expired': 'Expired',
};
final workflowIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class AiRequirements {
  const AiRequirements({
    required this.photographyType,
    required this.location,
    required this.budget,
    required this.earliestDate,
    required this.latestDate,
    required this.coverageHours,
    this.preferredStart = '',
    this.preferredEnd = '',
    this.services = '',
  });
  final String photographyType,
      location,
      budget,
      earliestDate,
      latestDate,
      coverageHours,
      preferredStart,
      preferredEnd,
      services;

  static DateTime? date(String value) {
    final parsed = DateTime.tryParse(value);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
            parsed != null &&
            parsed.toIso8601String().split('T').first == value
        ? parsed
        : null;
  }

  String? validate() => fieldErrors().values.firstOrNull;

  Map<String, String> fieldErrors() {
    final errors = <String, String>{};
    if (photographyType.trim().isEmpty || photographyType.trim().length > 100) {
      errors['type'] = 'Enter a photography type (up to 100 characters).';
    }
    if (location.trim().isEmpty || location.trim().length > 500) {
      errors['location'] = 'Enter a location (up to 500 characters).';
    }
    final amount = double.tryParse(budget.trim());
    if (amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > 9999999999999999.99) {
      errors['budget'] = 'Enter a budget greater than zero in LKR.';
    }
    final hours = double.tryParse(coverageHours.trim());
    if (hours == null || !hours.isFinite || hours < .01 || hours > 24) {
      errors['hours'] = 'Enter between 0.01 and 24 coverage hours.';
    }
    final first = date(earliestDate), last = date(latestDate);
    if (first == null) errors['earliest'] = 'Choose a valid earliest date.';
    if (last == null) errors['latest'] = 'Choose a valid latest date.';
    if (first != null && last != null) {
      if (last.isBefore(first)) {
        errors['latest'] = 'Latest date cannot be before earliest date.';
      } else if (last.difference(first).inDays >= 31) {
        errors['latest'] = 'Choose a date range of up to 31 days.';
      }
    }
    final time = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
    if ((preferredStart.isNotEmpty || preferredEnd.isNotEmpty) &&
        (!time.hasMatch(preferredStart) ||
            !time.hasMatch(preferredEnd) ||
            preferredStart.compareTo(preferredEnd) >= 0)) {
      errors['start'] = 'Enter both times as HH:mm, with end after start.';
      errors['end'] = errors['start']!;
    }
    final requested = services.trim().isEmpty
        ? <String>[]
        : services.split(',').map((s) => s.trim()).toList();
    if (requested.length > 20 ||
        requested.any((s) => s.isEmpty || s.length > 120)) {
      errors['services'] = 'Enter up to 20 services, each 1–120 characters.';
    }
    return errors;
  }

  Map<String, dynamic> toJson() {
    if (validate() != null) throw const FormatException('Invalid requirements');
    return {
      'photographyType': photographyType.trim(),
      'location': location.trim(),
      'maximumBudget': double.parse(budget.trim()),
      'earliestDate': earliestDate,
      'latestDate': latestDate,
      'coverageHours': double.parse(coverageHours.trim()),
      'preferredStartTime': preferredStart.isEmpty
          ? null
          : '$preferredStart:00',
      'preferredEndTime': preferredEnd.isEmpty ? null : '$preferredEnd:00',
      'requestedServices': services.trim().isEmpty
          ? <String>[]
          : services.split(',').map((s) => s.trim()).toSet().toList(),
    };
  }
}

class AiProposal {
  const AiProposal({
    required this.studioId,
    required this.packageName,
    required this.date,
    required this.start,
    required this.end,
    required this.price,
    required this.extraHours,
    required this.additionalPhotographers,
    required this.summary,
    this.addonNames = const [],
  });
  final String studioId, packageName, date, start, end, summary;
  final double price;
  final int extraHours, additionalPhotographers;
  final List<String> addonNames;
}

class AiWorkflow {
  const AiWorkflow({
    required this.id,
    required this.status,
    required this.step,
    required this.version,
    required this.expiresAt,
    this.proposal,
  });
  final String id, status, step;
  final int version;
  final DateTime expiresAt;
  final AiProposal? proposal;
  String get label => workflowLabels[status]!;

  factory AiWorkflow.fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        !workflowIdPattern.hasMatch(value['id']) ||
        !workflowLabels.containsKey(value['status']) ||
        value['proposalVersion'] is! int ||
        value['proposalVersion'] < 0 ||
        value['expiresAt'] is! String ||
        DateTime.tryParse(value['expiresAt']) == null) {
      throw const FormatException();
    }
    AiProposal? proposal;
    final p = value['proposal'];
    if (p != null) {
      if (p is! Map<String, dynamic>) throw const FormatException();
      final s = p['selection'], price = p['pricing'], r = p['requirements'];
      if (s is! Map<String, dynamic> ||
          price is! Map<String, dynamic> ||
          r is! Map<String, dynamic> ||
          p['version'] != value['proposalVersion'] ||
          s['studioId'] != value['selectedStudioId'] ||
          s['packageId'] != value['selectedPackageId'] ||
          s['studioId'] is! String ||
          !workflowIdPattern.hasMatch(s['studioId']) ||
          s['date'] is! String ||
          AiRequirements.date(s['date']) == null ||
          s['startTime'] is! String ||
          s['endTime'] is! String ||
          !RegExp(r'^\d{2}:\d{2}:\d{2}(\.\d+)?$').hasMatch(s['startTime']) ||
          !RegExp(r'^\d{2}:\d{2}:\d{2}(\.\d+)?$').hasMatch(s['endTime']) ||
          price['packageName'] is! String ||
          price['packageName'].isEmpty ||
          price['finalPrice'] is! num ||
          !price['finalPrice'].isFinite ||
          price['finalPrice'] < 0 ||
          r['photographyType'] is! String ||
          r['location'] is! String ||
          s['customization'] is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final c = s['customization'] as Map<String, dynamic>;
      if (c['extraHours'] is! int ||
          c['extraHours'] < 0 ||
          c['additionalPhotographers'] is! int ||
          c['additionalPhotographers'] < 0) {
        throw const FormatException();
      }
      proposal = AiProposal(
        studioId: s['studioId'],
        packageName: price['packageName'],
        date: s['date'],
        start: s['startTime'].substring(0, 5),
        end: s['endTime'].substring(0, 5),
        price: (price['finalPrice'] as num).toDouble(),
        extraHours: c['extraHours'],
        additionalPhotographers: c['additionalPhotographers'],
        summary: '${r['photographyType']} in ${r['location']}',
        addonNames: price['selectedAddons'] is List
            ? (price['selectedAddons'] as List).whereType<Map>().map((addon) {
                final name = addon['name'];
                return name is String && name.trim().isNotEmpty
                    ? name.trim()
                    : 'Add-on';
              }).toList()
            : const [],
      );
    }
    if ([
          'AwaitingApproval',
          'Approved',
          'Rejected',
        ].contains(value['status']) &&
        proposal == null) {
      throw const FormatException();
    }
    const steps = {
      'Submitted': 'Submitted',
      'StudioMatching': 'Finding studios',
      'PackageRecommendation': 'Comparing packages',
      'Scheduling': 'Checking dates',
      'Validation': 'Checking recommendation',
      'HumanApproval': 'Studio review',
      'Completed': 'Review completed',
      'Failed': 'Unable to complete',
    };
    return AiWorkflow(
      id: value['id'],
      status: value['status'],
      step: steps[value['currentStep']] ?? workflowLabels[value['status']]!,
      version: value['proposalVersion'],
      expiresAt: DateTime.parse(value['expiresAt']),
      proposal: proposal,
    );
  }
}

class AiWorkflowPage {
  const AiWorkflowPage(this.items, this.hasMore);
  final List<AiWorkflow> items;
  final bool hasMore;
}
