// Supabase Edge Function: send-push
//
// Receives a notification event from the Postgres trigger (pg_net) and sends
// an FCM push to every device token registered for the target reader_key.
//
// Required secrets:
//   supabase secrets set FCM_SERVER_KEY="<legacy server key>"        # simple
//   # or (recommended, FCM v1):
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='{ ... }'
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically by
// Supabase; the service-role key is also used to authenticate the incoming
// request so nobody on the internet can trigger pushes.
//
// ---------------------------------------------------------------------------
// IMPORTANT (FIX 2026-11-21)
// --------------------------
// The old v1 payload contained `android.notification.priority: 'MAX'`.
// AndroidNotification has NO field named `priority`; the correct field is
// `notificationPriority` (enum PRIORITY_MAX). FCM rejected EVERY v1 message
// with `Unknown name "priority" at 'message.android.notification'`.
// Because send-push caught the error and still returned HTTP 200, pg_net
// logged status_code=200 while no push ever reached a device.
// The inner priority field has been REMOVED (the Android channel is already
// created with Importance.max in notification_service.dart). This payload is
// now valid for ALL event types: notice, fee, attendance, model_test,
// class_routine, result and exam_routine.
//
// Also added:
//   * stale-token cleanup (404 / UNREGISTERED / NOT_FOUND) from student_devices
//   * fallback to the legacy `students.fcm_token` column when student_devices
//     has no row yet (RLS/token-sync race on login)
//   * teacher/staff/admin recipients resolve `users.fcm_token` (the same column
//     the teacher login already writes), so academy salary pushes reuse this
//     Edge Function without a second push service
//   * explicit per-token diagnostics in the JSON response
//   * data-only messages (no `notification` block) so Flutter can draw every
//     push itself: the app icon stays top-left (small icon) and the specific
//     institute logo of the target student is resolved here and sent as
//     `institute_logo_url` for the right-side `largeIcon`. The older generic
//     payload caused duplicate tray entries and unbranded system icons.
// ---------------------------------------------------------------------------

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type PushEvent = {
  reader_key: string;
  type: string;
  title: string;
  body: string;
  route: string;
  target_id?: string | null;
  academy_id?: string | null;
  notification_id?: string | null;
};

