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

## Learning notes

We are learning Flutter as we build this app. Explain new words and steps in simple English.
