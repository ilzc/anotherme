// Simulated delay to mimic real API calls
const delay = (ms = 300) => new Promise(r => setTimeout(r, ms))

// ─── Dashboard ───────────────────────────────────────────

export async function GetDashboardStats() {
  await delay(200)
  return {
    totalActivities: 1247,
    todayActivities: 23,
    totalMemories: 156,
    captureRunning: true,
    todayCaptureCount: 23,
    lastCaptureTime: new Date().toISOString()
  }
}

export async function GetTodayActivities(limit) {
  await delay(300)
  const apps = ['VS Code', 'Chrome', 'WeChat', 'Terminal', 'Figma', 'Notion']
  const titles = [
    'Writing Vue component code',
    'Searching Tailwind CSS documentation',
    'Discussing project progress with colleagues',
    'Running npm build scripts',
    'Designing user interface prototypes',
    'Organizing project notes'
  ]
  const summaries = [
    'User is writing Vue 3 components using Composition API and TypeScript',
    'User is browsing the official Tailwind CSS documentation, looking up Flexbox layout classes',
    'User is discussing feature requirements and scheduling with team members on WeChat',
    'User is running build and test commands in the terminal',
    'User is adjusting button and card visual styles in Figma',
    'User is recording meeting notes and to-do items in Notion'
  ]
  const categories = ['work', 'learning', 'social', 'work', 'creative', 'work']
  const engagements = ['deep_focus', 'active_work', 'browsing', 'active_work', 'deep_focus', 'browsing']
  const topicSets = [
    ['TypeScript', 'Vue.js', 'Composition API'],
    ['CSS', 'Tailwind', 'Frontend Development'],
    ['Project Management', 'Team Collaboration'],
    ['Node.js', 'npm', 'Build Tools'],
    ['UI Design', 'Interaction Design'],
    ['Notes', 'Knowledge Management']
  ]

  return Array.from({ length: Math.min(limit || 10, 10) }, (_, i) => ({
    id: `act-${i}`,
    timestamp: new Date(Date.now() - i * 3600000).toISOString(),
    appName: apps[i % apps.length],
    windowTitle: titles[i % titles.length],
    contentSummary: summaries[i % summaries.length],
    activityCategory: categories[i % categories.length],
    topics: topicSets[i % topicSets.length],
    engagementLevel: engagements[i % engagements.length]
  }))
}

// ─── Capture Control ─────────────────────────────────────

let _captureRunning = true
let _captureCount = 23

export async function StartCapture() {
  await delay(500)
  _captureRunning = true
  return { success: true }
}

export async function StopCapture() {
  await delay(500)
  _captureRunning = false
  return { success: true }
}

export async function GetCaptureStatus() {
  await delay(100)
  return {
    running: _captureRunning,
    count: _captureCount,
    lastTime: new Date().toISOString()
  }
}

// ─── Chat ────────────────────────────────────────────────

let _sessions = [
  { id: 'sess-1', title: 'Discussion on Work Efficiency', createdAt: '2026-03-12T09:00:00Z', lastMessageAt: '2026-03-12T10:30:00Z' },
  { id: 'sess-2', title: 'Creating a Study Plan', createdAt: '2026-03-11T14:00:00Z', lastMessageAt: '2026-03-11T16:00:00Z' },
  { id: 'sess-3', title: 'Daily Mood Journal', createdAt: '2026-03-10T20:00:00Z', lastMessageAt: '2026-03-10T21:00:00Z' }
]

