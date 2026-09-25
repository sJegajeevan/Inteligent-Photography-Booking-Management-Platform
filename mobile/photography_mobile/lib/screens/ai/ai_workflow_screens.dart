import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/ai_workflow.dart';
import '../../services/ai_workflow_service.dart';

class AiWorkflowsScreen extends StatefulWidget {
  const AiWorkflowsScreen({super.key, this.service});
  final AiWorkflowService? service;
  @override
  State<AiWorkflowsScreen> createState() => _AiWorkflowsScreenState();
}

class _AiWorkflowsScreenState extends State<AiWorkflowsScreen> {
  late final _service = widget.service ?? AiWorkflowService();
  AiWorkflowPage? _data;
  String? _error;
  bool _loading = false;
  int _page = 1;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.list(page: _page);
      if (mounted) setState(() => _data = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AiWorkflowException
              ? error.message
              : 'Unable to load recommendations.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My AI recommendations'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              FilledButton.icon(
                onPressed: () =>
                    _open(AiRequirementsScreen(service: widget.service)),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Find with AI'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Tell us about your session. Your recommended studio reviews the proposal before you book.',
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) Text(_error!, semanticsLabel: _error),
              if (!_loading && _error == null && _data?.items.isEmpty == true)
                const Text('No recommendations yet.'),
              if (_error == null)
                ...?_data?.items.map(
                  (w) => Card(
                    child: ListTile(
                      title: Text(
                        w.proposal?.packageName ?? 'Photography recommendation',
                      ),
                      subtitle: Text(
                        '${w.label}\nProposal version ${w.version}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(
                        AiWorkflowStatusScreen(
                          workflowId: w.id,
                          initial: w,
                          service: widget.service,
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _loading || _page == 1
                        ? null
                        : () {
                            _page--;
                            _load();
                          },
                    child: const Text('Previous'),
                  ),
                  Text('Page $_page'),
                  TextButton(
                    onPressed:
                        _loading ||
                            _error != null ||
                            _data?.hasMore != true ||
                            _page >= 10000
                        ? null
                        : () {
                            _page++;
                            _load();
                          },
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AiRequirementsScreen extends StatefulWidget {
  const AiRequirementsScreen({super.key, this.service});
  final AiWorkflowService? service;
  @override
  State<AiRequirementsScreen> createState() => _AiRequirementsScreenState();
}

class _AiRequirementsScreenState extends State<AiRequirementsScreen> {
  late final _service = widget.service ?? AiWorkflowService();
  final _fields = {
    for (final name in [
      'type',
      'location',
      'budget',
      'earliest',
      'latest',
      'hours',
      'start',
      'end',
      'services',
    ])
      name: TextEditingController(),
  };
  bool _submitting = false,
      _processing = false,
      _uncertain = false,
      _submitted = false;
  String? _error;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    for (final field in _fields.values) {
      field.dispose();
    }
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _chooseDate(String key) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = AiRequirements.date(_fields[key]!.text);
    final value = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 3, 12, 31),
      initialDate:
          current != null &&
              !current.isBefore(today) &&
              current.year <= today.year + 3
          ? current
          : today,
    );
    if (mounted && value != null) {
      _fields[key]!.text = value.toIso8601String().split('T').first;
    }
  }

  Future<void> _submit() async {
    if (_submitting || _uncertain || _submitted) return;
    final requirements = AiRequirements(
      photographyType: _fields['type']!.text,
      location: _fields['location']!.text,
      budget: _fields['budget']!.text,
      earliestDate: _fields['earliest']!.text,
      latestDate: _fields['latest']!.text,
      coverageHours: _fields['hours']!.text,
      preferredStart: _fields['start']!.text,
      preferredEnd: _fields['end']!.text,
      services: _fields['services']!.text,
    );
    final invalid = requirements.validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _submitting = true;
      _processing = false;
      _error = null;
    });
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _processing = true);
    });
    try {
      final workflow = await _service.submit(requirements);
      if (!mounted) {
        return;
      }
      _timer?.cancel();
      setState(() {
        _submitting = false;
        _submitted = true;
      });
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => AiWorkflowStatusScreen(
            workflowId: workflow.id,
            initial: workflow,
            service: widget.service,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AiWorkflowException ? error.message : 'Unable to submit. Check My AI recommendations before trying again.';
          _uncertain = error is! AiWorkflowException || error.outcomeUnknown;
        });
      }
    } finally {
      _timer?.cancel();
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _field(
    String key,
    String label, {
    int? max,
    String? hint,
    bool number = false,
    bool date = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(key),
      controller: _fields[key],
      enabled: !_submitting && !_uncertain && !_submitted,
      maxLength: max,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : date
          ? TextInputType.datetime
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: date
            ? IconButton(
                tooltip: 'Choose $label',
                onPressed: _submitting || _uncertain || _submitted
                    ? null
                    : () => _chooseDate(key),
                icon: const Icon(Icons.calendar_today),
              )
            : null,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      appBar: AppBar(title: const Text('Find with AI')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Your photography requirements',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Prices are in LKR. Dates and preferred times use Sri Lanka time. A recommendation does not reserve a session.',
                ),
              ),
              _field(
                'type',
                'Photography type',
                max: 100,
                hint: 'Wedding, Portrait, Event…',
              ),
              _field('location', 'Location', max: 500),
              _field('budget', 'Maximum budget (LKR)', number: true),
              _field(
                'earliest',
                'Earliest date',
                hint: 'YYYY-MM-DD',
                date: true,
              ),
              _field('latest', 'Latest date', hint: 'YYYY-MM-DD', date: true),
              _field('hours', 'Coverage hours', number: true),
              _field('start', 'Preferred start (optional)', hint: 'HH:mm'),
              _field('end', 'Preferred end (optional)', hint: 'HH:mm'),
              _field(
                'services',
                'Requested services (optional)',
                hint: 'Photography, Album',
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (_submitting) const LinearProgressIndicator(),
              FilledButton(
                onPressed: _submitting || _uncertain || _submitted
                    ? null
                    : _submit,
                child: Text(
                  _submitting
                      ? (_processing ? 'Processing…' : 'Submitting…')
                      : 'Get recommendation',
                ),
              ),
              if (_submitting)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Checking studios, packages and available dates. This may take a few minutes.',
                  ),
                ),
              if (_uncertain)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Check My AI recommendations'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AiWorkflowStatusScreen extends StatefulWidget {
  const AiWorkflowStatusScreen({
    super.key,
    required this.workflowId,
    this.initial,
    this.service,
  });
  final String workflowId;
  final AiWorkflow? initial;
  final AiWorkflowService? service;
  @override
  State<AiWorkflowStatusScreen> createState() => _AiWorkflowStatusScreenState();
}

