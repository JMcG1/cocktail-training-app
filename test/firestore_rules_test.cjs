const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  Timestamp,
  doc,
  getDoc,
  setDoc,
  getDocs,
  collection,
  writeBatch,
} = require('firebase/firestore');

const projectId = 'cocktail-training-rules-tests';
const venueId = 'venue-1';
const otherVenueId = 'venue-2';
const bootstrapEmail = 'newowner@example.com';

function userDoc({
  email,
  displayName,
  role,
  venueId,
  active = true,
  inviteId = null,
}) {
  return {
    email,
    displayName,
    role,
    venueId,
    active,
    inviteId,
    createdAt: '2026-06-17T00:00:00.000Z',
  };
}

async function seedData(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const now = Timestamp.fromDate(new Date('2026-06-17T12:00:00.000Z'));
    const future = Timestamp.fromDate(new Date('2026-12-31T12:00:00.000Z'));

    await Promise.all([
      setDoc(doc(db, 'users', 'owner-1'), userDoc({
        email: 'owner@example.com',
        displayName: 'Owner',
        role: 'owner',
        venueId,
      })),
      setDoc(doc(db, 'users', 'manager-1'), userDoc({
        email: 'manager@example.com',
        displayName: 'Manager',
        role: 'manager',
        venueId,
      })),
      setDoc(doc(db, 'users', 'bartender-1'), userDoc({
        email: 'bartender@example.com',
        displayName: 'Bartender',
        role: 'bartender',
        venueId,
        inviteId: 'invite-1',
      })),
      setDoc(doc(db, 'users', 'manager-2'), userDoc({
        email: 'manager2@example.com',
        displayName: 'Other Manager',
        role: 'manager',
        venueId: otherVenueId,
      })),
      setDoc(doc(db, 'users', 'bartender-2'), userDoc({
        email: 'bartender2@example.com',
        displayName: 'Other Bartender',
        role: 'bartender',
        venueId: otherVenueId,
        inviteId: 'invite-9',
      })),
      setDoc(doc(db, 'venues', venueId), {
        name: 'Venue One',
        ownerUid: 'owner-1',
        createdAt: now,
        active: true,
      }),
      setDoc(doc(db, 'venues', otherVenueId), {
        name: 'Venue Two',
        ownerUid: 'owner-2',
        createdAt: now,
        active: true,
      }),
      setDoc(doc(db, 'venues', venueId, 'invites', 'invite-1'), {
        venueId,
        role: 'bartender',
        createdBy: 'manager-1',
        createdAt: now,
        expiresAt: future,
        maxUses: 1,
        currentUses: 0,
        disabled: false,
      }),
      setDoc(doc(db, 'venues', venueId, 'quizSessions', 'quiz-1'), {
        title: 'Live quiz',
        bartenderName: 'Bartender',
        kind: 'stockVariance',
        isActive: true,
        createdAt: now,
        questions: [],
        weekId: 'week-1',
      }),
      setDoc(doc(db, 'venues', venueId, 'quizSessions', 'quiz-inactive'), {
        title: 'Closed quiz',
        bartenderName: 'Bartender',
        kind: 'stockVariance',
        isActive: false,
        createdAt: now,
        questions: [],
        weekId: 'week-1',
      }),
      setDoc(doc(db, 'venues', otherVenueId, 'quizSessions', 'quiz-2'), {
        title: 'Other venue quiz',
        bartenderName: 'Other Bartender',
        kind: 'stockVariance',
        isActive: true,
        createdAt: now,
        questions: [],
        weekId: 'week-9',
      }),
      setDoc(doc(db, 'venues', venueId, 'quizAttempts', 'attempt-owned'), {
        sessionId: 'quiz-1',
        bartenderName: 'Bartender',
        userId: 'bartender-1',
        scorePercent: 90,
        submittedAt: now,
        responses: [],
        overpourLines: [],
        underpourLines: [],
        batchOverpourLines: [],
        batchUnderpourLines: [],
        coachingAreas: [],
        encouragement: 'Nice work.',
        weekId: 'week-1',
      }),
      setDoc(doc(db, 'venues', venueId, 'quizAttempts', 'attempt-other-user'), {
        sessionId: 'quiz-1',
        bartenderName: 'Teammate',
        userId: 'manager-1',
        scorePercent: 75,
        submittedAt: now,
        responses: [],
        overpourLines: [],
        underpourLines: [],
        batchOverpourLines: [],
        batchUnderpourLines: [],
        coachingAreas: [],
        encouragement: 'Keep going.',
        weekId: 'week-1',
      }),
      setDoc(doc(db, 'venues', otherVenueId, 'quizAttempts', 'attempt-other-venue'), {
        sessionId: 'quiz-2',
        bartenderName: 'Other Bartender',
        userId: 'bartender-2',
        scorePercent: 88,
        submittedAt: now,
        responses: [],
        overpourLines: [],
        underpourLines: [],
        batchOverpourLines: [],
        batchUnderpourLines: [],
        coachingAreas: [],
        encouragement: 'Solid work.',
        weekId: 'week-9',
      }),
      setDoc(doc(db, 'bootstrapGrants', bootstrapEmail), {
        email: bootstrapEmail,
        role: 'owner',
        disabled: false,
        expiresAt: future,
      }),
    ]);
  });
}