let _messages = {
  'sess-1': [
    { id: 'msg-1', role: 'user', content: 'How do you think my work efficiency was today?', timestamp: '2026-03-12T09:00:00Z' },
    { id: 'msg-2', role: 'assistant', content: 'Based on today\'s screen capture data, you mainly focused on coding in VS Code, with about 3.5 hours of deep focus time, which is quite good. There was a period of browsing documentation, which is a normal part of the workflow. I suggest trying the Pomodoro technique to further optimize your focus time allocation.', timestamp: '2026-03-12T09:01:00Z' },
    { id: 'msg-3', role: 'user', content: 'Is there anything I can improve on?', timestamp: '2026-03-12T10:00:00Z' },
    { id: 'msg-4', role: 'assistant', content: 'Looking at your behavior patterns, there are a few areas for optimization:\n\n1. **Context switching frequency**: You switched between VS Code and Chrome about 15 times. Try batching your documentation lookup before focused coding sessions\n2. **Social media interruptions**: WeChat messages disrupted your coding flow between 2-3 PM. Consider setting a Do Not Disturb period\n3. **Break rhythm**: You coded continuously for over 2 hours without breaks. Taking appropriate breaks helps maintain efficiency\n\nOverall, your work pattern is healthy and just needs minor adjustments for further improvement.', timestamp: '2026-03-12T10:01:00Z' }
  ],
  'sess-2': [
    { id: 'msg-5', role: 'user', content: 'Help me create a plan for learning Rust', timestamp: '2026-03-11T14:00:00Z' },
    { id: 'msg-6', role: 'assistant', content: 'Based on your learning habits and current tech stack, here\'s a Rust learning plan:\n\n**Weeks 1-2: Basic Syntax**\n- Ownership system and borrow checker\n- Basic data types and control flow\n- Structs and enums\n\n**Weeks 3-4: Advanced Concepts**\n- Generics and traits\n- Error handling\n- Collections and iterators\n\n**Weeks 5-6: Hands-on Projects**\n- Build a CLI tool in Rust\n- Create a small project in a domain you\'re familiar with\n\nBased on your screen capture data, you have a consistent study window from 8-10 PM each evening. I recommend using this time slot.', timestamp: '2026-03-11T14:01:00Z' }
  ],
  'sess-3': [
    { id: 'msg-7', role: 'user', content: 'Feeling a bit tired today', timestamp: '2026-03-10T20:00:00Z' },
    { id: 'msg-8', role: 'assistant', content: 'Looking at today\'s activity data, you did have quite a busy day. You worked continuously for 4 hours in the morning and had a long meeting in the afternoon. Some fatigue is perfectly normal.\n\nI suggest tonight you could:\n- Do some relaxing activities to unwind\n- Get to bed early and ensure adequate sleep\n- Adjust your work pace tomorrow as needed\n\nRemember, sustained high-intensity work doesn\'t necessarily improve efficiency. Proper rest is equally important.', timestamp: '2026-03-10T20:01:00Z' }
  ]
}

let _nextSessionId = 4
let _nextMsgId = 9

export async function GetChatSessions() {
  await delay(200)
  return [..._sessions]
}

export async function CreateChatSession() {
  await delay(200)
  const session = {
    id: `sess-${_nextSessionId++}`,
    title: 'New Chat',
    createdAt: new Date().toISOString(),
    lastMessageAt: new Date().toISOString()
  }
  _sessions.unshift(session)
  _messages[session.id] = []
  return session
}

export async function GetChatMessages(sessionId) {
  await delay(200)
  return _messages[sessionId] || []
}

export async function SendChatMessageStream(sessionId, content) {
  await delay(100)
  const userMsg = {
    id: `msg-${_nextMsgId++}`,
    role: 'user',
    content,
    timestamp: new Date().toISOString()
  }
  if (!_messages[sessionId]) _messages[sessionId] = []
  _messages[sessionId].push(userMsg)

  // Simulate streaming delay
  await delay(1500)
  const aiContent = `This is a streaming reply to "${content}". As your digital twin, I'm thinking about this...\n\nBased on your behavioral data and memories, I believe this is a topic worth exploring in depth. When facing similar questions, you typically tend to start with structured analysis, then gradually refine your approach.`
  const msgId = `msg-${_nextMsgId++}`
  const aiMsg = {
    id: msgId,
    role: 'assistant',
    content: aiContent,
    timestamp: new Date().toISOString()
  }
  _messages[sessionId].push(aiMsg)

  return {
    sessionId,
    messageId: msgId,
    content: aiContent
  }
}

export async function SendChatMessage(sessionId, content) {
  await delay(100)
  const userMsg = {
    id: `msg-${_nextMsgId++}`,
    role: 'user',
    content,
    timestamp: new Date().toISOString()
  }
  if (!_messages[sessionId]) _messages[sessionId] = []
  _messages[sessionId].push(userMsg)

  // Simulate AI response with delay
  await delay(1500)
  const responses = [
    'That\'s a great question. Based on what I know about you, let me analyze this...\n\nFrom your recent behavioral data, you have a fairly stable pattern in this area. I\'ve noticed that your efficiency tends to peak in the afternoon, and you prefer using structured approaches to solve problems.\n\nIf you need a more detailed analysis, I can look up relevant data from your memory bank.',
    'I understand your thoughts. Based on your cognitive style, you tend to start with an overall plan and then refine the details. This is a very effective approach.\n\nMy suggestions are:\n1. First determine the core objective\n2. Break tasks into manageable small steps\n3. Set clear milestones\n\nWould you like me to help you refine this further?',
    'Based on your screen capture records, this has indeed been a key focus area for you recently. You\'ve already accumulated considerable knowledge in this field, including documentation reading and coding practice.\n\nBased on your learning style, I suggest consolidating this knowledge through hands-on projects, which is typically your most effective learning method.'
  ]
  const aiMsg = {
    id: `msg-${_nextMsgId++}`,
    role: 'assistant',
    content: responses[Math.floor(Math.random() * responses.length)],
    timestamp: new Date().toISOString()
  }
  _messages[sessionId].push(aiMsg)
  return aiMsg
}

