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

  /// The submission this quest's history row refers to, when one exists.
  ///
  /// Only the history query returns it. The appeal screen resolves a
  /// submission, so navigating with the user_quest id lands on "not found";
  /// this is the id the client must actually use.
  readonly submission_id?: string | null;
}

