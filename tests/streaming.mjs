// Live opt-in API check: node tests/streaming.mjs [http://localhost:5174/api]
// Uses Ollama and deletes only the conversation created by this test.
import assert from 'node:assert/strict';

const base = process.argv[2] || 'http://localhost:5174/api';
const post = (path, body) => fetch(`${base}${path}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body), signal: AbortSignal.timeout(240_000),
});
const created = await post('/conversations', {
  className: 'Test.Agents.SimpleAgent', activeSkills: [],
});
assert.equal(created.status, 201);
const { conversationId: id } = await created.json();
let toolSupportVerified = false;
try {
  for (const body of [{ message: '' }, { message: 42 }, { message: 'Hi', activeSkills: null }, { message: 'Hi', activeSkills: ['Test.Skill.NotAvailable'] }]) {
    const invalid = await post(`/conversations/${id}/messages/stream`, body);
    assert.equal(invalid.status, 400);
    assert.match(invalid.headers.get('content-type'), /application\/json/);
  }
  const missing = await post('/conversations/nonexistent-sse-test/messages/stream', { message: 'Hello' });
  assert.equal(missing.status, 400);

  const started = performance.now();
  const response = await post(`/conversations/${id}/messages/stream`, {
    message: 'Explain how rain forms in eight short sentences. Answer directly without tools.',
  });
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/event-stream/);
  assert.match(response.headers.get('cache-control'), /no-cache/);
  const decoder = new TextDecoder();
  let pending = '';
  const events = [];
  for await (const chunk of response.body) {
    pending += decoder.decode(chunk, { stream: true });
    let boundary;
    while ((boundary = pending.indexOf('\n\n')) >= 0) {
      const frame = pending.slice(0, boundary);
      pending = pending.slice(boundary + 2);
      if (!frame || frame.startsWith(':')) continue;
      const lines = frame.split('\n');
      assert.equal(lines.length, 2, `Unexpected stream output: ${frame.slice(0, 200)}`);
      assert.ok(lines[0].startsWith('event: '));
      assert.ok(lines[1].startsWith('data: '));
      const event = { type: lines[0].slice(7), data: JSON.parse(lines[1].slice(6)), ms: performance.now() - started };
      events.push(event);
      if (event.type !== 'delta') console.log(event.type, Math.round(event.ms), event.data);
    }
  }
  assert.equal(pending, '');
  assert.equal(events[0].type, 'start');
  assert.equal(events.filter(e => e.type === 'done').length, 1);
  assert.equal(events.filter(e => e.type === 'error').length, 0);
  const deltas = events.filter(e => e.type === 'delta');
  const done = events.at(-1);
  assert.equal(done.type, 'done');
  assert.ok(deltas.length > 1, 'Expected multiple native text chunks');
  assert.ok(done.ms - deltas[0].ms > 100, 'Deltas arrived buffered at completion');
  assert.ok(done.ms - events[0].ms > 100, 'Start event arrived buffered at completion');
  assert.ok(done.data.content.length > 0);
  const saved = await (await fetch(`${base}/conversations/${id}`)).json();
  assert.equal(saved.messages.length, 2);
  assert.equal(saved.messages[1].content, done.data.content);
  assert.deepEqual(saved.activeSkills, done.data.activeSkills);

  // Legacy transport still accepts the same chat and returns ordinary JSON.
  const legacy = await post(`/conversations/${id}/messages`, { message: 'Say hello in two words.', activeSkills: [] });
  assert.equal(legacy.status, 200);
  assert.match(legacy.headers.get('content-type'), /application\/json/);
  assert.ok((await legacy.json()).content);
  console.log(`PASS: ${deltas.length} chunks; first delta ${Math.round(deltas[0].ms)}ms, done ${Math.round(done.ms)}ms; saved reply and legacy JSON verified.`);

  // Explicit load, then omit activeSkills: streaming must preserve the saved selection.
  const loaded = await post(`/conversations/${id}/skills`, { activeSkills: ['Test.Skill.Echo'] });
  assert.ok(loaded.ok);
  const toolResponse = await post(`/conversations/${id}/messages/stream`, {
    message: 'Call CountWords with text="happy day" and AnalyzeSentiment with text="happy day", then report the results.',
  });
  const toolEvents = (await toolResponse.text()).split('\n\n').filter(f => f.startsWith('event:')).map(f => ({
    type: f.split('\n')[0].slice(7), data: JSON.parse(f.split('\n')[1].slice(6)),
  }));
  const toolDone = toolEvents.at(-1);
  console.log('tool result', toolDone);
  assert.equal(toolDone.type, 'done');
  assert.deepEqual(toolDone.data.activeSkills, ['Test.Skill.Echo']);
  toolSupportVerified = toolDone.data.stats.total_tool_calls > done.data.stats.total_tool_calls;
  if (toolSupportVerified) {
    console.log('PASS: native tool execution and omitted skill selection preserved');
  } else {
    assert.equal(toolDone.data.role, 'notice');
    console.error('BLOCKED: native StreamChat did not execute tools; preserved skills and saved an explicit notice. Do not migrate tool-based chats.');
  }
} finally {
  const cleanup = await fetch(`${base}/conversations/${id}`, { method: 'DELETE' });
  assert.ok(cleanup.ok, `Cleanup failed: ${cleanup.status}`);
}

// A missing Ollama model fails after SSE starts: one terminal error, saved notice, no done.
const failedChat = await post('/conversations', {
  className: 'Test.Agents.SimpleAgent', model: 'sse-test-nonexistent-model:never-pull', activeSkills: [],
});
assert.equal(failedChat.status, 201);
const { conversationId: failureId } = await failedChat.json();
try {
  const failed = await post(`/conversations/${failureId}/messages/stream`, { message: 'Hello' });
  assert.equal(failed.status, 200);
  const wire = await failed.text();
  assert.equal((wire.match(/event: error\n/g) || []).length, 1);
  assert.ok(!wire.includes('event: done\n'));
  const failure = JSON.parse(wire.split('event: error\ndata: ')[1].trim());
  assert.equal(failure.saved, 1);
  assert.equal(failure.retrySafe, false);
  const saved = await (await fetch(`${base}/conversations/${failureId}`)).json();
  assert.equal(saved.messages.length, 2);
  assert.equal(saved.messages[1].role, 'notice');
  console.log('PASS: provider failure emits terminal SSE error and saves a notice');
} finally {
  assert.ok((await fetch(`${base}/conversations/${failureId}`, { method: 'DELETE' })).ok);
}

// Deliberately fail the full migration gate until native streaming tools work.
assert.ok(toolSupportVerified, 'SSE transport passed, but native streaming tool parity is not verified');
