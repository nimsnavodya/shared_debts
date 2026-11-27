# Project Guide

## App purpose

This app helps groups keep track of money they owe each other. It is for shared debts and group expenses, not daily personal spending.

## People and groups

- Everyone must install the app and create an account.
- People sign in with Google.
- A person can create a group and invite other members.

## Debts and expenses

- A member can record who owes money, who should receive it, and the amount.
- A note can be added, but it is optional.
- Group trip expenses can be shared equally or divided in another way.
- The app can suggest payments that settle the group's balances.

## Closing a debt

- A debt is not closed automatically when someone says they paid.
- The person receiving the money must confirm before the debt is closed.

## History and reminders

- The app keeps a history of changes.
- Reminders are sent every two weeks by default.
- Each member can change how often they get reminders.

## Firebase and Google Sign-in Setup

### How Firebase is connected
1. We use official FlutterFire packages:
   - `firebase_core`: Starts Firebase in Flutter.
   - `firebase_auth`: Manages user accounts and login sessions.
   - `google_sign_in`: Lets users pick their Google account on their phone.
2. The Firebase project is named `shared-debts-app`.
3. The Android app (`com.example.shared_debts`) was registered with FlutterFire.
4. The debug SHA-1 and SHA-256 certificate fingerprints from the Android debug keystore were added to the Firebase project so Google Sign-in works securely on Android.
5. `lib/firebase_options.dart` and `android/app/google-services.json` hold the project settings.

### How Sign-in works in the app
1. **Auth Gate**: When the app opens, an `_AuthGate` checks if someone is already signed in.
2. **Sign-in Screen**: If no one is signed in, the app displays the `SignInScreen` with the "Sign in with Google" button.
3. **Groups Screen**: Once signed in, the app displays `GroupsScreen`.
4. **User Profile & Sign Out**: The top bar of `GroupsScreen` displays a user avatar. Tapping it opens a menu showing the person's Google display name and email, along with a **Sign out** button. Tapping Sign out returns to the sign-in screen.

