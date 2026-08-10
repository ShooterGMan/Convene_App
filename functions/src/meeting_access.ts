/** Minimal meeting shape used by the server-side authorization policy. */
export interface MeetingAccessData {
  groupId?: string | null;
  participantIds?: string[];
  organizerId?: string | null;
}

/**
 * Direct meetings are signed-in bearer-link invites. Group meetings are
 * private: the user must already be a participant or a current group member.
 */
export function canJoinMeeting(
  meeting: MeetingAccessData,
  userId: string,
  groupMemberIds: string[] = []
): boolean {
  if (!meeting.groupId) return true;
  return (meeting.participantIds || []).includes(userId) || groupMemberIds.includes(userId);
}

/** Only an organizer or group admin may stop a recording for everyone. */
export function canStopMeeting(
  meeting: MeetingAccessData,
  userId: string,
  groupAdminIds: string[] = []
): boolean {
  const organizerId = meeting.organizerId || meeting.participantIds?.[0];
  return organizerId === userId || (!!meeting.groupId && groupAdminIds.includes(userId));
}