type SendOutcome = {
  ok: boolean;
  stale: boolean;
  error?: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

/// FCM uses different spellings for a dead registration token depending on
/// the API version / error path. All of them mean: remove this row.
function isStaleTokenError(raw: string): boolean {
  const s = raw.toUpperCase();
  return (
    s.includes('UNREGISTERED') ||
    s.includes('NOT_REGISTERED') ||
    s.includes('NOTREGISTERED') ||
    s.includes('NOT_FOUND') ||
    s.includes('INVALID_REGISTRATION') ||
    s.includes('"CODE":404') ||
    /\b404\b/.test(s)
  );
}

/// Shared PostgREST select helper (service role bypasses RLS).
async function selectTokens(
  supabaseUrl: string,
  serviceKey: string,
  query: string,
): Promise<string[]> {
  try {
    const response = await fetch(`${supabaseUrl}/rest/v1/${query}`, {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    });
    if (!response.ok) return [];
    const rows = await response.json() as Array<{ fcm_token?: unknown }>;
    return rows
      .map((r) => String(r.fcm_token ?? '').trim())
      .filter((t) => t.length > 0);
  } catch (_) {
    return [];
  }
}

function cleanText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/// Only real http(s) URLs are safe to hand to the app's bitmap downloader.
function safeLogoUrl(value: unknown): string {
  const raw = cleanText(value);
  if (!raw || raw.length > 2048) return '';
  try {
    const parsed = new URL(raw);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return '';
    return parsed.toString();
  } catch (_) {
    return '';
  }
}

async function selectFirst(
  supabaseUrl: string,
  serviceKey: string,
  query: string,
): Promise<Record<string, unknown> | null> {
  try {
    const response = await fetch(`${supabaseUrl}/rest/v1/${query}&limit=1`, {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    });
    if (!response.ok) return null;
    const rows = await response.json() as Array<Record<string, unknown>>;
    return rows.length > 0 ? rows[0] : null;
  } catch (_) {
    return null;
  }
}

/// Resolves the logo of the institute that owns the target student.
/// `reader_key` is authoritative (`student:<id>`), so a stale/missing
/// `academy_id` in the event cannot show another institute's logo.
async function resolveInstituteLogoUrl(
  supabaseUrl: string,
  serviceKey: string,
  event: PushEvent,
  studentId: string,
): Promise<string> {
  try {
    let academyId = cleanText(event.academy_id);

    if (studentId) {
      const student = await selectFirst(
        supabaseUrl,
        serviceKey,
        `students?select=academy_id&id=eq.${encodeURIComponent(studentId)}`,
      );
      academyId = cleanText(student?.academy_id) || academyId;
    }

    if (!academyId) return '';
    const academy = await selectFirst(
      supabaseUrl,
      serviceKey,
      `academies?select=logo_url&id=eq.${encodeURIComponent(academyId)}`,
    );
    return safeLogoUrl(academy?.logo_url);
  } catch (_) {
    // Branding is best-effort: a failed lookup must never block the push.
    return '';
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  // Only the database trigger (service role) may call this function.
  const expected = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const supplied = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  if (!expected || supplied !== expected) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  let event: PushEvent;
  try {
    event = await req.json() as PushEvent;
  } catch (_) {
    return jsonResponse({ error: 'invalid payload' }, 400);
  }
  if (!event?.reader_key || !event?.title) {
    return jsonResponse({ error: 'reader_key and title are required' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceKey) {
    return jsonResponse({ error: 'server misconfigured' }, 500);
  }

  // 1. Resolve device tokens for this recipient (service role bypasses RLS).
  //    Student reader keys are `student:<id>`; teacher/staff keys are
  //    `teacher:<id>`; admins use their auth uid directly.
  let tokens: string[] = [];
  let tokenSource = 'student_devices';
  let recipientId = '';
  const isStudent = event.reader_key.startsWith('student:');

  if (isStudent) {
    recipientId = event.reader_key.substring('student:'.length);

    tokens = await selectTokens(
      supabaseUrl,
      serviceKey,
      `student_devices?select=fcm_token&student_id=eq.${encodeURIComponent(recipientId)}`,
    );

    // FALLBACK: FcmTokenService also mirrors the token into
    // `students.fcm_token`. Use it when the student_devices insert was blocked
    // (e.g. reader_key not yet stored in app_sessions at login time).
    if (tokens.length === 0) {
      const legacy = await selectTokens(
        supabaseUrl,
        serviceKey,
        `students?select=fcm_token&id=eq.${encodeURIComponent(recipientId)}&fcm_token=not.is.null`,
      );
      if (legacy.length > 0) {
        tokens = legacy;
        tokenSource = 'students.fcm_token (fallback)';
      }
    }

    // De-duplicate: a student may have the same token in both tables.
    tokens = Array.from(new Set(tokens));
  } else {
    recipientId = event.reader_key.startsWith('teacher:')
      ? event.reader_key.substring('teacher:'.length)
      : event.reader_key;

    if (recipientId) {
      tokens = await selectTokens(
        supabaseUrl,
        serviceKey,
        `users?select=fcm_token&id=eq.${encodeURIComponent(recipientId)}&fcm_token=not.is.null`,
      );
      if (tokens.length > 0) tokenSource = 'users.fcm_token';
    }
  }

  if (tokens.length === 0) {
    // Explicit diagnostics so `net._http_response.content` explains WHY.
    return jsonResponse({
      sent: 0,
      attempted: 0,
      reason: 'no device tokens',
      reader_key: event.reader_key,
      recipient_id: recipientId || '(unresolved)',
      hint: isStudent
        ? 'Student has not registered an FCM token. Check app_sessions.reader_key ' +
          'and student_devices for this student (see diagnosis SQL in the deploy notes).'
        : 'Teacher/staff has no FCM token in users.fcm_token. Ask them to log out ' +
          'and back in so the token is refreshed, then retry the salary payment.',
    });
  }

  // Resolve the target institute logo before building the payload. Students are
  // looked up by id; teacher/admin events already carry academy_id from the
  // trigger, so branding stays correct without another table scan.
  // Any failure degrades to an empty string; Flutter then uses its own fallback
  // large icon and the notification is still delivered normally.
  const instituteLogoUrl = await resolveInstituteLogoUrl(
    supabaseUrl,
    serviceKey,
    event,
    isStudent ? recipientId : '',
  );

  // Data-only push: the Flutter app draws the notification itself so the app
  // icon stays top-left and this student's institute logo appears on the right.
  // A stable notification_id lets duplicates replace each other in the tray.
  const data: Record<string, string> = {
    type: event.type,
    route: event.route || event.type,
    target_id: event.target_id ?? '',
    academy_id: event.academy_id ?? '',
    notification_id: event.notification_id ?? '',
    title: event.title,
    body: event.body ?? '',
    show_local: 'true',
    institute_logo_url: instituteLogoUrl,
  };

  let sent = 0;
  const failures: Array<{ token: string; error: string }> = [];
  const staleTokens: string[] = [];

  for (const token of tokens) {
    try {
      const outcome = await sendToToken(token, data);
      if (outcome.ok) {
        sent++;
      } else {
        failures.push({ token: maskToken(token), error: outcome.error ?? 'unknown FCM error' });
        if (outcome.stale) staleTokens.push(token);
      }
    } catch (e) {
      failures.push({ token: maskToken(token), error: String(e) });
    }
  }

  // 2. Clean up dead tokens so one stale device never blocks an active one.
  let cleanedStaleTokens = 0;
  for (const token of staleTokens) {
    try {
      const response = isStudent
        ? await fetch(
            `${supabaseUrl}/rest/v1/student_devices?fcm_token=eq.${encodeURIComponent(token)}`,
            {
              method: 'DELETE',
              headers: {
                apikey: serviceKey,
                Authorization: `Bearer ${serviceKey}`,
              },
            },
          )
        : await fetch(
            `${supabaseUrl}/rest/v1/users?id=eq.${encodeURIComponent(recipientId)}&fcm_token=eq.${encodeURIComponent(token)}`,
            {
              method: 'PATCH',
              headers: {
                apikey: serviceKey,
                Authorization: `Bearer ${serviceKey}`,
                'Content-Type': 'application/json',
                Prefer: 'return=minimal',
              },
              body: JSON.stringify({ fcm_token: null }),
            },
          );
      if (response.ok) cleanedStaleTokens++;
    } catch (_) {
      // Cleanup is best-effort; delivery to other tokens already succeeded.
    }
  }

  return jsonResponse({
    sent,
    attempted: tokens.length,
    tokenSource,
    institute_logo: instituteLogoUrl ? 'resolved' : 'fallback',
    cleanedStaleTokens,
    failures,
  });
});

function maskToken(token: string): string {
  return token.length > 12 ? `${token.slice(0, 6)}...${token.slice(-4)}` : '***';
}

// ---------------------------------------------------------------------------
// FCM v1 (service account) with legacy server-key fallback
// ---------------------------------------------------------------------------
async function sendToToken(
  token: string,
  data: Record<string, string>,
): Promise<SendOutcome> {
  const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');

  if (serviceAccountJson) {
    try {
      const accessToken = await getOAuth2Token(serviceAccountJson);
      const projectId = JSON.parse(serviceAccountJson).project_id;
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          // DATA-ONLY FCM v1 payload. Android must not draw its own generic
          // notification: the app renders it with the branded small icon and
          // institute logo (lib/services/notification_style.dart).
          // `android.priority` is delivery priority (HIGH/NORMAL);
          // `notificationPriority` is the Android notification priority.
          body: JSON.stringify({
            message: {
              token,
              data,
              android: {
                priority: 'HIGH',
                notification: {
                  channelId: 'high_importance_channel',
                  notificationPriority: 'PRIORITY_MAX',
                  visibility: 'PUBLIC',
                },
              },
            },
          }),
        },
      );
      const text = await response.text();
      if (!response.ok) {
        return {
          ok: false,
          stale: isStaleTokenError(text),
          error: text,
        };
      }
      return { ok: true, stale: false };
    } catch (e) {
      return { ok: false, stale: false, error: String(e) };
    }
  }

  const serverKey = Deno.env.get('FCM_SERVER_KEY');
  if (!serverKey) {
    return { ok: false, stale: false, error: 'No FCM credential configured' };
  }

  try {
    const response = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        Authorization: `key=${serverKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        to: token,
        priority: 'high',
        data,
      }),
    });
    const text = await response.text();
    if (!response.ok) {
      return { ok: false, stale: isStaleTokenError(text), error: text };
    }

    // The legacy endpoint answers 200 even when delivery failed.
    let parsed: {
      failure?: number;
      results?: Array<{ error?: string; message_id?: string }>;
    } | null = null;
    try {
      parsed = JSON.parse(text);
    } catch (_) {
      parsed = null;
    }
    if (parsed && (parsed.failure ?? 0) > 0) {
      const first = parsed.results?.[0] ?? {};
      const errorText = JSON.stringify(first);
      return {
        ok: false,
        stale: isStaleTokenError(errorText),
        error: errorText,
      };
    }
    return { ok: true, stale: false };
  } catch (e) {
    return { ok: false, stale: false, error: String(e) };
  }
}

async function getOAuth2Token(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson) as {
    client_email: string;
    private_key: string;
  };
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${payload}`;

  const pem = sa.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const keyBytes = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${b64urlBytes(new Uint8Array(signature))}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(await response.text());
  const json = await response.json() as { access_token: string };
  return json.access_token;
}

function b64url(value: string): string {
  return b64urlBytes(new TextEncoder().encode(value));
}

function b64urlBytes(bytes: Uint8Array): string {
  let binary = '';
  bytes.forEach((b) => (binary += String.fromCharCode(b)));
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}
