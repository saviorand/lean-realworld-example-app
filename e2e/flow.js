// Walks the site the way a person would, in Chromium: sign up, publish an article, comment, favorite
// and follow as a second user, change settings, sign out and back in. Prints what it saw at each
// step and exits non-zero on the first thing that does not happen.
//
//   cd e2e && npm install && npx playwright install chromium && node flow.js

const { chromium } = require('playwright');
const base = process.env.BASE_URL || 'http://localhost:8000';
const shots = process.argv[2] || 'screenshots';
require('fs').mkdirSync(shots, { recursive: true });
const uid = Date.now().toString(36);
const log = (...a) => console.log(...a);
async function expectText(page, sel, text) {
  await page.waitForFunction(([s, t]) => [...document.querySelectorAll(s)].some(e => e.textContent.includes(t)), [sel, text], { timeout: 5000 });
}
(async () => {
  const browser = await chromium.launch();
  const alice = await (await browser.newContext({ viewport: { width: 1200, height: 900 } })).newPage();
  const errors = [];
  alice.on('pageerror', e => errors.push('alice: ' + e.message));
  alice.on('console', m => { if (m.type() === 'error') errors.push('alice console: ' + m.text()); });

  // register
  await alice.goto(base + '/register');
  await alice.fill('input[name=username]', 'alice_' + uid);
  await alice.fill('input[name=email]', `alice_${uid}@example.com`);
  await alice.fill('input[name=password]', 'short');
  await alice.click('button:has-text("Sign up")');
  await expectText(alice, '.error-messages li', 'password is too short');
  log('register: short password refused with', await alice.textContent('.error-messages'));
  await alice.fill('input[name=password]', 'password123');
  await alice.click('button:has-text("Sign up")');
  await alice.waitForURL(base + '/');
  await expectText(alice, '.navbar', 'alice_' + uid);
  log('register: signed in, navbar shows', 'alice_' + uid);

  // publish
  await alice.goto(base + '/editor');
  await alice.fill('input[name=title]', `Lean on both ends ${uid}`);
  await alice.fill('input[name=description]', 'A RealWorld app served by Lean');
  await alice.fill('textarea[name=body]', '## Why\n\nBecause *types*.\n\n- server in Lean\n- pages in Lean\n\n<script>alert(1)</script>');
  await alice.fill('input[name=tags]', `lean, datastar_${uid}`);
  await alice.click('button:has-text("Publish Article")');
  await alice.waitForURL(/\/article\//);
  const slug = alice.url().split('/article/')[1];
  log('publish: at', alice.url());
  log('publish: rendered h2 =', await alice.textContent('.article-content h2'), '| em =', await alice.textContent('.article-content em'), '| script tags in body:', await alice.locator('.article-content script').count());
  log('publish: tags =', await alice.locator('.article-content .tag-list li').allTextContents());
  await alice.screenshot({ path: shots + '/1-article.png', fullPage: true });

  // comment then delete
  await alice.fill('textarea[name=body]', 'First comment from Alice');
  await alice.click('button:has-text("Post Comment")');
  await expectText(alice, '#comments .card-text', 'First comment from Alice');
  log('comment: posted; textarea now', JSON.stringify(await alice.inputValue('textarea[name=body]')));
  await alice.click('button:has-text("Post Comment")');
  await expectText(alice, '#comment-errors li', "body can't be blank");
  log('comment: empty refused with', await alice.textContent('#comment-errors'));
  await alice.fill('textarea[name=body]', 'Second, to be deleted');
  await alice.click('button:has-text("Post Comment")');
  await expectText(alice, '#comments .card-text', 'Second, to be deleted');
  await alice.locator('.card', { hasText: 'Second, to be deleted' }).locator('.mod-options').click();
  await alice.waitForFunction(() => ![...document.querySelectorAll('#comments .card-text')].some(e => e.textContent.includes('Second, to be deleted')));
  log('comment: deleted; remaining', await alice.locator('#comments .card-text').allTextContents());

  // bob favorites and follows
  const bob = await (await browser.newContext({ viewport: { width: 1200, height: 900 } })).newPage();
  bob.on('pageerror', e => errors.push('bob: ' + e.message));
  await bob.goto(base + '/register');
  await bob.fill('input[name=username]', 'bob_' + uid);
  await bob.fill('input[name=email]', `bob_${uid}@example.com`);
  await bob.fill('input[name=password]', 'password123');
  await bob.click('button:has-text("Sign up")');
  await bob.waitForURL(base + '/');
  await bob.goto(base + '/article/' + slug);
  await bob.click('#favorite-top');
  await expectText(bob, '#favorite-top', 'Unfavorite');
  log('favorite: top =', (await bob.textContent('#favorite-top')).trim(), '| bottom =', (await bob.textContent('#favorite-bottom')).trim());
  await bob.click('#follow-bottom');
  await expectText(bob, '#follow-top', 'Unfollow');
  log('follow: top =', (await bob.textContent('#follow-top')).trim());
  await bob.screenshot({ path: shots + '/2-article-bob.png' });

  // bob's feed and the tag page
  await bob.goto(base + '/?feed=following');
  log('feed: your feed shows', await bob.locator('.article-preview h1').allTextContents());
  await bob.goto(base + '/');
  await bob.screenshot({ path: shots + '/3-home.png' });
  await bob.click(`.sidebar a:has-text("datastar_${uid}")`);
  await bob.waitForURL(/\/tag\//);
  log('tag page:', bob.url(), 'shows', await bob.locator('.article-preview h1').allTextContents());
  const pv = bob.locator(`#favorite-${slug}`);
  await pv.click();
  await bob.waitForFunction(s => document.querySelector('#favorite-' + s).classList.contains('btn-outline-primary'), slug);
  log('preview: unfavorited from the list, now', (await pv.textContent()).trim());

  // settings and profile
  await alice.goto(base + '/settings');
  await alice.fill('textarea[name=bio]', 'I write Lean');
  await alice.click('button:has-text("Update Settings")');
  await alice.waitForURL(/\/profile\//);
  log('settings: profile bio =', await alice.textContent('.user-info p'));
  await alice.screenshot({ path: shots + '/4-profile.png' });

  // logout, then a wrong password
  await alice.goto(base + '/settings');
  await alice.click('button:has-text("logout")');
  await alice.waitForURL(base + '/');
  log('logout: navbar now', (await alice.textContent('.navbar ul')).replace(/\s+/g, ' ').trim());
  await alice.goto(base + '/login');
  await alice.fill('input[name=email]', `alice_${uid}@example.com`);
  await alice.fill('input[name=password]', 'wrongpassword');
  await alice.click('button:has-text("Sign in")');
  await expectText(alice, '.error-messages li', 'credentials invalid');
  log('login: wrong password ->', await alice.textContent('.error-messages'));
  await alice.fill('input[name=password]', 'password123');
  await alice.click('button:has-text("Sign in")');
  await alice.waitForURL(base + '/');
  log('login: back in as', (await alice.textContent('.navbar ul')).includes('alice_' + uid));

  log('browser errors:', errors.length ? errors : 'none');
  await browser.close();
})().catch(e => { console.error('FAILED:', e.message); process.exit(1); });
