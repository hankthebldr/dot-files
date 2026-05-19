# Cortex DC Demo Application - Testing Guide

## 🎯 Purpose

This guide provides step-by-step instructions for evaluating the demo application at **henryreedai.web.app** to assess current functionality against the target architecture and identify gaps.

---

## 🔐 Pre-Testing Setup

### 1. Test Accounts Setup

You'll need accounts with different roles:

```
User Role: DC (Domain Consultant)
- Email: dc@test.cortex.com
- Test creating TRRs, POVs, projects

Manager Role: Team Lead
- Email: manager@test.cortex.com  
- Test approval workflows, team oversight

Admin Role: Platform Admin
- Email: admin@test.cortex.com
- Test user management, system config
```

### 2. Browser Setup

**Recommended:** Chrome or Firefox with DevTools open

**Extensions to Install:**
- React Developer Tools
- Redux DevTools (if using Redux)
- Lighthouse for performance auditing

**Console Setup:**
```javascript
// Enable verbose logging
localStorage.setItem('DEBUG', '*');

// Track network requests
let apiCalls = [];
const originalFetch = window.fetch;
window.fetch = function(...args) {
  apiCalls.push({ url: args[0], time: Date.now() });
  return originalFetch.apply(this, args);
};

// Monitor WebSocket connections
let wsConnections = [];
const originalWS = window.WebSocket;
window.WebSocket = function(...args) {
  wsConnections.push({ url: args[0], time: Date.now() });
  return new originalWS(...args);
};
```

### 3. Testing Tools

**Network Tab:**
- Filter by: XHR, WS, Fetch
- Preserve log enabled
- Disable cache

**Performance Tab:**
- Ready to record
- Screenshots enabled

**Application Tab:**
- Check Local Storage
- Check Session Storage
- Check IndexedDB

---

## 🧪 Test Suite 1: Authentication & Authorization

### Test 1.1: Login Flow

**Steps:**
1. Navigate to https://henryreedai.web.app
2. Observe initial 