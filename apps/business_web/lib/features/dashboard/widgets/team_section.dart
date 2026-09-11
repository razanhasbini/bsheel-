import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/team_controller.dart';
import 'stat_tile.dart';

/// Who at the business can read the dashboard.
///
/// Owner-only, mirroring the API: a manager who could appoint members could
/// appoint itself an owner, which would make the two roles one role with
/// extra steps. A manager still sees the list — knowing who your colleagues
/// are is not a privilege — but not the controls.
///
/// The API supported this from #79 and nothing could reach it, which is the
/// gap this closes: an owner had to ask an admin to add their own staff.
class TeamSection extends ConsumerStatefulWidget {
  const TeamSection({super.key, required this.business});

  final BusinessSummary business;

  @override
  ConsumerState<TeamSection> createState() => _TeamSectionState();
}

class _TeamSectionState extends ConsumerState<TeamSection> {
  final _username = TextEditingController();
  BusinessMemberRole _role = BusinessMemberRole.manager;
  bool _busy = false;
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _add(List<BusinessMember> existing) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await ref.read(teamControllerProvider).add(
          widget.business.id,
          _username.text,
          role: _role,
          existing: existing,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Each outcome names its own cause, because the fix differs: a typo,
      // a duplicate, a lost permission, or a network failure.
      switch (outcome) {
        case AddMemberOutcome.added:
          _message = 'Added @${_username.text.trim()}.';
          _messageIsError = false;
          _username.clear();
        case AddMemberOutcome.unknownUsername:
          _message = 'No Bsheel account with that username.';
          _messageIsError = true;
        case AddMemberOutcome.alreadyMember:
          _message = 'That person is already on the team.';
          _messageIsError = false;
        case AddMemberOutcome.refused:
          _message = 'Only an owner can change the team.';
          _messageIsError = true;
        case AddMemberOutcome.failed:
          _message = 'Could not add them. Check your connection.';
          _messageIsError = true;
      }
    });
    if (outcome == AddMemberOutcome.added) {
      ref.invalidate(businessTeamProvider(widget.business.id));
    }
  }

  Future<void> _remove(BusinessMember member) async {
    setState(() => _busy = true);
    final ok = await ref
        .read(teamControllerProvider)
        .remove(widget.business.id, member.userId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // The server refuses to remove the last owner, which is the common
      // case here and is not a fault to apologise for.
      _message = ok
          ? 'Removed @${member.username}.'
          : 'Could not remove them. A business must keep at least one owner.';
      _messageIsError = !ok;
    });
    if (ok) ref.invalidate(businessTeamProvider(widget.business.id));
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(businessTeamProvider(widget.business.id));
    final isOwner = widget.business.isOwner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Team',
          subtitle: isOwner
              ? 'Anyone here can read this dashboard. Managers cannot change '
                  'the team; owners can.'
              : 'Anyone here can read this dashboard. Only an owner can '
                  'change it.',
        ),
        team.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => SectionError(
            onRetry: () =>
                ref.invalidate(businessTeamProvider(widget.business.id)),
          ),
          data: (members) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ArcadeCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (index, member) in members.indexed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          border: index == 0
                              ? null
                              : Border(
                                  top: BorderSide(
                                      color: QuestColors.borderC(context))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(member.displayName,
                                      style: QuestTypography.osBodyMedium),
                                  Text('@${member.username}',
                                      style: QuestTypography.osBodySmall
                                          .copyWith(
                                              color: QuestColors.textDim(
                                                  context))),
                                ],
                              ),
                            ),
                            Text(
                              member.role == BusinessMemberRole.owner
                                  ? 'OWNER'
                                  : 'MANAGER',
                              style: QuestTypography.osLabelSmall.copyWith(
                                  color: QuestColors.textDim(context)),
                            ),
                            if (isOwner) ...[
                              const SizedBox(width: 12),
                              ArcadeButton(
                                label: 'REMOVE',
                                variant: ArcadeButtonVariant.ghost,
                                size: ArcadeButtonSize.small,
                                expand: false,
                                onTap: _busy ? null : () => _remove(member),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (isOwner) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 240,
                      child: ArcadeTextField(
                        controller: _username,
                        label: 'ADD BY USERNAME',
                        hint: 'their Bsheel handle',
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<BusinessMemberRole>(
                      value: _role,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                            value: BusinessMemberRole.manager,
                            child: Text('Manager')),
                        DropdownMenuItem(
                            value: BusinessMemberRole.owner,
                            child: Text('Owner')),
                      ],
                      onChanged: (value) =>
                          setState(() => _role = value ?? _role),
                    ),
                    const SizedBox(width: 12),
                    ArcadeButton(
                      label: _busy ? 'WORKING…' : 'ADD',
                      size: ArcadeButtonSize.small,
                      expand: false,
                      onTap: _busy ? null : () => _add(members),
                    ),
                  ],
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: QuestTypography.osBodySmall.copyWith(
                    color: _messageIsError
                        ? QuestColors.osRed
                        : QuestColors.textDim(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
