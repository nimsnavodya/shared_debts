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
- **Read**: Only signed-in users who belong to the group (`request.auth.uid in resource.data.memberIds`) can view the group.
- **Create**: Only authenticated users can create groups, where `creatorId` matches their Firebase UID and `memberIds` starts with only their UID.
- **Update**: Only existing members can update group information. Non-members cannot add themselves to groups they do not belong to.
- **Delete**: Only the group creator can delete their group.

### Firebase Console steps to create the Firestore database
Before Firestore can accept data in production, it must be created once in your Firebase Console:
1. Open the [Firebase Console Firestore Page](https://console.firebase.google.com/project/shared-debts-app/firestore).
2. Click **Create database**.
3. Choose a Database ID (leave as `(default)`).
4. Choose a location closest to your users (e.g. `nam5 (us-central)`).
5. Choose **Production mode** (or test mode) and click **Create**.
6. Switch to the **Rules** tab, paste the rules from `firestore.rules`, and click **Publish**.

## Learning notes

We are learning Flutter as we build this app. Explain new words and steps in simple English.