// ─── Personality ─────────────────────────────────────────

export async function GetPersonalityLayer(layerNum) {
  await delay(400)
  const layers = {
    1: [ // Behavioral Rhythm
      { dimension: 'Daily Routine', value: 78, confidence: 85, description: 'Usually active 9:00-18:00 on weekdays, with a study session from 20:00-23:00', evidenceCount: 234 },
      { dimension: 'Focus Mode', value: 82, confidence: 90, description: 'Prefers long deep focus sessions, average focus duration 45 minutes', evidenceCount: 189 },
      { dimension: 'Switching Frequency', value: 45, confidence: 75, description: 'Moderate context switching, averaging about 30 app switches per day', evidenceCount: 156 },
      { dimension: 'Break Rhythm', value: 35, confidence: 60, description: 'Tends toward long intervals between breaks, sometimes working over 2 hours continuously', evidenceCount: 98 },
      { dimension: 'Peak Hours', value: 88, confidence: 92, description: 'Peak efficiency during 10:00 AM - 12:00 PM and 2:00 - 4:00 PM', evidenceCount: 267 }
    ],
    2: [ // Knowledge Map
      { dimension: 'Frontend Development', value: 92, confidence: 95, description: 'Deep user of Vue.js, React, and TypeScript', evidenceCount: 456 },
      { dimension: 'Backend Technology', value: 68, confidence: 80, description: 'Familiar with Go and Node.js, regularly uses REST APIs', evidenceCount: 178 },
      { dimension: 'System Design', value: 71, confidence: 70, description: 'Interested in architecture design and system scalability', evidenceCount: 89 },
      { dimension: 'AI/ML', value: 55, confidence: 65, description: 'Strong interest in LLM applications and prompt engineering', evidenceCount: 67 },
      { dimension: 'Tool Proficiency', value: 85, confidence: 88, description: 'Proficient with development toolchains, prefers keyboard-driven workflows', evidenceCount: 312 }
    ],
    3: [ // Cognitive Style
      { dimension: 'Analytical Tendency', value: 80, confidence: 82, description: 'Prefers structured analysis, skilled at breaking down complex problems', evidenceCount: 145 },
      { dimension: 'Learning Mode', value: 75, confidence: 78, description: 'Practice-oriented learner, driven by project-based learning', evidenceCount: 123 },
      { dimension: 'Decision Style', value: 65, confidence: 70, description: 'Tends to gather thorough information before deciding, occasionally over-analyzes', evidenceCount: 87 },
      { dimension: 'Innovation', value: 72, confidence: 68, description: 'Seeks innovation within existing frameworks, balancing stability with change', evidenceCount: 76 },
      { dimension: 'Systems Thinking', value: 83, confidence: 85, description: 'Skilled at understanding problems from a holistic perspective, focusing on interconnections', evidenceCount: 134 }
    ],
    4: [ // Expression Style
      { dimension: 'Conciseness', value: 78, confidence: 80, description: 'Tends toward concise expression, gets to the point with little redundancy', evidenceCount: 98 },
      { dimension: 'Technical Jargon', value: 85, confidence: 88, description: 'Comfortable using professional terminology, writes well-structured code comments', evidenceCount: 167 },
      { dimension: 'Bilingual Usage', value: 70, confidence: 82, description: 'Frequently mixes Chinese and English in technical discussions', evidenceCount: 145 },
      { dimension: 'Communication Frequency', value: 55, confidence: 65, description: 'Prefers asynchronous communication, avoids unnecessary real-time conversations', evidenceCount: 78 },
      { dimension: 'Emotional Expression', value: 40, confidence: 55, description: 'Relatively restrained emotional expression in work contexts', evidenceCount: 56 }
    ],
    5: [ // Values
      { dimension: 'Efficiency First', value: 88, confidence: 85, description: 'Highly values work efficiency and time management', evidenceCount: 198 },
      { dimension: 'Quality Awareness', value: 82, confidence: 80, description: 'Pursues code quality and user experience', evidenceCount: 156 },
      { dimension: 'Continuous Learning', value: 90, confidence: 92, description: 'Maintains strong learning motivation and curiosity', evidenceCount: 234 },
      { dimension: 'Independence', value: 75, confidence: 72, description: 'Prefers independent thinking and problem-solving', evidenceCount: 112 },
      { dimension: 'Work-Life Balance', value: 50, confidence: 58, description: 'High work engagement, room for improvement in work-life balance', evidenceCount: 67 }
    ]
  }
  return layers[layerNum] || []
}