class _AiWorkflowStatusScreenState extends State<AiWorkflowStatusScreen> {
  late final _service = widget.service ?? AiWorkflowService();
  AiWorkflow? _workflow;
  String? _error, _studio;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _workflow = widget.initial;
    if (_workflow == null) {
      _load();
    } else {
      _loadName(_workflow!);
    }
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _loadName(AiWorkflow workflow) async {
    final id = workflow.proposal?.studioId;
    if (id == null) return;
    final name = await _service.studioName(id);
    if (mounted && _workflow?.proposal?.studioId == id) {
      setState(() => _studio = name);
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.get(widget.workflowId);
      if (mounted) {
        setState(() {
          _workflow = result;
          _studio = null;
        });
        unawaited(_loadName(result));
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AiWorkflowException
              ? error.message
              : 'Unable to refresh recommendation.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _workflow, p = _workflow?.proposal;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI recommendation'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '$_error Previously loaded information may be out of date.',
                    ),
                  ),
                if (w != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              w.label,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('Current step: ${w.step}'),
                          Text('Proposal version: ${w.version}'),
                          if (w.status == 'AwaitingApproval')
                            const Text(
                              'Your selected studio is reviewing this recommendation. Refresh to see its decision.',
                            ),
                          if (w.status == 'Approved')
                            const Text(
                              'Your recommendation was approved. No booking has been created. Book separately through the existing booking flow.',
                            ),
                          if (w.status == 'Rejected')
                            const Text(
                              'The studio rejected this recommendation. You can request a new recommendation from My AI recommendations.',
                            ),
                          if (w.status == 'RevalidationRequired')
                            const Text(
                              'The recommendation needs to be refreshed because availability or pricing has changed. You can submit new requirements from My AI recommendations.',
                            ),
                          if (w.status == 'Failed')
                            const Text(
                              'We could not complete this recommendation. No booking was created.',
                            ),
                          if (w.status == 'NeedsInput')
                            const Text(
                              'Please review your requirements and submit a new recommendation request.',
                            ),
                          if (p != null) ...[
                            const Divider(height: 32),
                            Text(
                              'Studio: ${_studio ?? 'Selected studio (name unavailable)'}',
                            ),
                            Text('Package: ${p.packageName}'),
                            Text(p.summary),
                            Text('Date: ${p.date}'),
                            Text('Time: ${p.start}–${p.end} (Sri Lanka)'),
                            Text(
                              'Authoritative price: LKR ${p.price.toStringAsFixed(2)}',
                            ),
                            Text(
                              'Customization: ${p.extraHours} extra hours, ${p.additionalPhotographers} additional photographers',
                            ),
                            Text(
                              'Proposal expires: ${w.expiresAt.toUtc().toIso8601String()} (UTC)',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh status'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
