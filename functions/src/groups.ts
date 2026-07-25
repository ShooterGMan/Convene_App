import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { notifyUser } from "./notifications";

/**
 * Looks up a user by email so the client can invite them to a group by real
 * identity. Needed because Firestore rules lock the `users` collection to
 * self-only reads - this callable uses the Admin SDK (bypasses rules) to do
 * the lookup safely on the server instead.
 */
export const findUserByEmail = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }

  const email = String(data?.email || "").trim();
  if (!email) {
    throw new functions.https.HttpsError("invalid-argument", "email required.");
  }

  const snapshot = await admin.firestore().collection("users").where("email", "==", email).limit(1).get();

  if (snapshot.empty) {
    return { found: false };
  }

  const doc = snapshot.docs[0];
  const userData = doc.data();
  return {
    found: true,
    user: {
      id: doc.id,
      name: userData.name || "",
      email: userData.email || "",
      avatarUrl: userData.avatarUrl || null,
    },
  };
});

async function getAppUser(uid: string) {
  const doc = await admin.firestore().collection("users").doc(uid).get();
  const data = doc.data() || {};
  return {
    id: uid,
    name: data.name || "Unknown",
    email: data.email || "",
    avatarUrl: data.avatarUrl || null,
  };
}

/**
 * Invites an existing user (by email) to a group. Rather than adding them
 * directly, this creates a pending invite they must accept - so people don't
 * silently end up in a group (and get its meeting summaries) without knowing.
 * Only existing group members can invite others.
 */
export const sendGroupInvite = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }
  const { groupId, email } = data;
  if (!groupId || !email) {
    throw new functions.https.HttpsError("invalid-argument", "groupId and email required.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const groupDoc = await groupRef.get();
  if (!groupDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Group not found.");
  }
  const groupData = groupDoc.data()!;
  if (!(groupData.memberIds || []).includes(context.auth.uid)) {
    throw new functions.https.HttpsError("permission-denied", "Only group members can invite others.");
  }

  const userSnapshot = await db.collection("users").where("email", "==", String(email).trim()).limit(1).get();
  if (userSnapshot.empty) {
    return { found: false };
  }
  const invitedUser = userSnapshot.docs[0];
  const invitedUserId = invitedUser.id;

  if ((groupData.memberIds || []).includes(invitedUserId)) {
    return { found: true, alreadyMember: true };
  }

  const inviterUser = await getAppUser(context.auth.uid);

  await groupRef.collection("pendingInvites").doc(invitedUserId).set({
    groupId,
    groupName: groupData.name || "Unnamed Group",
    groupAvatarEmoji: groupData.avatarEmoji || null,
    invitedBy: inviterUser,
    invitedUserId,
    invitedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await notifyUser(invitedUserId, {
    type: "group_invite",
    title: "New group invite",
    body: `${inviterUser.name} invited you to join "${groupData.name || "a group"}"`,
    route: "/groups",
    relatedId: groupId,
  });

  return { found: true, alreadyMember: false, invited: true };
});

/**
 * Invited user accepts or declines a pending group invite. Runs as the
 * invited user themself, via the Admin SDK, since adding oneself to a
 * group's memberIds isn't something the normal client-side rules allow
 * (you have to already be a member to update a group).
 */
export const respondToGroupInvite = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }
  const { groupId, accept } = data;
  if (!groupId || typeof accept !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "groupId and accept (boolean) required.");
  }

  const db = admin.firestore();
  const inviteRef = db.collection("groups").doc(groupId).collection("pendingInvites").doc(context.auth.uid);
  const inviteDoc = await inviteRef.get();
  if (!inviteDoc.exists) {
    throw new functions.https.HttpsError("not-found", "No pending invite found.");
  }

  const inviteData = inviteDoc.data()!;
  const inviterUserId = inviteData.invitedBy?.id as string | undefined;

  if (accept) {
    const appUser = await getAppUser(context.auth.uid);
    await db.collection("groups").doc(groupId).update({
      members: admin.firestore.FieldValue.arrayUnion(appUser),
      memberIds: admin.firestore.FieldValue.arrayUnion(context.auth.uid),
      [`memberJoinedAt.${context.auth.uid}`]: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (inviterUserId) {
      await notifyUser(inviterUserId, {
        type: "group_invite_accepted",
        title: "Invite accepted",
        body: `${appUser.name} joined "${inviteData.groupName || "your group"}"`,
        route: `/group/${groupId}`,
        relatedId: groupId,
      });
    }
  } else if (inviterUserId) {
    const appUser = await getAppUser(context.auth.uid);
    await notifyUser(inviterUserId, {
      type: "group_invite_declined",
      title: "Invite declined",
      body: `${appUser.name} declined your invite to "${inviteData.groupName || "your group"}"`,
      route: `/group/${groupId}`,
      relatedId: groupId,
    });
  }

  await inviteRef.delete();
  return { accepted: accept };
});

/**
 * Joins a group directly via its shareable invite link/code - clicking the
 * link and confirming is itself the consent, so no separate accept step.
 */
export const joinGroupByInviteLink = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }
  const inviteCode = String(data?.inviteCode || "").trim();
  if (!inviteCode) {
    throw new functions.https.HttpsError("invalid-argument", "inviteCode required.");
  }

  const db = admin.firestore();
  const snapshot = await db.collection("groups").where("inviteCode", "==", inviteCode).limit(1).get();
  if (snapshot.empty) {
    throw new functions.https.HttpsError("not-found", "Invalid or expired invite link.");
  }
  const groupDoc = snapshot.docs[0];
  const groupData = groupDoc.data();

  if ((groupData.memberIds || []).includes(context.auth.uid)) {
    return { groupId: groupDoc.id, groupName: groupData.name, alreadyMember: true };
  }

  const appUser = await getAppUser(context.auth.uid);
  await groupDoc.ref.update({
    members: admin.firestore.FieldValue.arrayUnion(appUser),
    memberIds: admin.firestore.FieldValue.arrayUnion(context.auth.uid),
    [`memberJoinedAt.${context.auth.uid}`]: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { groupId: groupDoc.id, groupName: groupData.name, alreadyMember: false };
});

