# Firebase Cloud Functions for Secure Her (Twilio SMS Alerts)

This directory contains a Cloud Function that sends SMS messages via Twilio whenever a new alert document is created in Firestore.

## Setup

1) Install Firebase CLI and login
- npm i -g firebase-tools
- firebase login

2) Initialize functions (if not already)
- From the project root: firebase init functions
- Or just deploy from this functions directory after linking your Firebase project.

3) Configure Twilio credentials (pick one option)
- Using Functions config (recommended):
  firebase functions:config:set twilio.sid="{{TWILIO_ACCOUNT_SID}}" twilio.token="{{TWILIO_AUTH_TOKEN}}" twilio.from="{{TWILIO_PHONE_NUMBER}}"
- Or set environment variables in your CI/CD or shell before deploy:
  export TWILIO_SID={{TWILIO_ACCOUNT_SID}}
  export TWILIO_TOKEN={{TWILIO_AUTH_TOKEN}}
  export TWILIO_FROM={{TWILIO_PHONE_NUMBER}}

4) Install deps and build
- cd functions
- npm install
- npm run build

5) Deploy
- npm run deploy

## Firestore schema

Collection: alerts
- type: "sos" | "safe"
- message: string (the SMS text)
- recipients: array of { name, phone, email }
- createdAt: server timestamp
- active: boolean (true while SOS running)
- last/end: optional location objects { lat, lng, timestamp }
- locations: subcollection with periodic {lat,lng,timestamp} entries for live tracking

When a new document is created, onAlertCreate will send the message to all recipients who have a phone number.
