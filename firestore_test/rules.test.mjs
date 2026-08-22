// Behaviour tests for ../firestore.rules, run against the Firestore emulator.
//
//   cd firestore_test && npm install
//   npm test
//
// Nothing here touches the real project: the emulator runs locally on a fake
// project id. Worth running before every rules deploy — the first pass of these
// caught a rule that denied every edit, delete and reaction, which reads as
// "the chat is broken" and would have shipped otherwise.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  updateDoc,
  deleteDoc,
  getDoc,
  serverTimestamp,
  deleteField,
  Timestamp,
} from 'firebase/firestore';

const RULES = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  'firestore.rules',
);

const MEMBER = '01712345678';
const OTHER = '01787654321';
const ADMIN = '01799999999';

const env = await initializeTestEnvironment({
  projectId: 'demo-rules-check',
  firestore: {
    rules: fs.readFileSync(RULES, 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
});

// Every install signs in anonymously, so all three contexts are just "the app".
const app = env.authenticatedContext('anon-install-1').firestore();
const app2 = env.authenticatedContext('anon-install-2').firestore();
const guest = env.unauthenticatedContext().firestore();

// Both phones, sorted and joined — see `ChatThread.conversationIdFor`.
const DM = [MEMBER, OTHER].sort().join('__');

const FRESH = 'msg_fresh';
const OLD = 'msg_old';
const OLD_OTHER = 'msg_old_other';
const OLD_IMAGE = 'msg_old_image';

async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${MEMBER}`), { name: 'Member', phone: MEMBER, isAdmin: '0' });
    await setDoc(doc(db, `users/${OTHER}`), { name: 'Other', phone: OTHER, isAdmin: '0' });
    await setDoc(doc(db, `users/${ADMIN}`), { name: 'Admin', phone: ADMIN, isAdmin: '1' });

    const base = { sender_name: 'Member', sender_phone: MEMBER, text: 'hello' };
    await setDoc(doc(db, `chats/${FRESH}`), { ...base, createdAt: Timestamp.now() });
    await setDoc(doc(db, `chats/${OLD}`), {
      ...base,
      createdAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
    });
    await setDoc(doc(db, `chats/${OLD_OTHER}`), {
      sender_name: 'Other',
      sender_phone: OTHER,
      text: 'not yours',
      createdAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
    });
    await setDoc(doc(db, `chats/${OLD_IMAGE}`), {
      ...base,
      text: '',
      image_url: 'https://x/storage/v1/object/public/uploads/chat/1.jpg',
      image_width: 800,
      image_height: 600,
      reactions: { [OTHER]: '👍' },
      createdAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
    });

    // A direct thread between MEMBER and OTHER: the summary the chat list
    // reads, and the same two messages underneath it.
    await setDoc(doc(db, `direct_chats/${DM}`), {
      participants: [MEMBER, OTHER],
      last_text: 'hello',
      last_sender_phone: MEMBER,
      last_has_image: false,
      unread: { [OTHER]: 1 },
    });
    await setDoc(doc(db, `direct_chats/${DM}/messages/${FRESH}`), {
      ...base,
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(db, `direct_chats/${DM}/messages/${OLD}`), {
      ...base,
      createdAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
    });
    await setDoc(doc(db, `direct_chats/${DM}/messages/${OLD_OTHER}`), {
      sender_name: 'Other',
      sender_phone: OTHER,
      text: 'not yours',
      createdAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
    });
  });
}

const edit = (actor, text) => ({
  text,
  edited_at: serverTimestamp(),
  edited_by: actor,
});

const softDelete = (actor, byAdmin) => ({
  deleted: true,
  deleted_by_admin: byAdmin,
  deleted_by: actor,
  text: '',
  image_url: deleteField(),
  image_width: deleteField(),
  image_height: deleteField(),
  reactions: deleteField(),
});

const cases = [
  // --- reading and posting -------------------------------------------------
  ['app can read the thread', 'pass', () => getDoc(doc(app, `chats/${FRESH}`))],
  ['a signed-out client cannot read', 'fail', () => getDoc(doc(guest, `chats/${FRESH}`))],
  ['app can post a message', 'pass', () =>
    setDoc(doc(app, 'chats/new1'), {
      text: 'hi', sender_name: 'Member', sender_phone: MEMBER, createdAt: serverTimestamp(),
    })],
  ['a signed-out client cannot post', 'fail', () =>
    setDoc(doc(guest, 'chats/new2'), {
      text: 'hi', sender_name: 'Member', sender_phone: MEMBER, createdAt: serverTimestamp(),
    })],
  ['a self-chosen createdAt is rejected (no endless window)', 'fail', () =>
    setDoc(doc(app, 'chats/new3'), {
      text: 'hi', sender_name: 'Member', sender_phone: MEMBER,
      createdAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
    })],
  ['posting something pre-marked deleted is rejected', 'fail', () =>
    setDoc(doc(app, 'chats/new4'), {
      text: 'hi', sender_name: 'Member', sender_phone: MEMBER,
      createdAt: serverTimestamp(), deleted: true,
    })],

  // --- editing -------------------------------------------------------------
  ['author edits own message inside 5 min', 'pass', () =>
    updateDoc(doc(app, `chats/${FRESH}`), edit(MEMBER, 'fixed'))],
  ['author edits own message after 5 min', 'fail', () =>
    updateDoc(doc(app, `chats/${OLD}`), edit(MEMBER, 'too late'))],
  ['admin edits an old message', 'pass', () =>
    updateDoc(doc(app2, `chats/${OLD}`), edit(ADMIN, 'admin fixed'))],
  ['admin edits someone else\'s message', 'pass', () =>
    updateDoc(doc(app2, `chats/${OLD_OTHER}`), edit(ADMIN, 'admin fixed'))],
  ['a member edits someone else\'s message', 'fail', () =>
    updateDoc(doc(app, `chats/${OLD_OTHER}`), edit(MEMBER, 'not mine to touch'))],
  ['an edit cannot rewrite authorship', 'fail', () =>
    updateDoc(doc(app, `chats/${FRESH}`), { ...edit(MEMBER, 'x'), sender_phone: OTHER })],
  ['an edit cannot move createdAt', 'fail', () =>
    updateDoc(doc(app, `chats/${FRESH}`), { ...edit(MEMBER, 'x'), createdAt: serverTimestamp() })],
  ['an edit cannot back-date edited_at', 'fail', () =>
    updateDoc(doc(app, `chats/${FRESH}`), {
      text: 'x', edited_by: MEMBER, edited_at: Timestamp.fromMillis(Date.now() - 1000),
    })],

  // --- deleting ------------------------------------------------------------
  ['author deletes own message inside 5 min', 'pass', () =>
    updateDoc(doc(app, `chats/${FRESH}`), softDelete(MEMBER, false))],
  ['author deletes own message after 5 min', 'fail', () =>
    updateDoc(doc(app, `chats/${OLD}`), softDelete(MEMBER, false))],
  ['admin deletes an old message with a picture', 'pass', () =>
    updateDoc(doc(app2, `chats/${OLD_IMAGE}`), softDelete(ADMIN, true))],
  ['a member deletes someone else\'s message', 'fail', () =>
    updateDoc(doc(app, `chats/${OLD_OTHER}`), softDelete(MEMBER, true))],
  ['a "delete" that keeps the text is rejected', 'fail', () =>
    updateDoc(doc(app, `chats/${FRESH}`), {
      deleted: true, deleted_by_admin: false, deleted_by: MEMBER, text: 'still here',
    })],
  ['nobody can hard-delete a message', 'fail', () => deleteDoc(doc(app, `chats/${FRESH}`))],
  ['an admin cannot hard-delete either', 'fail', () => deleteDoc(doc(app2, `chats/${OLD}`))],

  // --- reactions -----------------------------------------------------------
  ['anyone reacts to any message, any age', 'pass', () =>
    updateDoc(doc(app, `chats/${OLD_OTHER}`), { reactions: { [MEMBER]: '❤️' } })],
  ['a reaction write cannot smuggle in a text change', 'fail', () =>
    updateDoc(doc(app, `chats/${OLD_OTHER}`), { reactions: {}, text: 'sneaky' })],

  // --- direct chats --------------------------------------------------------
  //
  // The same rules as the group, one collection deeper. Worth testing
  // separately: they are a second copy of the same functions, and a typo in
  // either would only show up in one half of the chat section.
  ['app can read a direct thread', 'pass', () => getDoc(doc(app, `direct_chats/${DM}`))],
  ['a signed-out client cannot read a direct thread', 'fail', () =>
    getDoc(doc(guest, `direct_chats/${DM}`))],
  ['app can read direct messages', 'pass', () =>
    getDoc(doc(app, `direct_chats/${DM}/messages/${FRESH}`))],
  ['a signed-out client cannot read direct messages', 'fail', () =>
    getDoc(doc(guest, `direct_chats/${DM}/messages/${FRESH}`))],
  ['app can send a direct message', 'pass', () =>
    setDoc(doc(app, `direct_chats/${DM}/messages/dm1`), {
      text: 'hi', sender_name: 'Member', sender_phone: MEMBER, createdAt: serverTimestamp(),
    })],
  ['app can bump the thread summary', 'pass', () =>
    setDoc(doc(app, `direct_chats/${DM}`), {
      last_text: 'hi', last_sender_phone: MEMBER, last_at: serverTimestamp(),
    }, { merge: true })],
  ['a signed-out client cannot send a direct message', 'fail', () =>
    setDoc(doc(guest, `direct_chats/${DM}/messages/dm2`), {
      text: 'hi', sender_name: 'Member', sender_phone: MEMBER, createdAt: serverTimestamp(),
    })],
  ['a self-chosen createdAt is rejected in a direct chat too', 'fail', () =>
    setDoc(doc(app, `direct_chats/${DM}/messages/dm3`), {
      text: 'hi', sender_name: 'Member', sender_phone: MEMBER,
      createdAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
    })],
  ['author edits own direct message inside 5 min', 'pass', () =>
    updateDoc(doc(app, `direct_chats/${DM}/messages/${FRESH}`), edit(MEMBER, 'fixed'))],
  ['author edits own direct message after 5 min', 'fail', () =>
    updateDoc(doc(app, `direct_chats/${DM}/messages/${OLD}`), edit(MEMBER, 'too late'))],
  ['admin edits an old direct message', 'pass', () =>
    updateDoc(doc(app2, `direct_chats/${DM}/messages/${OLD}`), edit(ADMIN, 'admin fixed'))],
  ['a member edits someone else\'s direct message', 'fail', () =>
    updateDoc(doc(app, `direct_chats/${DM}/messages/${OLD_OTHER}`), edit(MEMBER, 'nope'))],
  ['author deletes own direct message inside 5 min', 'pass', () =>
    updateDoc(doc(app, `direct_chats/${DM}/messages/${FRESH}`), softDelete(MEMBER, false))],
  ['author deletes own direct message after 5 min', 'fail', () =>
    updateDoc(doc(app, `direct_chats/${DM}/messages/${OLD}`), softDelete(MEMBER, false))],
  ['nobody can hard-delete a direct message', 'fail', () =>
    deleteDoc(doc(app, `direct_chats/${DM}/messages/${FRESH}`))],
  ['anyone reacts to a direct message, any age', 'pass', () =>
    updateDoc(doc(app, `direct_chats/${DM}/messages/${OLD_OTHER}`), { reactions: { [MEMBER]: '❤️' } })],
  ['app can write a direct read receipt', 'pass', () =>
    setDoc(doc(app, `direct_chats/${DM}/seen/${OTHER}`), { lastSeenMessageId: FRESH })],
  ['a signed-out client cannot read direct receipts', 'fail', () =>
    getDoc(doc(guest, `direct_chats/${DM}/seen/${OTHER}`))],

  // --- pinned messages -----------------------------------------------------
  //
  // Open to everyone on purpose: pinning is how the house keeps something
  // above the conversation, and it writes nothing into the thread itself.
  ['app can pin a message', 'pass', () =>
    setDoc(doc(app, `pinned_messages/${FRESH}`), {
      message_id: FRESH, text: 'rent is due on the 5th',
      sender_name: 'Member', sender_phone: MEMBER, order: 0,
      pinned_by: MEMBER, pinned_by_name: 'Member', pinned_at: serverTimestamp(),
    })],
  ['a member can pin somebody else\'s message', 'pass', () =>
    setDoc(doc(app, `pinned_messages/${OLD_OTHER}`), {
      message_id: OLD_OTHER, text: 'not yours', sender_phone: OTHER, order: 1,
      pinned_by: MEMBER, pinned_by_name: 'Member', pinned_at: serverTimestamp(),
    })],
  ['app can read the pinned list', 'pass', () =>
    getDoc(doc(app, `pinned_messages/${FRESH}`))],
  ['app can rearrange a pin', 'pass', () =>
    setDoc(doc(app, `pinned_messages/${FRESH}`), { order: 3 }, { merge: true })],
  ['app can unpin', 'pass', () => deleteDoc(doc(app, `pinned_messages/${FRESH}`))],
  ['a signed-out client cannot read pins', 'fail', () =>
    getDoc(doc(guest, `pinned_messages/${FRESH}`))],
  ['a signed-out client cannot pin', 'fail', () =>
    setDoc(doc(guest, `pinned_messages/${OLD}`), { message_id: OLD, order: 0 })],

  // --- the rest of the app still works -------------------------------------
  ['app can write meals', 'pass', () =>
    setDoc(doc(app, 'meals/x'), { user_phone: MEMBER, meal_count: 2 })],
  ['app can write expenses', 'pass', () => setDoc(doc(app, 'expenses/x'), { amount: 10 })],
  ['app can write seen status', 'pass', () =>
    setDoc(doc(app, `seen_status/${MEMBER}`), { lastSeenMessageId: FRESH })],
  ['app can write edit logs', 'pass', () => setDoc(doc(app, 'edit_logs/x'), { note: 'x' })],
  ['app can write monthly bills', 'pass', () => setDoc(doc(app, 'monthly_bills/2026-08'), { total: 1 })],
  ['app can write announcements', 'pass', () => setDoc(doc(app, 'announcements/x'), { text: 'x' })],
  ['app can write house rules', 'pass', () =>
    setDoc(doc(app, 'house_rules/seed_rent'), {
      text_en: 'Pay the rent by the 10th.', text_bn: '১০ তারিখের মধ্যে ভাড়া দিন।', order: 0,
    })],
  ['app can delete house rules', 'pass', () => deleteDoc(doc(app, 'house_rules/seed_rent'))],
  ['a signed-out client cannot read house rules', 'fail', () =>
    getDoc(doc(guest, 'house_rules/seed_rent'))],
  ['app can record a rule acknowledgement', 'pass', () =>
    setDoc(doc(app, `house_rule_acks/${MEMBER}`), {
      acks: { seed_rent: 1755590400000 }, user_name: 'Member',
    })],
  ['a signed-out client cannot read acknowledgements', 'fail', () =>
    getDoc(doc(guest, `house_rule_acks/${MEMBER}`))],
  ['app can write a personal transaction', 'pass', () =>
    setDoc(doc(app, 'personal_transactions/t1'), {
      owner_phone: MEMBER, type: 'expense', amount: 250, category: 'food', date: '2026-08-19',
    })],
  ['app can write a personal due', 'pass', () =>
    setDoc(doc(app, 'personal_debts/d1'), {
      owner_phone: MEMBER, person_name: 'Rakib', direction: 'gave', amount: 500, date: '2026-08-19',
    })],
  ['a signed-out client cannot read a personal ledger', 'fail', () =>
    getDoc(doc(guest, 'personal_transactions/t1'))],
  ['app can delete announcements', 'pass', () => deleteDoc(doc(app, 'announcements/x'))],
  ['app can read config', 'pass', () => getDoc(doc(app, 'config/business_config'))],
  ['app can sign a member up', 'pass', () =>
    setDoc(doc(app, 'users/01700000000'), { name: 'New', phone: '01700000000', isAdmin: '0' })],
  ['a signed-out client cannot read members', 'fail', () => getDoc(doc(guest, `users/${MEMBER}`))],
];

let passed = 0;
let failed = 0;

for (const [name, expectation, run] of cases) {
  await seed();
  try {
    await (expectation === 'pass' ? assertSucceeds(run()) : assertFails(run()));
    console.log(`  ok    ${expectation === 'pass' ? 'ALLOW' : 'DENY '}  ${name}`);
    passed++;
  } catch (e) {
    console.log(`  FAIL  ${expectation === 'pass' ? 'ALLOW' : 'DENY '}  ${name}`);
    console.log(`        ${String(e).split('\n')[0]}`);
    failed++;
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
await env.cleanup();
process.exit(failed === 0 ? 0 : 1);