export async function GetAllPersonalityLayers() {
  const results = await Promise.all(
    [1, 2, 3, 4, 5].map(i => GetPersonalityLayer(i))
  )
  const layers = {}
  results.forEach((traits, i) => { layers[i + 1] = traits })
  return layers
}

export async function GetPersonalitySnapshot() {
  await delay(300)
  return {
    generatedAt: '2026-03-12T08:00:00Z',
    summary: 'You are an efficiency-focused frontend developer with strong systems thinking abilities and a habit of continuous learning. You prefer deep focus mode at work and are skilled at using development tools to boost productivity. In the technical domain, frontend development is your core strength, while you maintain a keen interest in exploring AI applications. Your expression style is concise and direct, and you tend to gather thorough information before making decisions. In terms of values, you highly prioritize efficiency and code quality, but could benefit from better work-life balance.',
    keyTraits: ['Deep Focus', 'Efficiency-Driven', 'Continuous Learner', 'Systems Thinker', 'Concise Communicator'],
    version: 12
  }
}

// ─── Memory ──────────────────────────────────────────────

const _memories = [
  { id: 'mem-1', content: 'User is a frontend development engineer, primarily using Vue.js and TypeScript', category: 'topic', keywords: ['Frontend', 'Vue.js', 'TypeScript'], importance: 95, isPinned: true, createdAt: '2026-03-01T10:00:00Z', updatedAt: '2026-03-12T08:00:00Z', accessCount: 45 },
  { id: 'mem-2', content: 'User prefers handling complex coding tasks during 10 AM - 12 PM', category: 'habit', keywords: ['Work Habits', 'Time Management', 'Coding'], importance: 80, isPinned: false, createdAt: '2026-03-05T14:00:00Z', updatedAt: '2026-03-11T09:00:00Z', accessCount: 23 },
  { id: 'mem-3', content: 'User is learning the Rust programming language, planning to use it for systems-level development', category: 'intent', keywords: ['Rust', 'Study Plan', 'Systems Development'], importance: 70, isPinned: true, createdAt: '2026-03-08T20:00:00Z', updatedAt: '2026-03-10T21:00:00Z', accessCount: 12 },
  { id: 'mem-4', content: 'User believes code readability is more important than performance optimization (in most scenarios)', category: 'opinion', keywords: ['Code Quality', 'Readability', 'Engineering Principles'], importance: 75, isPinned: false, createdAt: '2026-03-03T16:00:00Z', updatedAt: '2026-03-09T11:00:00Z', accessCount: 8 },
  { id: 'mem-5', content: 'User completed the frontend architecture design for the AnotherMe project', category: 'milestone', keywords: ['AnotherMe', 'Project Milestone', 'Architecture Design'], importance: 90, isPinned: true, createdAt: '2026-03-10T18:00:00Z', updatedAt: '2026-03-10T18:00:00Z', accessCount: 5 },
  { id: 'mem-6', content: 'User prefers dark-themed editors and applications', category: 'habit', keywords: ['Preferences', 'Dark Theme', 'UI'], importance: 45, isPinned: false, createdAt: '2026-03-02T09:00:00Z', updatedAt: '2026-03-08T14:00:00Z', accessCount: 15 },
  { id: 'mem-7', content: 'User has a positive attitude toward AI-assisted programming tools (e.g., GitHub Copilot)', category: 'opinion', keywords: ['AI', 'Programming Tools', 'Copilot'], importance: 65, isPinned: false, createdAt: '2026-03-06T11:00:00Z', updatedAt: '2026-03-11T10:00:00Z', accessCount: 9 },
  { id: 'mem-8', content: 'User follows technical articles and videos on web performance optimization', category: 'topic', keywords: ['Performance Optimization', 'Web', 'Technical Learning'], importance: 60, isPinned: false, createdAt: '2026-03-04T15:00:00Z', updatedAt: '2026-03-07T16:00:00Z', accessCount: 18 },
  { id: 'mem-9', content: 'User plans to start learning system design in the next quarter', category: 'intent', keywords: ['System Design', 'Study Plan', 'Career Development'], importance: 55, isPinned: false, createdAt: '2026-03-09T13:00:00Z', updatedAt: '2026-03-09T13:00:00Z', accessCount: 3 },
  { id: 'mem-10', content: 'User spends 30-60 minutes reading technical blogs after work each day', category: 'habit', keywords: ['Reading Habits', 'Tech Blogs', 'Self-improvement'], importance: 50, isPinned: false, createdAt: '2026-03-07T21:00:00Z', updatedAt: '2026-03-11T22:00:00Z', accessCount: 20 }
]

