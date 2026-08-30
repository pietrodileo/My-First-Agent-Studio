import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import './style.css';

const markdownComponents = {
  table: ({ children }) => <div className="table-scroll"><table>{children}</table></div>,
};

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
  const [text, setText] = useState('');
  const [stats, setStats] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [agentDetailsOpen, setAgentDetailsOpen] = useState(true);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(
    () => window.localStorage.getItem('agent-studio-sidebar') === 'collapsed',
  );
  const chatRef = useRef(null);
  const selected = agents.find((item) => item.className === agent);
  const provider = providers[0];

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
    setAgent(value);
    setConversation('');
    setMessages([]);
    setActiveSkills([]);
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
    }
  }

  async function deleteConversation(id) {
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
    if (!text.trim() || busy) return;

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
        { role: 'assistant', content: data.content },
      ]);
      setActiveSkills(data.activeSkills || activeSkills);
      setStats(data.stats);
      await refreshHistory();
    } catch (requestError) {
      setError(requestError.message);
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

  function toggleSkill(skill) {
    if (busy) return;
    setActiveSkills((items) => items.includes(skill)
      ? items.filter((item) => item !== skill)
      : [...items, skill]);
  }

  return (
    <main className={`app-shell${sidebarCollapsed ? ' sidebar-collapsed' : ''}`}>
      <aside className="sidebar">
        <div className="brand"><button className="brand-toggle" onClick={() => setSidebarCollapsed((collapsed) => !collapsed)} aria-label={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'} title={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}><span className="brand-mark">✦</span></button><div><small>INTERSYSTEMS AI HUB</small><strong>Agent Studio</strong></div></div>
        <button className="new-chat" onClick={() => choose(agent)} title="New chat"><span>＋</span><span className="new-chat-label">New chat</span></button>
        <section className="history-section">
          <div className="history-heading"><p className="eyebrow">Recent chats</p><span>{history.length}</span></div>
          <div className="history-list">
            {!history.length && <p className="history-empty">Your conversations will appear here.</p>}
            {history.map((item) => (
              <div className={`history-row${conversation === item.conversationId ? ' active' : ''}`} key={item.conversationId}>
                <button className="history-item" onClick={() => openConversation(item.conversationId)}>
                  <span className="history-icon">◌</span>
                  <span className="history-copy"><strong>{item.title}</strong><small>{item.agentClass}</small></span>
                </button>
                <button className="history-delete" title="Delete chat" onClick={() => deleteConversation(item.conversationId)}>×</button>
              </div>
            ))}
          </div>
        </section>
        <div className="sidebar-section">
          <p className="eyebrow">Configuration</p>
          <label>Agent<select value={agent} onChange={(event) => choose(event.target.value)}>{agents.map((item) => <option key={item.className}>{item.className}</option>)}</select></label>
          <label>Provider<div className="provider-field"><span className="status-dot" />{provider?.name || 'Loading…'}</div></label>
          <label>Model<select value={model} onChange={(event) => setModel(event.target.value)} disabled={!provider?.models?.length}>{!provider?.models?.length && <option value="">No models available</option>}{provider?.models?.map((item) => <option key={item}>{item}</option>)}</select></label>
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
              <div className="capability-group toolsets">
                <div className="capability-heading"><span>Toolsets</span><b>{selected.toolSets.length}</b></div>
                <ul>{selected.toolSets.length ? selected.toolSets.map((item) => <li key={item}><span className="capability-icon">⌘</span><span>{item}</span></li>) : <li className="empty">None</li>}</ul>
              </div>
              <div className="capability-group skills">
                <div className="capability-heading"><span>Skills</span><b>{selected.skills.length}</b></div>
                <ul>{selected.skills.length ? selected.skills.map((item) => <li className={activeSkills.includes(item) ? 'active' : ''} key={item}><button type="button" aria-pressed={activeSkills.includes(item)} disabled={busy} onClick={() => toggleSkill(item)}><span className="capability-icon">✦</span><span>{item}</span><span className="skill-state">{activeSkills.includes(item) ? 'On' : 'Off'}</span></button></li>) : <li className="empty">None</li>}</ul>
              </div>
            </div>}
          </div>
        )}
        <div className="sidebar-footer"><span className="status-dot" /> Ollama connected</div>
      </aside>
      <section className="workspace">
        <header className="topbar"><div><span className="mobile-brand">Agent Studio</span><strong>{selected?.className || 'Choose an agent'}</strong><span className="model-pill">{model || 'Default model'}</span></div><button className="icon-button" title="New chat" onClick={() => choose(agent)}>＋</button></header>
        <section className="chat" ref={chatRef}>
          {!messages.length && <div className="welcome"><div className="welcome-icon">✦</div><h1>How can I help?</h1><p>Chat with <strong>{selected?.className || 'an agent'}</strong>, powered by {provider?.name || 'your provider'}.</p>{selected?.examplePrompt && <button className="suggestion" onClick={() => setText(selected.examplePrompt)}>{selected.examplePrompt}<span>→</span></button>}</div>}
          <div className="message-list">{messages.map((message, index) => <article className={message.role} key={`${message.role}-${index}`}><div className="avatar">{message.role === 'user' ? 'Y' : '✦'}</div><div className="message-content"><b>{message.role === 'user' ? 'You' : selected?.className}</b><ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>{message.content}</ReactMarkdown></div></article>)}{busy && <div className="working"><span /><span /><span /> Agent is thinking</div>}</div>
        </section>
        <div className="composer-wrap">
          {error && <div className="error">{error}</div>}
          <form onSubmit={send} className="composer"><textarea value={text} onChange={(event) => setText(event.target.value)} onKeyDown={handleComposerKeyDown} placeholder={`Message ${selected?.className || 'agent'}`} rows="1" /><button className="send-button" disabled={busy || !agent || !text.trim()} title="Send message">↑</button></form>
          <div className="composer-meta"><span><kbd>Enter</kbd> send · <kbd>Shift</kbd> + <kbd>Enter</kbd> new line</span>{stats && <span>{stats.total_prompt_tokens || 0} prompt · {stats.total_completion_tokens || 0} completion · {stats.total_tool_calls || 0} tools</span>}</div>
        </div>
      </section>
    </main>
  );
}

createRoot(document.getElementById('root')).render(<App />);
