import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import ReactMarkdown from 'react-markdown';
import { normalizeMath, remarkPlugins, rehypePlugins } from './markdown.js';
import 'katex/dist/katex.min.css';
import './style.css';

const markdownComponents = {
  table: ({ children }) => <div className="table-scroll"><table>{children}</table></div>,
};

function resizeComposer(input) {
  if (!input) return;
  // Reset before measuring so deleting text also shrinks the input.
  input.style.height = 'auto';
  const limit = parseFloat(window.getComputedStyle(input).maxHeight);
  input.style.height = `${Math.min(input.scrollHeight, limit)}px`;
  input.style.overflowY = input.scrollHeight > limit ? 'auto' : 'hidden';
}

async function responseJSON(response) {
  const body = await response.text();

  if (!body || !body.trim()) {
    console.log('EMPTY RESPONSE', response.status, response.url);
    throw new Error(`Empty response from ${response.url} (${response.status})`);
  }

  if (response.status === 504) {
    throw new Error('The model request timed out. Please retry with a shorter prompt or fewer active skills.');
  }

  if (response.status >= 400) {
    let payload;
    try {
      payload = JSON.parse(body);
    } catch (parseError) {
      console.log('NON-JSON ERROR RESPONSE', response.status, response.url, body.slice(0, 500));
      throw new Error(`Request failed from ${response.url} (${response.status})`);
    }
    throw new Error(payload.message || `Request failed (${response.status})`);
  }

  try {
    return JSON.parse(body);
  } catch (err) {
    console.log('NON-JSON RESPONSE', response.status, response.url, body.slice(0, 500));
    throw new Error(`Invalid JSON from ${response.url} (${response.status})`);
  }
}