async function runTest(name, fn) {
  try {
    await fn();
    console.log(`PASS ${name}`);
  } catch (error) {
    console.error(`FAIL ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync('firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });

  try {
    await seedData(testEnv);

    await runTest('owner can write ingredient costs', async () => {
      const db = testEnv.authenticatedContext('owner-1').firestore();
      await assertSucceeds(
        setDoc(doc(db, 'venues', venueId, 'ingredients', 'vodka'), {
          name: 'Vodka',
          bottleSizeMl: 700,
          bottleCost: 28,
          costPerMl: 0.04,
          isGarnish: false,
        }),
      );
    });

    await runTest('manager cannot write ingredient costs', async () => {
      const db = testEnv.authenticatedContext('manager-1').firestore();
      await assertFails(
        setDoc(doc(db, 'venues', venueId, 'ingredients', 'vodka'), {
          name: 'Vodka',
          bottleSizeMl: 700,
          bottleCost: 28,
          costPerMl: 0.04,
          isGarnish: false,
        }),
      );
    });

    await runTest('manager can read bartender profile in same venue', async () => {
      const db = testEnv.authenticatedContext('manager-1').firestore();
      await assertSucceeds(getDoc(doc(db, 'users', 'bartender-1')));
    });

    await runTest('manager cannot read owner profile in same venue', async () => {
      const db = testEnv.authenticatedContext('manager-1').firestore();
      await assertFails(getDoc(doc(db, 'users', 'owner-1')));
    });

    await runTest('manager can create venue-scoped bartender invites', async () => {
      const db = testEnv.authenticatedContext('manager-1').firestore();
      const now = Timestamp.fromDate(new Date('2026-06-17T12:00:00.000Z'));
      const future = Timestamp.fromDate(new Date('2026-12-31T12:00:00.000Z'));
      await assertSucceeds(
        setDoc(doc(db, 'venues', venueId, 'invites', 'invite-2'), {
          venueId,
          role: 'bartender',
          createdBy: 'manager-1',
          createdAt: now,
          expiresAt: future,
          maxUses: 2,
          currentUses: 0,
          disabled: false,
        }),
      );
    });

    await runTest('bartender cannot create venue invites', async () => {
      const db = testEnv.authenticatedContext('bartender-1').firestore();
      const now = Timestamp.fromDate(new Date('2026-06-17T12:00:00.000Z'));
      const future = Timestamp.fromDate(new Date('2026-12-31T12:00:00.000Z'));
      await assertFails(
        setDoc(doc(db, 'venues', venueId, 'invites', 'invite-3'), {
          venueId,
          role: 'bartender',
          createdBy: 'bartender-1',
          createdAt: now,
          expiresAt: future,
          maxUses: 1,
          currentUses: 0,
          disabled: false,
        }),
      );
    });

    await runTest('public can get a redeemable invite but cannot list invites', async () => {
      const db = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(getDoc(doc(db, 'venues', venueId, 'invites', 'invite-1')));
      await assertFails(getDocs(collection(db, 'venues', venueId, 'invites')));
    });

    await runTest('public cannot get an inactive quiz session', async () => {
      const db = testEnv.unauthenticatedContext().firestore();
      await assertFails(getDoc(doc(db, 'venues', venueId, 'quizSessions', 'quiz-inactive')));
    });

    await runTest('manager can write stock concern sessions in own venue', async () => {
      const db = testEnv.authenticatedContext('manager-1').firestore();
      await assertSucceeds(
        setDoc(doc(db, 'venues', venueId, 'stockConcernSessions', 'week-1'), {
          label: 'Monday focus',
          weekStart: '2026-06-17T00:00:00.000Z',
          concerns: [{ ingredientName: 'Vodka' }],
          targetCocktailIds: ['aperol-spritz'],
          quizSessionIds: [],
        }),
      );
    });

    await runTest('manager cannot write stock concern sessions in another venue', async () => {
      const db = testEnv.authenticatedContext('manager-1').firestore();
      await assertFails(
        setDoc(doc(db, 'venues', otherVenueId, 'stockConcernSessions', 'week-3'), {
          label: 'Other venue focus',
          weekStart: '2026-06-19T00:00:00.000Z',
          concerns: [{ ingredientName: 'Gin' }],
          targetCocktailIds: ['garden-gimlet'],
          quizSessionIds: [],
        }),
      );
    });

    await runTest('bartender cannot write stock concern sessions', async () => {
      const db = testEnv.authenticatedContext('bartender-1').firestore();
      await assertFails(
        setDoc(doc(db, 'venues', venueId, 'stockConcernSessions', 'week-2'), {
          label: 'Tuesday focus',
          weekStart: '2026-06-18T00:00:00.000Z',
          concerns: [{ ingredientName: 'Vodka' }],
          targetCocktailIds: ['aperol-spritz'],
          quizSessionIds: [],
        }),
      );
    });

    await runTest('bartender can read only their own saved quiz attempt', async () => {
      const db = testEnv.authenticatedContext('bartender-1').firestore();
      await assertSucceeds(getDoc(doc(db, 'venues', venueId, 'quizAttempts', 'attempt-owned')));
      await assertFails(getDoc(doc(db, 'venues', venueId, 'quizAttempts', 'attempt-other-user')));
    });

    await runTest('manager cannot read quiz attempts from another venue', async () => {
      const db = testEnv.authenticatedContext('manager-1').firestore();
      await assertFails(getDoc(doc(db, 'venues', otherVenueId, 'quizAttempts', 'attempt-other-venue')));
    });

    await runTest('bartender can save own quiz attempt for an active session', async () => {
      const db = testEnv.authenticatedContext('bartender-1').firestore();
      await assertSucceeds(
        setDoc(doc(db, 'venues', venueId, 'quizAttempts', 'attempt-1'), {
          sessionId: 'quiz-1',
          bartenderName: 'Bartender',
          userId: 'bartender-1',
          scorePercent: 80,
          submittedAt: Timestamp.fromDate(new Date('2026-06-17T13:00:00.000Z')),
          responses: [],
          overpourLines: [],
          underpourLines: [],
          batchOverpourLines: [],
          batchUnderpourLines: [],
          coachingAreas: [],
          encouragement: 'Nice work.',
          weekId: 'week-1',
        }),
      );
    });

    await runTest('bartender cannot save a quiz attempt for another user id', async () => {
      const db = testEnv.authenticatedContext('bartender-1').firestore();
      await assertFails(
        setDoc(doc(db, 'venues', venueId, 'quizAttempts', 'attempt-2'), {
          sessionId: 'quiz-1',
          bartenderName: 'Bartender',
          userId: 'manager-1',
          scorePercent: 80,
          submittedAt: Timestamp.fromDate(new Date('2026-06-17T13:00:00.000Z')),
          responses: [],
          overpourLines: [],
          underpourLines: [],
          batchOverpourLines: [],
          batchUnderpourLines: [],
          coachingAreas: [],
          encouragement: 'Nice work.',
          weekId: 'week-1',
        }),
      );
    });

    await runTest('bootstrap owner creation succeeds only when grant, user, and venue are written together', async () => {
      const db = testEnv.authenticatedContext('owner-bootstrap').firestore();
      const future = Timestamp.fromDate(new Date('2026-12-31T12:00:00.000Z'));
      const now = Timestamp.fromDate(new Date('2026-06-17T12:00:00.000Z'));
      const batch = writeBatch(db);
      batch.update(doc(db, 'bootstrapGrants', bootstrapEmail), {
        email: bootstrapEmail,
        role: 'owner',
        disabled: true,
        expiresAt: future,
        usedAt: now,
        usedByUid: 'owner-bootstrap',
        venueId: 'venue-bootstrap',
      });
      batch.set(doc(db, 'users', 'owner-bootstrap'), {
        email: bootstrapEmail,
        displayName: 'Bootstrap Owner',
        role: 'owner',
        venueId: 'venue-bootstrap',
        active: true,
        createdAt: '2026-06-17T12:00:00.000Z',
      });
      batch.set(doc(db, 'venues', 'venue-bootstrap'), {
        name: 'Bootstrap Venue',
        ownerUid: 'owner-bootstrap',
        createdAt: now,
        active: true,
      });
      await assertSucceeds(batch.commit());
    });

    await runTest('bootstrap owner creation fails without consuming the grant in the same batch', async () => {
      const db = testEnv.authenticatedContext('owner-bootstrap-fail').firestore();
      const now = Timestamp.fromDate(new Date('2026-06-17T12:00:00.000Z'));
      const batch = writeBatch(db);
      batch.set(doc(db, 'users', 'owner-bootstrap-fail'), {
        email: 'brokenowner@example.com',
        displayName: 'Broken Owner',
        role: 'owner',
        venueId: 'venue-bootstrap-fail',
        active: true,
        createdAt: '2026-06-17T12:00:00.000Z',
      });
      batch.set(doc(db, 'venues', 'venue-bootstrap-fail'), {
        name: 'Broken Venue',
        ownerUid: 'owner-bootstrap-fail',
        createdAt: now,
        active: true,
      });
      await assertFails(batch.commit());
    });

    await runTest('invite redemption succeeds only when invite usage and user creation happen together', async () => {
      const db = testEnv.authenticatedContext('bartender-join').firestore();
      const future = Timestamp.fromDate(new Date('2026-12-31T12:00:00.000Z'));
      const now = Timestamp.fromDate(new Date('2026-06-17T12:00:00.000Z'));
      const batch = writeBatch(db);
      batch.update(doc(db, 'venues', venueId, 'invites', 'invite-1'), {
        venueId,
        role: 'bartender',
        createdBy: 'manager-1',
        createdAt: now,
        expiresAt: future,
        maxUses: 1,
        currentUses: 1,
        disabled: false,
      });
      batch.set(doc(db, 'users', 'bartender-join'), {
        email: 'newbartender@example.com',
        displayName: 'New Bartender',
        role: 'bartender',
        venueId,
        active: true,
        inviteId: 'invite-1',
        createdAt: '2026-06-17T12:00:00.000Z',
      });
      await assertSucceeds(batch.commit());
    });

    await runTest('manager invite redemption succeeds when the created user role matches the invite role', async () => {
      const managerDb = testEnv.authenticatedContext('manager-1').firestore();
      const future = Timestamp.fromDate(new Date('2026-12-31T12:00:00.000Z'));
      const now = Timestamp.fromDate(new Date('2026-06-17T12:00:00.000Z'));
      const seedBatch = writeBatch(managerDb);
      seedBatch.set(doc(managerDb, 'venues', venueId, 'invites', 'invite-manager-join'), {
        venueId,
        role: 'manager',
        createdBy: 'manager-1',
        createdAt: now,
        expiresAt: future,
        maxUses: 2,
        currentUses: 0,
        disabled: false,
      });
      await assertSucceeds(seedBatch.commit());

      const db = testEnv.authenticatedContext('manager-join').firestore();
      const redeemBatch = writeBatch(db);
      redeemBatch.update(doc(db, 'venues', venueId, 'invites', 'invite-manager-join'), {
        venueId,
        role: 'manager',
        createdBy: 'manager-1',
        createdAt: now,
        expiresAt: future,
        maxUses: 2,
        currentUses: 1,
        disabled: false,
      });
      redeemBatch.set(doc(db, 'users', 'manager-join'), {
        email: 'newmanager@example.com',
        displayName: 'New Manager',
        role: 'manager',
        venueId,
        active: true,
        inviteId: 'invite-manager-join',
        createdAt: '2026-06-17T12:00:00.000Z',
      });
      await assertSucceeds(redeemBatch.commit());
    });

    await runTest('invite redemption fails when the created user role does not match the invite role', async () => {
      const managerDb = testEnv.authenticatedContext('manager-1').firestore();
      const future = Timestamp.fromDate(new Date('2026-12-31T12:00:00.000Z'));
      const now = Timestamp.fromDate(new Date('2026-06-17T12:00:00.000Z'));
      const batch = writeBatch(managerDb);
      batch.set(doc(managerDb, 'venues', venueId, 'invites', 'invite-role-check'), {
        venueId,
        role: 'bartender',
        createdBy: 'manager-1',
        createdAt: now,
        expiresAt: future,
        maxUses: 2,
        currentUses: 0,
        disabled: false,
      });
      await assertSucceeds(batch.commit());

      const db = testEnv.authenticatedContext('manager-join-fail').firestore();
      const redeemBatch = writeBatch(db);
      redeemBatch.update(doc(db, 'venues', venueId, 'invites', 'invite-role-check'), {
        venueId,
        role: 'bartender',
        createdBy: 'manager-1',
        createdAt: now,
        expiresAt: future,
        maxUses: 2,
        currentUses: 1,
        disabled: false,
      });
      redeemBatch.set(doc(db, 'users', 'manager-join-fail'), {
        email: 'wrongrole@example.com',
        displayName: 'Wrong Role',
        role: 'manager',
        venueId,
        active: true,
        inviteId: 'invite-role-check',
        createdAt: '2026-06-17T12:00:00.000Z',
      });
      await assertFails(redeemBatch.commit());
    });
  } finally {
    await testEnv.cleanup();
  }

  if (process.exitCode && process.exitCode !== 0) {
    process.exit(process.exitCode);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
