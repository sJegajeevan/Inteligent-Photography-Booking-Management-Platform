import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/ai_workflow.dart';
import '../../services/ai_workflow_service.dart';
import '../booking/my_bookings_screen.dart';
import 'ai_workflow_progress.dart';
import 'ai_journey_view.dart';

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
                  'Find a session for you. Studio approval creates your booking.',
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
                      subtitle: Text(w.label),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(
                        AiWorkflowStatusScreen(
                          workflowId: w.id,
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
  bool _submitting = false, _uncertain = false, _submitted = false;
  String? _error;
  Map<String, String> _fieldErrors = {};
  @override
  void dispose() {
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
      helpText: key == 'earliest'
          ? 'Choose your earliest date'
          : 'Choose your latest date',
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
    final invalid = requirements.fieldErrors();
    setState(() => _fieldErrors = invalid);
    if (invalid.isNotEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final workflow = await _service.submit(requirements);
      if (!mounted) {
        return;
      }
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
      textInputAction: key == 'services'
          ? TextInputAction.done
          : TextInputAction.next,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : date
          ? TextInputType.datetime
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: _fieldErrors[key],
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Your photography requirements',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(
                    avatar: Icon(Icons.radio_button_checked, size: 16),
                    label: Text('Requirements'),
                  ),
                  Chip(label: Text('Studio')),
                  Chip(label: Text('Package')),
                  Chip(label: Text('Schedule')),
                  Chip(label: Text('Validate')),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Tell us what you need and AI will find a suitable studio, package and available time.',
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
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Text(
                  'When is your session? · Sri Lanka time',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
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
              if (_submitting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(
                    semanticsLabel: 'Finding the best match for you',
                  ),
                ),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: _submitting || _uncertain || _submitted
                    ? null
                    : _submit,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _submitting
                        ? 'Finding the best match for you...'
                        : 'Find Studios with AI',
                  ),
                ),
              ),
              if (_submitting)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'This may take a moment. Please keep this screen open.',
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
  String? _runningStage;
  String? _pendingAction;

  Future<void> _act(String action, String? option) async {
    if (_loading || _workflow?.journey == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _pendingAction = action;
      _runningStage = const {
        'studio': 'PackageRecommendation',
        'package': 'Scheduling',
        'schedule': 'Validation',
      }[action];
    });
    try {
      final result = await _service.journeyAction(
        widget.workflowId,
        action,
        _workflow!.journey!['revision'] as int,
        optionEventId: option,
      );
      if (mounted) setState(() => _workflow = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AiWorkflowException
              ? error.message
              : 'Unable to continue. Refresh your saved journey.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _runningStage = null;
          _pendingAction = null;
        });
      }
    }
  }

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
    if (w?.journey != null) {
      return AiJourneyView(
        workflow: w!,
        busy: _loading,
        runningStage: _runningStage,
        loadingMessage: _loading && _pendingAction == null
            ? 'Refreshing your saved journey…'
            : _pendingAction == 'submit'
            ? 'Sending for studio approval…'
            : null,
        error: _error,
        onAction: _act,
        onRefresh: _load,
      );
    }
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final expiry = w?.expiresAt.toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
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
                          Text(
                            'AI Recommendation',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 20),
                          AiWorkflowProgress(workflow: w, studioName: _studio),
                          if (p != null)
                            detail('Photography requirement', p.summary),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              w.label,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (w.status == 'AwaitingApproval')
                            const Text(
                              'Your recommendation has been sent to the studio for review.',
                            ),
                          if (w.status == 'Approved') ...[
                            Text(
                              'Recommendation approved',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Your booking has been created successfully.',
                            ),
                          ],
                          if (w.status == 'Rejected')
                            const Text('Recommendation was not approved.'),
                          if (w.status == 'RevalidationRequired')
                            const Text(
                              'Availability or pricing has changed. Please create a new recommendation.',
                            ),
                          if (w.status == 'Failed')
                            const Text(
                              'AI recommendations are temporarily unavailable. Please try again later.',
                            ),
                          if (w.status == 'NeedsInput')
                            const Text(
                              'Please review your requirements and submit a new recommendation request.',
                            ),
                          if (w.status == 'Expired')
                            const Text(
                              'This recommendation has expired. Please create a new recommendation.',
                            ),
                          if (w.label == 'Processing') Text(w.step),
                          if (w.status == 'AwaitingApproval' &&
                              expiry != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Available for review until ${localizations.formatMediumDate(expiry)}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(expiry), alwaysUse24HourFormat: false)} (Sri Lanka time)',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (w?.status == 'Approved')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const MyBookingsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.event_note_outlined),
                    label: const Text('Go to My Bookings'),
                  ),
                if ([
                  'Rejected',
                  'Expired',
                  'RevalidationRequired',
                  'NeedsInput',
                ].contains(w?.status))
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => Navigator.of(context)
                        .pushReplacement<void, void>(
                          MaterialPageRoute(
                            builder: (_) =>
                                AiRequirementsScreen(service: widget.service),
                          ),
                        ),
                    child: const Text('Create a new recommendation'),
                  ),
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