/** Effective admins for a group - falls back to the original creator for
 * groups created before multi-admin support existed. */
function effectiveAdminIds(groupData: FirebaseFirestore.DocumentData): string[] {
  const admins = (groupData.adminIds || []) as string[];
  if (admins.length > 0) return admins;
  const creator = groupData.createdBy?.id as string | undefined;
  return creator ? [creator] : [];
}

/**
 * Removes a member from a group - either the caller leaving on their own, or
 * any group admin removing someone else. The last remaining admin can't leave
 * (they must delete the group or promote someone else first).
 */
export const removeGroupMember = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }
  const { groupId, userId } = data;
  if (!groupId || !userId) {
    throw new functions.https.HttpsError("invalid-argument", "groupId and userId required.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const groupDoc = await groupRef.get();
  if (!groupDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Group not found.");
  }
  const groupData = groupDoc.data()!;
  const admins = effectiveAdminIds(groupData);

  const isSelf = context.auth.uid === userId;
  const callerIsAdmin = admins.includes(context.auth.uid);
  if (!isSelf && !callerIsAdmin) {
    throw new functions.https.HttpsError("permission-denied", "Only a group admin can remove other members.");
  }
  // Prevent orphaning the group: the last admin can't be removed/leave.
  if (admins.includes(userId) && admins.length === 1) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "You're the only admin. Make someone else an admin first, or delete the group."
    );
  }

  const remainingMembers = (groupData.members || []).filter((m: any) => m.id !== userId);
  const remainingMemberIds = (groupData.memberIds || []).filter((id: string) => id !== userId);
  const remainingAdmins = admins.filter((id) => id !== userId);

  await groupRef.update({
    members: remainingMembers,
    memberIds: remainingMemberIds,
    adminIds: remainingAdmins,
    [`memberJoinedAt.${userId}`]: admin.firestore.FieldValue.delete(),
  });

  return { removed: true };
});

/**
 * Promotes or demotes a group member to/from admin. Only an existing admin
 * can do this. Supports multiple admins at once. You can't demote the last
 * admin (would leave the group unmanageable).
 */
export const setGroupAdmin = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }
  const { groupId, userId, makeAdmin } = data;
  if (!groupId || !userId || typeof makeAdmin !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "groupId, userId and makeAdmin required.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const groupDoc = await groupRef.get();
  if (!groupDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Group not found.");
  }
  const groupData = groupDoc.data()!;
  const admins = effectiveAdminIds(groupData);

  if (!admins.includes(context.auth.uid)) {
    throw new functions.https.HttpsError("permission-denied", "Only a group admin can change admins.");
  }
  if (!(groupData.memberIds || []).includes(userId)) {
    throw new functions.https.HttpsError("failed-precondition", "That person isn't a member of this group.");
  }
  if (!makeAdmin && admins.length === 1 && admins.includes(userId)) {
    throw new functions.https.HttpsError("failed-precondition", "A group must have at least one admin.");
  }

  const newAdmins = makeAdmin
    ? Array.from(new Set([...admins, userId]))
    : admins.filter((id) => id !== userId);

  await groupRef.update({ adminIds: newAdmins });

  const actor = await getAppUser(context.auth.uid);
  await notifyUser(userId, {
    type: makeAdmin ? "group_invite_accepted" : "group_invite_declined",
    title: makeAdmin ? "You're now a group admin" : "Admin access removed",
    body: makeAdmin
      ? `${actor.name} made you an admin of "${groupData.name || "a group"}"`
      : `${actor.name} removed your admin access to "${groupData.name || "a group"}"`,
    route: `/group/${groupId}`,
    relatedId: groupId,
  });

  return { adminIds: newAdmins };
});

/**
 * Permanently deletes a group and its pending invites. Only an admin can do
 * this. Threads/meetings that referenced the group are left intact (they stay
 * visible to their own participants) - only the group container is removed.
 */
export const deleteGroup = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }
  const { groupId } = data;
  if (!groupId) {
    throw new functions.https.HttpsError("invalid-argument", "groupId required.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const groupDoc = await groupRef.get();
  if (!groupDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Group not found.");
  }
  const groupData = groupDoc.data()!;
  const admins = effectiveAdminIds(groupData);
  if (!admins.includes(context.auth.uid)) {
    throw new functions.https.HttpsError("permission-denied", "Only a group admin can delete the group.");
  }

  // Let the other members know before the group disappears.
  const actor = await getAppUser(context.auth.uid);
  const otherMemberIds = ((groupData.memberIds || []) as string[]).filter((id) => id !== context.auth!.uid);
  await Promise.all(
    otherMemberIds.map((id) =>
      notifyUser(id, {
        type: "group_invite_declined",
        title: "Group deleted",
        body: `${actor.name} deleted the group "${groupData.name || "a group"}"`,
        relatedId: groupId,
      })
    )
  );

  // Delete pending invites subcollection, then the group doc.
  const invites = await groupRef.collection("pendingInvites").get();
  const batch = db.batch();
  invites.docs.forEach((d) => batch.delete(d.ref));
  batch.delete(groupRef);
  await batch.commit();

  return { deleted: true };
});