function App() {
  const [agents, setAgents] = useState([]);
  const [providers, setProviders] = useState([]);
  const [history, setHistory] = useState([]);
  const [agent, setAgent] = useState('');
  const [model, setModel] = useState('');
  const [conversation, setConversation] = useState('');
  const [messages, setMessages] = useState([]);
  const [activeSkills, setActiveSkills] = useState([]);
  const [skillAction, setSkillAction] = useState('');
  const [text, setText] = useState('');
  const [stats, setStats] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [agentDetailsOpen, setAgentDetailsOpen] = useState(true);
  const [configurationOpen, setConfigurationOpen] = useState(true);
  const [historyOpen, setHistoryOpen] = useState(true);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(
    () => window.localStorage.getItem('agent-studio-sidebar') === 'collapsed',
  );
  const chatRef = useRef(null);
  const composerRef = useRef(null);
  const selected = agents.find((item) => item.className === agent);
  const provider = providers[0];

  useLayoutEffect(() => {
    resizeComposer(composerRef.current);
  }, [text]);

  useEffect(() => {
    const input = composerRef.current;
    let width = input.clientWidth;
    const resize = () => resizeComposer(input);
    const observer = new ResizeObserver(() => {
      if (input.clientWidth !== width) {
        width = input.clientWidth;
        resize();
      }
    });
    observer.observe(input);
    window.addEventListener('resize', resize);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', resize);
    };
  }, []);

  useEffect(() => {
    fetch('/api/agents')
      .then(responseJSON)
      .then((items) => {
        setAgents(items);
        setAgent(items[0]?.className || '');
      })
      .catch((requestError) => setError(requestError.message));
  }, []);

  useEffect(() => {
    refreshHistory();
  }, []);

  useEffect(() => {
    fetch('/api/providers')
      .then(responseJSON)
      .then((items) => {
        setProviders(items);
        setModel(items[0]?.model || items[0]?.models?.[0] || '');
      })
      .catch((requestError) => setError(requestError.message));
  }, []);

  useEffect(() => {
    chatRef.current?.scrollTo({ top: chatRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages, busy]);

  useEffect(() => {
    window.localStorage.setItem('agent-studio-sidebar', sidebarCollapsed ? 'collapsed' : 'expanded');
  }, [sidebarCollapsed]);

  function choose(value) {
    if (busy) return;
    setAgent(value);
    setConversation('');
    setMessages([]);
    setActiveSkills([]);
    setError('');
    setStats(null);
  }

  async function refreshHistory() {
    try {
      const response = await fetch('/api/conversations');
      const items = await responseJSON(response);
      if (!response.ok) throw Error(items.message);
      setHistory(items);
    } catch (requestError) {
      setError(requestError.message);
    }
  }

  async function openConversation(id) {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      const response = await fetch(`/api/conversations/${encodeURIComponent(id)}`);
      const data = await responseJSON(response);
      if (!response.ok) throw Error(data.message);
      setConversation(data.conversationId);
      setAgent(data.agentClass);
      setModel(data.model);
      setMessages(data.messages || []);
      setActiveSkills(data.activeSkills || []);
      setStats(null);
    } catch (requestError) {
      setError(requestError.message);
    } finally {
      setBusy(false);
    }
  }

  async function deleteConversation(id) {
    if (busy) return;
    if (!window.confirm('Delete this conversation?')) return;
    try {
      const response = await fetch(`/api/conversations/${encodeURIComponent(id)}`, { method: 'DELETE' });
      if (!response.ok) throw Error('Could not delete conversation');
      if (conversation === id) choose(agent);
      await refreshHistory();
    } catch (requestError) {
      setError(requestError.message);
    }
  }

  async function startConversation() {
    const response = await fetch('/api/conversations', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ className: agent, model, activeSkills }),
    });
    const data = await responseJSON(response);
    if (!response.ok) throw Error(data.message);
    setConversation(data.conversationId);
    const saved = await fetch(`/api/conversations/${encodeURIComponent(data.conversationId)}`).then(responseJSON);
    setActiveSkills(saved.activeSkills || []);
    return data.conversationId;
  }

  async function sendMessage(conversationId, prompt) {
    const response = await fetch(
      `/api/conversations/${encodeURIComponent(conversationId)}/messages`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: prompt, activeSkills }),
      },
    );
    const data = await responseJSON(response);
    if (!response.ok) throw Error(data.message);
    return data;
  }

  async function send(event) {
    event.preventDefault();
    if (!text.trim() || busy || !agent) return;

    setBusy(true);
    setError('');
    const prompt = text.trim();
    setText('');
    setMessages((items) => [...items, { role: 'user', content: prompt }]);

    try {
      const conversationId = conversation || await startConversation();
      const data = await sendMessage(conversationId, prompt);
      setMessages((items) => [
        ...items,
        { role: data.role || 'assistant', content: data.content },
      ]);
      setActiveSkills(data.activeSkills || activeSkills);
      setStats(data.stats);
      await refreshHistory();
    } catch (requestError) {
      setMessages(messages);
      setText((draft) => draft || prompt);
      setError(requestError.message);
      await refreshHistory();
    } finally {
      setBusy(false);
    }
  }

  function handleComposerKeyDown(event) {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      event.currentTarget.form?.requestSubmit();
    }
  }

  async function toggleSkill(skill) {
    if (busy) return;
    const skills = activeSkills.includes(skill)
      ? activeSkills.filter((item) => item !== skill)
      : [...activeSkills, skill];
    setBusy(true);
    setSkillAction(skill);
    setError('');
    try {
      const id = conversation || await startConversation();
      const data = await fetch(`/api/conversations/${encodeURIComponent(id)}/skills`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ activeSkills: skills }),
      }).then(responseJSON);
      setActiveSkills(data.activeSkills || []);
      setMessages(data.messages || []);
      await refreshHistory();
    } catch (requestError) {
      setError(requestError.message);
    } finally {
      setSkillAction('');
      setBusy(false);
    }
  }

  return (
    <main className={`app-shell${sidebarCollapsed ? ' sidebar-collapsed' : ''}`}>
      <aside className="sidebar">
        <div className="brand"><button className="brand-toggle" onClick={() => setSidebarCollapsed((collapsed) => !collapsed)} aria-label={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'} title={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}><span className="brand-mark">✦</span></button><div><small>INTERSYSTEMS AI HUB</small><strong>Agent Studio</strong></div></div>
        <button className="new-chat" disabled={busy} onClick={() => choose(agent)} title="New chat"><span>＋</span><span className="new-chat-label">New chat</span></button>
        <section className="history-section">
          <button className="section-toggle" aria-expanded={historyOpen} aria-controls="recent-chats" onClick={() => setHistoryOpen((open) => !open)}><span className="eyebrow">Recent chats</span><span>{history.length}</span><span aria-hidden="true">{historyOpen ? '⌄' : '›'}</span></button>
          <div className="history-list" id="recent-chats" hidden={!historyOpen}>
            {!history.length && <p className="history-empty">Your conversations will appear here.</p>}
            {history.map((item) => (
              <div className={`history-row${conversation === item.conversationId ? ' active' : ''}`} key={item.conversationId}>
                <button className="history-item" disabled={busy} onClick={() => openConversation(item.conversationId)}>
                  <span className="history-icon">◌</span>
                  <span className="history-copy"><strong>{item.title}</strong><small>{item.agentClass}</small></span>
                </button>
                <button className="history-delete" disabled={busy} title="Delete chat" onClick={() => deleteConversation(item.conversationId)}>×</button>
              </div>
            ))}
          </div>
        </section>
        <div className="sidebar-section">
          <button className="section-toggle" aria-expanded={configurationOpen} aria-controls="configuration" onClick={() => setConfigurationOpen((open) => !open)}><span className="eyebrow">Configuration</span><span aria-hidden="true">{configurationOpen ? '⌄' : '›'}</span></button>
          <div className="configuration-fields" id="configuration" hidden={!configurationOpen}>
          <label>Agent<select value={agent} disabled={busy || !!conversation} onChange={(event) => choose(event.target.value)}>{agents.map((item) => <option key={item.className}>{item.className}</option>)}</select></label>
          <label>Provider<div className="provider-field"><span className="status-dot" />{provider?.name || 'Loading…'}</div></label>
          <label>Model<select value={model} onChange={(event) => setModel(event.target.value)} disabled={busy || !!conversation || !provider?.models?.length}>{model && !provider?.models?.includes(model) && <option value={model}>{model} (saved)</option>}{!model && !provider?.models?.length && <option value="">No models available</option>}{provider?.models?.map((item) => <option key={item}>{item}</option>)}</select></label>
          {conversation && <p className="field-help">Start a new chat to change agent or model.</p>}
          </div>
        </div>
        {selected && (
          <div className={`agent-card${agentDetailsOpen ? ' open' : ''}`}>
            <button className="agent-card-toggle" onClick={() => setAgentDetailsOpen((open) => !open)} aria-expanded={agentDetailsOpen}>
              <span className="agent-symbol">A</span>
              <span className="agent-summary"><small>Selected agent</small><strong>{selected.className}</strong></span>
              <span className="chevron">⌄</span>
            </button>
            {agentDetailsOpen && <div className="agent-details">
              <p>{selected.description}</p>
              <div className="capability-group skills">
                <div className="capability-heading"><span>Skills</span><b>{activeSkills.length} active / {selected.skills.length}</b></div>
                <p className="field-help">Load activates instructions immediately in this chat. A Studio message confirms each change; no model request is needed.</p>
                <ul>{selected.skills.length ? selected.skills.map((item) => {
                  const enabled = activeSkills.includes(item);
                  const state = skillAction === item ? 'Saving…' : enabled ? 'Unload' : 'Load';
                  return <li className={enabled ? 'active' : ''} key={item}><button type="button" aria-pressed={enabled} aria-label={`${state} ${item.split('.').pop()}`} disabled={busy} title={item} onClick={() => toggleSkill(item)}><span className="capability-icon">✦</span><span className="skill-name">{item.split('.').pop()}{enabled && <small> · Active</small>}</span><span className="skill-state">{state}</span></button></li>;
                }) : <li className="empty">No skills declared by this agent</li>}</ul>
              </div>
              <div className="capability-group toolsets">
                <div className="capability-heading"><span>Toolsets</span><b>{selected.toolSets.length}</b></div>
                <ul>{selected.toolSets.length ? selected.toolSets.map((item) => <li key={item}><span className="capability-icon">⌘</span><span>{item}</span></li>) : <li className="empty">None</li>}</ul>
              </div>
            </div>}
          </div>
        )}
        <div className="sidebar-footer">Local inference · {provider?.name || 'Loading provider…'}</div>
      </aside>
      <section className="workspace">
        <header className="topbar"><div><span className="mobile-brand">Agent Studio</span><strong>{selected?.className || 'Choose an agent'}</strong><span className="model-pill">{model || 'Default model'}</span></div></header>
        <section className="chat" ref={chatRef}>
          {!messages.length && <div className="welcome"><div className="welcome-icon">✦</div><h1>How can I help?</h1><p>Chat with <strong>{selected?.className || 'an agent'}</strong>, powered by {provider?.name || 'your provider'}.</p>{selected?.examplePrompt && <button className="suggestion" onClick={() => setText(selected.examplePrompt)}>{selected.examplePrompt}<span>→</span></button>}</div>}
          <div className="message-list">{messages.map((message, index) => <article className={message.role} key={`${message.role}-${index}`}><div className="avatar">{message.role === 'user' ? 'Y' : '✦'}</div><div className="message-content"><b>{message.role === 'user' ? 'You' : message.role === 'notice' ? 'Studio' : selected?.className}</b><ReactMarkdown remarkPlugins={remarkPlugins} rehypePlugins={rehypePlugins} components={markdownComponents}>{normalizeMath(message.content)}</ReactMarkdown></div></article>)}{busy && <div className="working"><span /><span /><span /> {skillAction ? 'Updating skills' : 'Agent is thinking'}</div>}</div>
        </section>
        <div className="composer-wrap">
          <div className="skill-summary" role="status">Active skills: {activeSkills.length ? activeSkills.map((skill) => skill.split('.').pop()).join(', ') : 'none'}</div>
          {error && <div className="error">{error}</div>}
          <form onSubmit={send} className="composer"><textarea ref={composerRef} value={text} onChange={(event) => setText(event.target.value)} onKeyDown={handleComposerKeyDown} placeholder={`Message ${selected?.className || 'agent'}`} rows="1" /><button className="send-button" disabled={busy || !agent || !text.trim()} title="Send message">↑</button></form>
          <div className="composer-meta"><span><kbd>Enter</kbd> send · <kbd>Shift</kbd> + <kbd>Enter</kbd> new line</span>{stats && <span>{stats.total_prompt_tokens || 0} prompt · {stats.total_completion_tokens || 0} completion · {stats.total_tool_calls || 0} tools</span>}</div>
        </div>
      </section>
    </main>
  );
}

createRoot(document.getElementById('root')).render(<App />);
