# Cocktail Training Manual Test Plan

Last updated: 2026-06-17

Use this plan after significant app, Firebase, or Cloudflare changes. Run the checks against the live production build unless a test explicitly says local or preview.

## Test accounts and setup

Prepare:

- one owner/admin account
- one manager account
- one bartender account
- one valid bartender invite
- one valid manager invite
- one expired invite
- one disabled or already-used invite
- one mobile browser
- one normal desktop browser tab
- one incognito/private tab

## 1. Login

1. Open the production URL in a normal browser tab.
2. Log in as owner/admin.
3. Confirm the app loads the signed-in workspace.
4. Sign out.
5. Repeat for manager.
6. Sign out.
7. Repeat for bartender.

Expected:

- all three accounts can sign in
- no demo login copy appears in production
- the correct workspace loads for each role

## 2. Logout

1. Log in as each role.
2. Use the in-app logout action.
3. Refresh the page.

Expected:

- the user returns to the login screen
- no protected workspace remains visible after refresh

## 3. Forgotten password

1. Open the login screen.
2. Enter a real account email.
3. Use `Forgot password? Send reset link`.

Expected:

- the app confirms the reset flow clearly
- the user receives the Firebase password reset email

## 4. Manager invite bartender

1. Log in as manager.
2. Open the team/invite area.
3. Create a bartender invite.
4. Copy the invite link or QR code.

Expected:

- the invite is created under the manager's venue
- the invite role is bartender
- the invite appears in the manager's invite list

## 5. Manager invite manager

1. Log in as manager.
2. Create a manager invite.

Expected:

- the invite is created successfully if the current venue policy allows it
- the invite role is manager

## 6. Bartender join via invite

1. Open a valid bartender invite link in a logged-out browser.
2. Complete the join flow.
3. Sign in with the new account.

Expected:

- no role chooser appears
- the account is assigned bartender access automatically
- the user lands in the bartender training workspace

## 7. Manager join via invite

1. Open a valid manager invite link in a logged-out browser.
2. Complete the join flow.
3. Sign in with the new account.

Expected:

- no role chooser appears
- the account is assigned manager access automatically
- the user can access both bartender and manager workflows

## 8. Expired invite

1. Open an expired invite link.

Expected:

- the join flow is blocked
- the error message is clear and not technical

## 9. Used invite

1. Open an invite that has already reached its maximum uses, or a disabled invite.

Expected:

- the join flow is blocked
- the invite cannot be reused

## 10. Bartender access restrictions

1. Sign in as bartender.
2. Try to reach manager and admin areas through navigation and direct URLs if possible.

Expected:

- bartender sees library, study, quiz, and own progress
- bartender does not see settings/admin tools, team tools, or invite management

## 11. Manager access restrictions

1. Sign in as manager.
2. Open the workspace.
3. Try to access owner-only setup functions.

Expected:

- manager can still use library, study, quiz, and own progress
- manager can access team tools
- manager cannot access owner/admin-only setup actions

## 12. Cocktail library loading

1. Sign in as bartender.
2. Open the approved cocktail library.

Expected:

- approved cocktails load correctly
- cards show names, key details, and linked images where available
- no draft-only or duplicate items appear

## 13. Study mode

1. Sign in as bartender.
2. Open study mode.
3. Reveal spec details on several recipes.

Expected:

- the reveal flow works smoothly on mobile
- ingredients, garnish, glassware, method, and batch details are readable

## 14. Quiz mode

1. Sign in as bartender.
2. Start a practice quiz.
3. Start a garnish/glassware quiz if available.
4. Submit answers.

Expected:

- spec questions show units such as `ml`
- the quiz completes without errors
- results appear immediately

## 15. Quiz results saved

1. Submit at least one practice quiz and one live surprise quiz if available.
2. Refresh the app.
3. Reopen progress or results.
4. Sign in as manager and review team results.

Expected:

- bartender can still see personal results after refresh
- manager can see team results for the same venue

## 16. Normal tab after deployment

1. After a production deploy, open the site in a normal browser tab.
2. Hard refresh once if needed.
3. Sign in and move through the main screens.

Expected:

- the latest build loads
- login works
- no stale service-worker or cache symptoms appear

## 17. Incognito tab after deployment

1. Open the site in an incognito/private tab.
2. Sign in and open the main screens.

Expected:

- behaviour matches the normal tab
- incognito is not required for a clean app state

## 18. Mobile browser navigation

1. Open the production site on a phone.
2. Log in as bartender and as manager.
3. Move through the key screens.
4. Use the app back buttons and the browser back action carefully.

Expected:

- navigation stays inside the app flow
- mobile layout remains readable
- buttons and tabs remain usable without horizontal overflow

## 19. Cloudflare deployment sanity check

1. Confirm the latest production deployment is from the intended GitHub repository and branch.
2. Confirm production environment variables are present.
3. Confirm the Firebase authorized domain includes the production URL.
4. Confirm the live site loads the expected build.

Expected:

- production points at the intended repo
- the live domain is authorized in Firebase
- the build is in Firebase mode, not demo mode

## 20. PDF sales import sanity check

1. Sign in as manager.
2. Create or open a stock concern session with priced target cocktails.
3. Import a sample Aztec-style sales PDF.

Expected:

- only approved, priced target cocktails are imported
- bartender matching works when the name is present
- if the bartender name is not found, each target cocktail is filled with `25` for manager testing
- unmatched products are shown for review

## 21. Commodity CSV ingredient price import

1. Sign in as owner/admin.
2. Open ingredient costs.
3. Import the commodity CSV.

Expected:

- matched ingredients update bottle size and bottle price
- unmatched ingredients are listed clearly
- manual edits remain possible afterwards

## Release sign-off checklist

Before marking a release ready:

1. Run `npm run test:firestore-rules`.
2. Run login, logout, and password reset.
3. Run one invite redemption flow.
4. Run bartender access restriction and manager restriction checks.
5. Run one practice quiz and confirm results save.
6. Run one sales PDF import if that area changed.
7. Open the production build in both a normal and incognito tab.