### Remaining Firebase Console steps (one-time manual check)
To allow Google sign-in to complete on live Google accounts:
1. Open the [Firebase Console](https://console.firebase.google.com/project/shared-debts-app/authentication/providers).
2. Go to **Build** > **Authentication** > **Sign-in method**.
3. Click **Google** under Additional providers.
4. Turn on the **Enable** switch, choose a project support email, and click **Save**.

## Cloud Firestore Setup & Group Storage

### How groups are stored
We use `cloud_firestore` to save and load groups in real time from Google Cloud Firestore:
1. **Collection**: All groups are stored in the top-level collection `groups`.
2. **Document Fields**:
   - `name` (String): The name of the group entered by the user.
   - `kind` (String): Either `'shared'` (general group) or `'trip'` (travel group).
   - `creatorId` (String): The Firebase Authentication UID of the person who created the group.
   - `memberIds` (List of Strings): The Firebase user IDs of everyone in the group. The creator is automatically added as the first member: `[creatorId]`.
   - `createdAt` (Timestamp): Server timestamp when the group was created.

### How groups are loaded in the app
1. **Query**: The app queries `groups` where `memberIds` contains the signed-in user's UID (`arrayContains: userId`).
2. **Persistent across restarts**: Because groups are saved in Firestore with local offline cache enabled, groups remain visible after closing and reopening the app.
3. **Screen States**:
   - **Loading State**: Shows a spinning progress indicator while the groups are loading.
   - **Empty State**: Shows a welcome message and "Create group" button if no groups exist for the user.
   - **Error State**: Displays a clear error message with a **Retry** button if network or permissions fail.

### Security Rules (`firestore.rules`)
We protect user data with Firestore rules:
- **Groups**:
  - **Read**: Only signed-in users who belong to the group (`request.auth.uid in resource.data.memberIds`) can view the group.
  - **Create**: Only authenticated users can create groups, where `creatorId` matches their Firebase UID and `memberIds` starts with only their UID.
  - **Update**: Only existing members can update group information, or new members joining with a valid one-time invitation token.
  - **Delete**: Group deletion is disabled for now.
- **Invitations (`invitations/{token}`)**:
  - **Create**: Only current group members can create an invitation token for their group.
  - **Get**: Any signed-in user who enters the token can look it up (`allow get`).
  - **List**: Collection browsing is forbidden (`allow list: if false`) to prevent discovering tokens.
  - **Delete**: The token is deleted after a user joins so it cannot be reused.
- **Debts (`groups/{groupId}/debts/{debtId}`)**:
  - **Read**: Only signed-in members of the group can view its debts.
  - **Create**: Only signed-in members of the group can record debts. The debtor and creditor must both be members of the group and must be different people. The amount must be a positive number (> 0), status must be `'open'`, and `creatorId` must match the caller.
  - **Update / Delete**: Modifications and deletions are denied to prevent tampering with financial records.
- **Payments (`groups/{groupId}/payments/{paymentId}`)**:
  - **Read**: Only signed-in members of the group can view payment requests and history.
  - **Create**: Only the named payer (a group member) can send a `'pending'` payment request to another group member for a positive amount.
  - **Update**: Only `'pending'` payments can be updated. The named recipient can confirm a payment (`'confirmed'`), and the named payer can cancel their own request (`'cancelled'`). No one else can change them, and confirmed or cancelled payments cannot be modified again.
  - **Delete**: Payment deletion is disabled so the group keeps a permanent history.
- **Users (`users/{userId}`)**:
  - **Read / Write**: Each signed-in user can read and update only their own personal reminder preference (`reminderEnabled` and `reminderIntervalDays` between 1 and 365). No other user can access it.

### Firebase Console steps to create the Firestore database
Before Firestore can accept data in production, it must be created once in your Firebase Console:
1. Open the [Firebase Console Firestore Page](https://console.firebase.google.com/project/shared-debts-app/firestore).
2. Click **Create database**.
3. Choose a Database ID (leave as `(default)`).
4. Choose a location closest to your users (e.g. `nam5 (us-central)`).
5. Choose **Production mode** (or test mode) and click **Create**.
6. Switch to the **Rules** tab, paste the rules from `firestore.rules`, and click **Publish**.

## Debt Management & Net Balances

### How debts are stored
Debts are stored in a dedicated subcollection under each group: `groups/{groupId}/debts/{debtId}`.
1. **Document Fields**:
   - `groupId` (String): ID of the group the debt belongs to.
   - `debtorId` (String): Firebase UID of the person who owes money.
   - `creditorId` (String): Firebase UID of the person who should receive the money.
   - `amount` (Number): The positive monetary amount owed.
   - `note` (String, optional): Description of what the debt was for (e.g. "Dinner", "Gas").
   - `creatorId` (String): Firebase UID of the person who recorded the debt.
   - `createdAt` (Timestamp): Server timestamp when the record was created.
   - `status` (String): Default `'open'`. (Settling/closing debts will be added in a future update).

### How member balances are calculated
The app automatically calculates the net balance for each group member from all `'open'` debts:
1. Every member starts with a balance of `0.0`.
2. For each open debt:
   - The **debtor** owes money: their balance decreases by `amount` (`-amount`).
   - The **creditor** is owed money: their balance increases by `amount` (`+amount`).
3. Example (Simple Debt):
   - Member A owes Member B `50`.
   - Member A balance: `-50` (owes 50).
   - Member B balance: `+50` (is owed 50).
4. Example (Cycle Debt):
   - Member A owes Member B `50`.
   - Member B owes Member C `50`.
   - Member C owes Member A `50`.
   - All three net balances equal `0` (they cancel each other out).
5. Formatting:
   - Positive balances display in green (`+50.00` - "is owed 50.00").
   - Negative balances display in red (`-50.00` - "owes 50.00").
   - Zero balances display in grey (`0` - "settled up").
   - No hardcoded currency symbols are used until a currency preference is selected.

### Group Details Screen
- **Opening a group**: Tapping any group tile on the Groups screen opens `GroupDetailsScreen`.
- **Top Summary**: Displays group title, kind (Shared/Trip), member count, an **Invite member** button, and an **Add debt** action.
- **Member Balances**: Shows every member's current net balance (calculated from open debts and confirmed payments).
- **Suggested payments**: Shows the smallest number of transfers needed to settle all balances (for example, `Nimsara pays Member 2 — 400`). If everyone's balance is zero, it shows **Everyone is settled up**.
- **Pending requests**: When a payer taps **I paid** and sends a payment request (for the full amount or a partial amount), it appears under **Pending requests**. Pending requests do not change balances yet. The payer can **Cancel** it, and the recipient can **Confirm** they received the money.
- **Debts List**: Displays all recorded debts with debtor, creditor, amount, optional note, and status (**Open**, **Partial (amount left)**, or **Settled**). Original debt records are never deleted.
- **Payment history**: Lists all confirmed and cancelled payments for the group.
- **Add Debt Dialog**: Lets users select who owes and who receives (validating that debtor and creditor are different members), enter a positive amount, and add an optional note. If a group has fewer than 2 members, it prompts the user to invite a member first.

## Personal Payment Reminders (Local Notifications)

### How reminders work
- Each signed-in member has their own reminder setting stored in Firestore at `users/{userId}`.
- **Default interval**: **14 days**.
- Tap the bell icon in the top bar of the **Groups** screen to choose **7 days**, **14 days**, **30 days**, enter a **Custom** number of days (1–365), or turn reminders **Off**.
- You are reminded **only** about groups where **you** still owe money. If your balance is zero, if you are owed money, or if a debt has been settled (confirmed payment), the reminder is automatically cancelled.
- Pending payment requests do **not** cancel reminders until the recipient confirms the payment.
- Reminders automatically refresh when the app starts, when it returns to the foreground, when debts or payments change, and when you save new reminder settings.
- On Android 13+, the app asks for notification permission. If permission is denied, the app shows a clear message explaining how to turn notifications on in device settings.

### Limit of local device reminders
Because reminders use **local device notifications** (no paid cloud server or push notifications):
- If another group member adds a debt or confirms a payment **while your app is completely closed**, your phone will not know about that change until the next time you open or resume the app.
- Once you open or resume the app, it syncs with Firestore and immediately schedules, updates, or cancels your local reminders.

## Learning notes

We are learning Flutter as we build this app. Explain new words and steps in simple English.
