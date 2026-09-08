export interface QuestRecord {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly category: string;
  readonly difficulty: string;
  readonly xp_reward: number;
  readonly duration_hours: number;
  readonly is_active: boolean;
  readonly created_by: string | null;
  readonly created_at: Date;
  readonly updated_at: Date;
}

export interface UserQuestRecord {
  readonly id: string;
  readonly user_id: string;
  readonly quest_id: string;
  readonly status: string;
  readonly assigned_at: Date;
  readonly completed_at: Date | null;
  readonly expires_at: Date;
  readonly quests?: QuestRecord;

  /// True when this quest's rejection can still be appealed.
  ///
  /// Only the history query computes it; elsewhere it is absent. `status`
  /// alone cannot express it, because a first rejection and a re-rejection
  /// after a spent appeal are both 'rejected'.
  readonly appeal_available?: boolean;
}