export async function GetMemories(options = {}) {
  await delay(400)
  let result = [..._memories]

  // Filter by category
  if (options.category && options.category !== 'all') {
    result = result.filter(m => m.category === options.category)
  }

  // Filter by keyword search
  if (options.keyword) {
    const kw = options.keyword.toLowerCase()
    result = result.filter(m =>
      m.content.toLowerCase().includes(kw) ||
      m.keywords.some(k => k.toLowerCase().includes(kw))
    )
  }

  // Sort
  if (options.sortBy === 'importance') {
    result.sort((a, b) => b.importance - a.importance)
  } else if (options.sortBy === 'recency') {
    result.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt))
  } else {
    result.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
  }

  return result
}

export async function GetMemoryStats() {
  await delay(100)
  return {
    total: _memories.length,
    pinned: _memories.filter(m => m.isPinned).length,
    byCategory: {
      topic: _memories.filter(m => m.category === 'topic').length,
      intent: _memories.filter(m => m.category === 'intent').length,
      habit: _memories.filter(m => m.category === 'habit').length,
      opinion: _memories.filter(m => m.category === 'opinion').length,
      milestone: _memories.filter(m => m.category === 'milestone').length
    }
  }
}

// ─── Settings ────────────────────────────────────────────

let _settings = {
  language: '',
  ai: {
    providerName: 'OpenAI',
    endpoint: 'https://api.openai.com/v1',
    apiKey: 'sk-xxxxxxxxxxxxxxxx',
    modelName: 'gpt-4o'
  },
  capture: {
    mode: 'smart',
    intervalSeconds: 300,
    dailyLimit: 200
  },
  blacklist: ['WeChat.exe', 'QQ.exe', '1Password.exe', 'KeePass.exe']
}

export async function GetSettings() {
  await delay(200)
  return JSON.parse(JSON.stringify(_settings))
}

export async function SaveSettings(settings) {
  await delay(400)
  _settings = JSON.parse(JSON.stringify(settings))
  return { success: true }
}

export async function TestAIConnection(endpoint, apiKey, model) {
  await delay(1500)
  // Simulate 80% success rate
  if (Math.random() > 0.2) {
    return { success: true, message: 'Connection successful, model responding normally' }
  }
  return { success: false, message: 'Connection failed: please check your API Key and endpoint URL' }
}

export async function AddBlacklistItem(processName) {
  await delay(200)
  if (!_settings.blacklist.includes(processName)) {
    _settings.blacklist.push(processName)
  }
  return { success: true }
}

export async function RemoveBlacklistItem(processName) {
  await delay(200)
  _settings.blacklist = _settings.blacklist.filter(p => p !== processName)
  return { success: true }
}

export async function ExportPersonality(format) {
  await delay(1000)
  return {
    success: true,
    filePath: `C:\\Users\\User\\Documents\\AnotherMe\\personality_export_${Date.now()}.${format === 'json' ? 'json' : 'txt'}`,
    message: `Personality data exported in ${format} format`
  }
}

export async function GetDataStats() {
  await delay(200)
  return {
    dbPath: 'C:\\Users\\User\\AppData\\Local\\AnotherMe\\data.db',
    dbSize: '45.2 MB',
    activitiesCount: 1247,
    memoriesCount: 156,
    personalityVersion: 12,
    oldestRecord: '2026-01-15T08:00:00Z'
  }
}
