// One virtual user (VU) = one person using the app in a loop.
//   k6 run -e BASE_URL=http://10.0.0.x -e VUS=500 social.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const VUS = Number(__ENV.VUS || 10);
const RAMP = __ENV.RAMP || '1m';
const HOLD = __ENV.HOLD || '3m';
const NUM_USERS = 50000;
const OUT_DIR = __ENV.OUT_DIR || 'results';

export const options = {
  scenarios: {
    users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: RAMP, target: VUS }, // ramp up
        { duration: HOLD, target: VUS }, // hold: this is the part that counts
        { duration: '20s', target: 0 },  // ramp down
      ],
      gracefulRampDown: '10s',
    },
  },
  // Pass/fail for "the server supports this many users".
  thresholds: {
    http_req_failed: ['rate<0.01'],   // < 1% errors
    http_req_duration: ['p(95)<500'], // 95% of requests under 500 ms
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const rand = (min, max) => min + Math.random() * (max - min);
const chance = (p) => Math.random() < p;

export default function () {
  const userId = ((__VU - 1) % NUM_USERS) + 1;
  const headers = { 'x-user-id': String(userId) };
  const jsonHeaders = { ...headers, 'content-type': 'application/json' }; // only for requests with a body
  // Only the feed's body is needed; skipping the rest saves load-generator memory.
  const noBody = { headers, responseType: 'none' };

  // 1. Load the feed.
  const feed = http.get(`${BASE_URL}/api/feed`, { headers, tags: { name: 'feed' } });
  check(feed, { 'feed 200': (r) => r.status === 200 });
  const posts = feed.status === 200 ? feed.json('posts') : [];

  sleep(rand(2, 5)); // scroll and read

  // 2. Open a post from the feed.
  if (posts.length) {
    const post = posts[Math.floor(Math.random() * posts.length)];
    const res = http.get(`${BASE_URL}/api/posts/${post.id}`, { ...noBody, tags: { name: 'post' } });
    check(res, { 'post 200': (r) => r.status === 200 });

    sleep(rand(1, 3));

    // 3. Like it (15%).
    if (chance(0.15)) {
      const like = http.post(`${BASE_URL}/api/posts/${post.id}/like`, null, { ...noBody, tags: { name: 'like' } });
      check(like, { 'like 200': (r) => r.status === 200 });
    }
  }

  // 4. Write a post (2%).
  if (chance(0.02)) {
    const body = JSON.stringify({ body: `hello from vu ${__VU} at ${Date.now()}` });
    const created = http.post(`${BASE_URL}/api/posts`, body, { headers: jsonHeaders, responseType: 'none', tags: { name: 'create' } });
    check(created, { 'create 201': (r) => r.status === 201 });
  }

  sleep(rand(5, 10)); // wander off, come back later
}

// End-of-run report: normal console summary + one CSV row for the results table.
export function handleSummary(data) {
  const m = data.metrics;
  const d = m.http_req_duration.values;
  const row = [
    VUS,
    m.http_reqs.values.rate.toFixed(1),
    m.http_reqs.values.count,
    (m.http_req_failed.values.rate * 100).toFixed(2),
    d.med.toFixed(1),
    d['p(95)'].toFixed(1),
    d['p(99)'].toFixed(1),
    d.max.toFixed(1),
  ];
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
    [`${OUT_DIR}/vus-${VUS}.json`]: JSON.stringify(data, null, 2),
    [`${OUT_DIR}/vus-${VUS}.row.csv`]: row.join(',') + '\n',
  };
}
