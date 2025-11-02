import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import Twilio from 'twilio';

admin.initializeApp();

const twilioSid = process.env.TWILIO_SID || functions.config().twilio?.sid;
const twilioToken = process.env.TWILIO_TOKEN || functions.config().twilio?.token;
const twilioFrom = process.env.TWILIO_FROM || functions.config().twilio?.from;

const client = twilioSid && twilioToken ? new Twilio(twilioSid, twilioToken) : null;

export const onAlertCreate = functions.firestore
  .document('alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return;

    const type = data.type || 'sos';
    const message: string = data.message || (type === 'safe' ? 'I\'m safe now.' : 'SOS!');
    const recipients: Array<{ phone?: string; name?: string }> = data.recipients || [];

    if (!client || !twilioFrom) {
      console.log('Twilio not configured, skipping SMS send.');
      return;
    }

    const phones = recipients
      .map((r) => (r.phone || '').trim())
      .filter((p) => p.length > 0);

    await Promise.all(
      phones.map(async (to) => {
        try {
          await client.messages.create({ to, from: twilioFrom, body: message });
          console.log('SMS sent to', to);
        } catch (e) {
          console.error('Failed to send SMS to', to, e);
        }
      })
    );
  });
