const test = require("node:test");
const assert = require("node:assert/strict");

const {
  canJoinMeeting,
  canStopMeeting,
} = require("../lib/meeting_access.js");

test("direct meeting links permit signed-in guests", () => {
  assert.equal(canJoinMeeting({participantIds: ["organizer"]}, "guest"), true);
});

test("group meeting permits an existing participant", () => {
  assert.equal(
    canJoinMeeting({groupId: "team-a", participantIds: ["guest"]}, "guest"),
    true
  );
});

test("group meeting permits a current group member", () => {
  assert.equal(
    canJoinMeeting({groupId: "team-a", participantIds: ["organizer"]}, "member", ["member"]),
    true
  );
});

test("group meeting rejects an unrelated signed-in user", () => {
  assert.equal(
    canJoinMeeting({groupId: "team-a", participantIds: ["organizer"]}, "outsider", ["member"]),
    false
  );
});

test("only the organizer can stop a direct meeting recording", () => {
  const meeting = {participantIds: ["organizer"]};
  assert.equal(canStopMeeting(meeting, "organizer"), true);
  assert.equal(canStopMeeting(meeting, "guest"), false);
});

test("a group admin can stop a group meeting recording", () => {
  const meeting = {groupId: "team-a", participantIds: ["organizer"]};
  assert.equal(canStopMeeting(meeting, "admin", ["admin"]), true);
  assert.equal(canStopMeeting(meeting, "member", ["admin"]), false);
});
