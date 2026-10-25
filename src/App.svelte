<script>
  import { onMount, tick } from 'svelte';
  import { createSupabaseClient } from './lib/supabase.js';

  const storageKey = 'daylist-tasks-v1';
  const noteColors = ['yellow', 'mint', 'rose', 'peach', 'sky', 'lilac'];
  const workspaceThemes = [
    { id: 'sage', name: 'Sage', preview: '#78967b' },
    { id: 'ocean', name: 'Ocean', preview: '#6489ad' },
    { id: 'lavender', name: 'Lavender', preview: '#8a78ad' },
    { id: 'coral', name: 'Coral', preview: '#c77c6d' },
    { id: 'amber', name: 'Amber', preview: '#b08a46' },
  ];
  const themeStorageKey = 'daylist-workspace-theme-v1';
  const weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
  const hours = Array.from({ length: 12 }, (_, index) => String(index + 1).padStart(2, '0'));
  const minutes = Array.from({ length: 60 }, (_, index) => String(index).padStart(2, '0'));
  let tasks = $state([]);
  let filter = $state('wall');
  let viewMode = $state('board');
  let activeProject = $state('All tasks');
  let modalStatus = $state('todo');
  let modalPriority = $state('Medium');
  let sortOpen = $state(false);
  let sortMode = $state('recent');
  let searchQuery = $state('');
  let theme = $state('sage');
  let themePickerOpen = $state(false);
  let modalOpen = $state(false);
  let modalTitle = $state('');
  let modalNotes = $state('');
  let modalDue = $state('');
  let modalColor = $state('yellow');
  let datePickerOpen = $state(false);
  let calendarMonth = $state(new Date(new Date().getFullYear(), new Date().getMonth(), 1));
  let timeHour = $state('09');
  let timeMinute = $state('00');
  let timePeriod = $state('AM');
  let editingTaskId = $state(null);
  let titleInput = $state(null);
  let paperDialog = $state(null);
  let modalReturnFocus = $state(null);
  let ready = $state(false);
  let reminderPermission = $state('unsupported');
  let reminderQueue = $state([]);
  let currentTime = $state(Date.now());
  let cloudStatus = $state('local');
  let cloudError = $state('');
  let cloudClient = null;
  let cloudUserId = null;
  let cloudReady = false;
  let syncRunning = false;
  let syncRequested = false;
  let syncTimer;

  onMount(() => {
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey) || '[]');
      if (Array.isArray(saved)) {
        tasks = saved.filter((task) => task && typeof task.id === 'string' && typeof task.title === 'string')
          .map((task) => ({
            id: task.id,
            title: task.title,
            done: Boolean(task.done),
            createdAt: Number(task.createdAt) || Date.now(),
            dueAt: typeof task.dueAt === 'string' && Number.isFinite(new Date(task.dueAt).getTime()) ? task.dueAt : '',
            reminded: Boolean(task.reminded),
            notes: typeof task.notes === 'string' ? task.notes : '',
            color: noteColors.includes(task.color) ? task.color : '',
            status: ['todo', 'progress', 'revision', 'done'].includes(task.status) ? task.status : (task.done ? 'done' : 'todo'),
            priority: ['Low', 'Medium', 'High'].includes(task.priority) ? task.priority : 'Medium',
            project: typeof task.project === 'string' ? task.project : 'Nova UI Revamp',
          }));
      }
    } catch {
      tasks = [];
    }
    try {
      const savedTheme = localStorage.getItem(themeStorageKey);
      if (workspaceThemes.some((option) => option.id === savedTheme)) theme = savedTheme;
    } catch { /* Theme preferences may be unavailable in private browsing. */ }
    if ('Notification' in window) reminderPermission = Notification.permission;
    ready = true;
    checkReminders();
    initializeCloud();
    const timer = window.setInterval(() => {
      currentTime = Date.now();
      checkReminders();
    }, 15000);
    return () => { window.clearInterval(timer); window.clearTimeout(syncTimer); };
  });

  $effect(() => {
    if (ready) {
      try { localStorage.setItem(storageKey, JSON.stringify(tasks)); } catch { /* Storage may be unavailable. */ }
    }
  });

  $effect(() => {
    tasks;
    if (cloudReady) queueCloudSync();
  });

  $effect(() => {
    if (ready) {
      try { localStorage.setItem(themeStorageKey, theme); } catch { /* Theme preferences may be unavailable. */ }
    }
  });

  let selectedTheme = $derived(workspaceThemes.find((option) => option.id === theme) ?? workspaceThemes[0]);

  let todayLabel = $derived(new Intl.DateTimeFormat('en', { weekday: 'long', month: 'long', day: 'numeric' }).format(new Date()));
  let remaining = $derived(tasks.filter((task) => !task.done).length);
  let completed = $derived(tasks.filter((task) => task.done).length);
  let visibleTasks = $derived(tasks.filter((task) => {
    const matchesFilter = (filter === 'wall' && !task.done)
      || (filter === 'today' && !task.done && !isUpcoming(task) && !isMissed(task))
      || (filter === 'upcoming' && isUpcoming(task))
      || (filter === 'missed' && isMissed(task))
      || (filter === 'completed' && task.done);
    const matchesProject = activeProject === 'All tasks' || task.project === activeProject;
    return matchesFilter && matchesProject && `${task.title} ${task.notes}`.toLowerCase().includes(searchQuery.trim().toLowerCase());
  }).sort((a, b) => sortMode === 'priority' ? ['High', 'Medium', 'Low'].indexOf(a.priority) - ['High', 'Medium', 'Low'].indexOf(b.priority) : b.createdAt - a.createdAt));
  let projects = $derived(['Nova UI Revamp', 'Orion SaaS Platform', 'PixelFrame Website', 'Zetta Landing Page'].map((name) => ({ name, count: tasks.filter((task) => task.project === name && !task.done).length })));
  let columns = [
    { id: 'todo', name: 'To do', color: 'purple' },
    { id: 'progress', name: 'In Progress', color: 'blue' },
    { id: 'revision', name: 'Revision', color: 'orange' },
    { id: 'done', name: 'Done', color: 'green' },
  ];
  let upcomingCount = $derived(tasks.filter(isUpcoming).length);
  let todayCount = $derived(tasks.filter((task) => !task.done && !isUpcoming(task) && !isMissed(task)).length);
  let missedCount = $derived(tasks.filter(isMissed).length);
  let calendarMonthLabel = $derived(new Intl.DateTimeFormat('en', { month: 'long', year: 'numeric' }).format(calendarMonth));
  let calendarDays = $derived(makeCalendarDays(calendarMonth));

  function taskToRow(task) {
    return {
      id: task.id,
      owner_id: cloudUserId,
      title: task.title,
      notes: task.notes || '',
      done: Boolean(task.done),
      status: task.status || (task.done ? 'done' : 'todo'),
      priority: task.priority || 'Medium',
      project: task.project || 'Nova UI Revamp',
      due_at: task.dueAt || null,
      reminded: Boolean(task.reminded),
      color: task.color || null,
      created_at: new Date(task.createdAt || Date.now()).toISOString(),
    };
  }

  function rowToTask(row) {
    return {
      id: row.id,
      title: row.title,
      notes: row.notes || '',
      done: Boolean(row.done),
      status: row.status || (row.done ? 'done' : 'todo'),
      priority: row.priority || 'Medium',
      project: row.project || 'Nova UI Revamp',
      dueAt: row.due_at || '',
      reminded: Boolean(row.reminded),
      color: noteColors.includes(row.color) ? row.color : '',
      createdAt: Number.isFinite(new Date(row.created_at).getTime()) ? new Date(row.created_at).getTime() : Date.now(),
    };
  }

  async function initializeCloud() {
    const setup = createSupabaseClient();
    if (!setup.client) {
      cloudStatus = setup.error ? 'error' : 'local';
      cloudError = setup.error || '';
      return;
    }
    cloudClient = setup.client;
    cloudStatus = 'connecting';
    try {
      const { data: sessionData, error: sessionError } = await cloudClient.auth.getSession();
      if (sessionError) throw sessionError;
      let session = sessionData.session;
      if (!session) {
        const { data, error } = await cloudClient.auth.signInAnonymously();
        if (error) throw error;
        session = data.session;
      }
      if (!session?.user?.id) throw new Error('Supabase did not return an authenticated user.');
      cloudUserId = session.user.id;

      const { data: remoteRows, error: queryError } = await cloudClient.from('lexterbeat_tasks').select('*').order('created_at', { ascending: false });
      if (queryError) throw queryError;
      const migrationKey = `daylist-supabase-import-v1:${cloudUserId}`;
      let mergedRows = remoteRows || [];
      if (!localStorage.getItem(migrationKey)) {
        const remoteIds = new Set(mergedRows.map((row) => row.id));
        const localOnlyRows = tasks.filter((task) => !remoteIds.has(task.id)).map(taskToRow);
        if (localOnlyRows.length) {
          const { error: importError } = await cloudClient.from('lexterbeat_tasks').upsert(localOnlyRows, { onConflict: 'id' });
          if (importError) throw importError;
          mergedRows = [...mergedRows, ...localOnlyRows];
        }
        localStorage.setItem(migrationKey, 'done');
      }
      tasks = mergedRows.map(rowToTask);
      cloudReady = true;
      cloudStatus = 'synced';
      cloudError = '';
    } catch (error) {
      cloudStatus = 'error';
      cloudError = error?.message || 'Could not connect to Supabase.';
      console.error('Supabase connection failed:', cloudError);
    }
  }

  function queueCloudSync() {
    syncRequested = true;
    window.clearTimeout(syncTimer);
    syncTimer = window.setTimeout(runCloudSync, 400);
  }

  async function runCloudSync() {
    if (syncRunning || !cloudClient || !cloudUserId || !cloudReady) return;
    syncRunning = true;
    try {
      while (syncRequested) {
        syncRequested = false;
        const snapshot = tasks.map((task) => ({ ...task }));
        const rows = snapshot.map(taskToRow);
        if (rows.length) {
          const { error: saveError } = await cloudClient.from('lexterbeat_tasks').upsert(rows, { onConflict: 'id' });
          if (saveError) throw saveError;
          const keepIds = rows.map((row) => row.id).join(',');
          const deletion = cloudClient.from('lexterbeat_tasks').delete().eq('owner_id', cloudUserId);
          const { error: deleteError } = rows.length
            ? await deletion.not('id', 'in', `(${keepIds})`)
            : await deletion;
          if (deleteError) throw deleteError;
        } else {
          const { error: deleteError } = await cloudClient.from('lexterbeat_tasks').delete().eq('owner_id', cloudUserId);
          if (deleteError) throw deleteError;
        }
        cloudStatus = 'synced';
        cloudError = '';
      }
    } catch (error) {
      cloudStatus = 'error';
      cloudError = error?.message || 'Cloud sync failed. Your tasks remain saved on this device.';
      console.error('Supabase sync failed:', cloudError);
    } finally {
      syncRunning = false;
      if (syncRequested) queueCloudSync();
    }
  }

  function saveNote(event) {
    event.preventDefault();
    const title = modalTitle.trim();
    if (!title) return;
    if (editingTaskId) {
      tasks = tasks.map((task) => task.id === editingTaskId
      ? { ...task, title, notes: modalNotes, dueAt: modalDue, color: modalColor, status: modalStatus, done: modalStatus === 'done', priority: modalPriority, reminded: task.dueAt === modalDue ? task.reminded : false }
        : task);
    } else {
      tasks = [{ id: crypto.randomUUID(), title, done: modalStatus === 'done', status: modalStatus, priority: modalPriority, project: activeProject === 'All tasks' ? 'Nova UI Revamp' : activeProject, createdAt: Date.now(), dueAt: modalDue, reminded: false, notes: modalNotes, color: modalColor }, ...tasks];
    }
    filter = 'wall';
    closeEditor();
  }

  async function openCreateNote(event) {
    modalReturnFocus = event?.currentTarget;
    editingTaskId = null;
    modalTitle = '';
    modalNotes = '';
    modalDue = '';
    modalColor = 'yellow';
    modalStatus = 'todo';
    modalPriority = 'Medium';
    datePickerOpen = false;
    calendarMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    timeHour = '09';
    timeMinute = '00';
    timePeriod = 'AM';
    modalOpen = true;
    await tick();
    if (paperDialog && !paperDialog.open) paperDialog.showModal();
    titleInput?.focus();
  }

  async function openEditNote(task, event) {
    modalReturnFocus = event?.currentTarget;
    editingTaskId = task.id;
    modalTitle = task.title;
    modalNotes = task.notes;
    modalDue = task.dueAt;
    modalColor = task.color || 'yellow';
    modalStatus = task.status || (task.done ? 'done' : 'todo');
    modalPriority = task.priority || 'Medium';
    datePickerOpen = false;
    const date = task.dueAt ? new Date(task.dueAt) : new Date();
    calendarMonth = new Date(date.getFullYear(), date.getMonth(), 1);
    const hour = date.getHours();
    timeHour = String(hour % 12 || 12).padStart(2, '0');
    timeMinute = String(date.getMinutes()).padStart(2, '0');
    timePeriod = hour >= 12 ? 'PM' : 'AM';
    modalOpen = true;
    await tick();
    if (paperDialog && !paperDialog.open) paperDialog.showModal();
    titleInput?.focus();
  }

  function closeEditor() {
    if (paperDialog?.open) paperDialog.close();
    modalOpen = false;
    datePickerOpen = false;
    editingTaskId = null;
    requestAnimationFrame(() => modalReturnFocus?.focus());
  }

  function handleWindowKeydown(event) {
    if (modalOpen && event.key === 'Escape') {
      event.preventDefault();
      closeEditor();
    } else if (reminderQueue.length && event.key === 'Escape') {
      event.preventDefault();
      dismissReminder();
    }
  }

  function noteColor(task, index) {
    return task.color || noteColors[index % noteColors.length];
  }

  function localDateString(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  function makeCalendarDays(month) {
    const first = new Date(month.getFullYear(), month.getMonth(), 1);
    const start = new Date(month.getFullYear(), month.getMonth(), 1 - first.getDay());
    const selectedDate = modalDue ? modalDue.split('T')[0] : '';
    const today = localDateString(new Date());
    return Array.from({ length: 42 }, (_, index) => {
      const date = new Date(start.getFullYear(), start.getMonth(), start.getDate() + index);
      const value = localDateString(date);
      return { value, day: date.getDate(), inMonth: date.getMonth() === month.getMonth(), selected: value === selectedDate, today: value === today };
    });
  }

  function setCalendarMonth(offset) {
    calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + offset, 1);
  }

  function to24Hour() {
    const hour = Number(timeHour) % 12 + (timePeriod === 'PM' ? 12 : 0);
    return String(hour).padStart(2, '0');
  }

  function setPickerDate(value) {
    modalDue = `${value}T${to24Hour()}:${timeMinute}`;
    const date = new Date(`${value}T12:00`);
    calendarMonth = new Date(date.getFullYear(), date.getMonth(), 1);
  }

  function updatePickerTime(part, value) {
    if (part === 'hour') timeHour = value;
    if (part === 'minute') timeMinute = value;
    if (part === 'period') timePeriod = value;
    if (modalDue) modalDue = `${modalDue.split('T')[0]}T${to24Hour()}:${timeMinute}`;
  }

  function setQuickDate(offset) {
    const date = new Date();
    date.setDate(date.getDate() + offset);
    setPickerDate(localDateString(date));
  }

  function clearPickerDate() {
    modalDue = '';
  }

  function isUpcoming(task) {
    if (task.done || !task.dueAt) return false;
    const due = new Date(task.dueAt);
    const tomorrow = new Date();
    tomorrow.setHours(24, 0, 0, 0);
    return due.getTime() >= tomorrow.getTime();
  }

  function isMissed(task) {
    if (task.done || !task.dueAt) return false;
    const due = new Date(task.dueAt);
    const gracePeriod = 5 * 60 * 1000;
    return Number.isFinite(due.getTime()) && due.getTime() + gracePeriod <= currentTime;
  }

  function toggleTask(id) {
    tasks = tasks.map((task) => task.id === id ? { ...task, done: !task.done, status: task.done ? 'todo' : 'done' } : task);
  }

  function setTaskStatus(id, status) {
    tasks = tasks.map((task) => task.id === id ? { ...task, status, done: status === 'done' } : task);
  }

  function moveTask(id, direction) {
    const order = columns.map((column) => column.id);
    tasks = tasks.map((task) => {
      if (task.id !== id) return task;
      const index = order.indexOf(task.status || (task.done ? 'done' : 'todo'));
      const next = Math.max(0, Math.min(order.length - 1, index + direction));
      return { ...task, status: order[next], done: order[next] === 'done' };
    });
  }

  function deleteTask(id) {
    tasks = tasks.filter((task) => task.id !== id);
    reminderQueue = reminderQueue.filter((task) => task.id !== id);
    if (editingTaskId === id) closeEditor();
  }

  function dismissReminder() {
    reminderQueue = reminderQueue.slice(1);
  }

  function completeReminder() {
    const current = reminderQueue[0];
    if (!current) return;
    toggleTask(current.id);
    dismissReminder();
  }

  function snoozeReminder() {
    const current = reminderQueue[0];
    if (!current) return;
    const snoozedUntil = new Date(Date.now() + 5 * 60 * 1000).toISOString();
    tasks = tasks.map((task) => task.id === current.id ? { ...task, dueAt: snoozedUntil, reminded: false } : task);
    dismissReminder();
  }

  async function enableReminders() {
    if (!('Notification' in window)) { reminderPermission = 'unsupported'; return; }
    try {
      reminderPermission = await Notification.requestPermission();
      checkReminders();
    } catch {
      reminderPermission = Notification.permission;
    }
  }

  function checkReminders() {
    if (!ready) return;
    const now = Date.now();
    const dueNow = tasks.filter((task) => !task.done && !task.reminded && task.dueAt && Number.isFinite(new Date(task.dueAt).getTime()) && new Date(task.dueAt).getTime() <= now);
    if (!dueNow.length) return;
    const ids = new Set(dueNow.map((task) => task.id));
    tasks = tasks.map((task) => ids.has(task.id) ? { ...task, reminded: true } : task);
    reminderQueue = [...reminderQueue, ...dueNow];
    if (reminderPermission === 'granted' && 'Notification' in window) {
      dueNow.forEach((task) => {
        const notification = new Notification('Task due now', { body: task.title, tag: `daylist-${task.id}` });
        notification.onclick = () => { window.focus(); notification.close(); };
      });
    }
  }

  function formatDue(dueAt) {
    const date = new Date(dueAt);
    return `${new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric' }).format(date)} · ${new Intl.DateTimeFormat('en', { hour: 'numeric', minute: '2-digit' }).format(date)}`;
  }
</script>

<svelte:head>
  <title>LexterBeat To do list</title>
</svelte:head>

<svelte:window onkeydown={handleWindowKeydown} />

<div class="page-backdrop theme-{theme}">
  <div class="app-shell">
    <aside class="sidebar">
      <a class="brand" href="#home" aria-label="LexterBeat To do list home"><span class="brand-mark"><span></span><span></span><span></span></span><span class="brand-name">LexterBeat</span><span class="brand-chevron">⌄</span></a>
      <div class="side-label">MAIN MENU</div>
      <label class="search-box"><span>⌕</span><input aria-label="Search tasks" bind:value={searchQuery} placeholder="Search tasks" /></label>
      <nav class="nav-group" aria-label="Task views">
        <button class="nav-item" class:selected={filter === 'wall'} onclick={() => { filter = 'wall'; activeProject = 'All tasks'; }}><span class="nav-icon">▦</span><span>Dashboard</span></button>
        <button class="nav-item" class:selected={filter === 'wall' && activeProject === 'All tasks'} onclick={() => { filter = 'wall'; activeProject = 'All tasks'; }}><span class="nav-icon">▤</span><span>Tasks</span><span class="nav-count">{remaining}</span></button>
        <button class="nav-item" class:selected={filter === 'upcoming'} onclick={() => filter = 'upcoming'}><span class="nav-icon">▧</span><span>Calendar</span></button>
        <button class="nav-item" class:selected={filter === 'completed'} onclick={() => filter = 'completed'}><span class="nav-icon">♙</span><span>Members</span></button>
        <button class="nav-item" class:selected={filter === 'missed'} onclick={() => filter = 'missed'}><span class="nav-icon">▥</span><span>Reports</span></button>
      </nav>
      <div class="sidebar-section-title"><span>PROJECTS</span><button aria-label="Add project" title="Add project" onclick={openCreateNote}>+</button></div>
      <nav class="project-nav" aria-label="Projects">
        {#each projects as project}<button class="project-link" class:active={activeProject === project.name} onclick={() => { activeProject = project.name; filter = 'wall'; }}><span class="project-folder">▱</span><span>{project.name}</span></button>{/each}
      </nav>
      <div class="sidebar-lower"><div class="side-label">SETTINGS</div>
        <button class="nav-item theme-nav-item" aria-expanded={themePickerOpen} onclick={() => themePickerOpen = !themePickerOpen}><span class="nav-icon">⚙</span><span>Appearance</span><span class="theme-preview" style={`--swatch: ${selectedTheme.preview}`}></span></button>
        {#if themePickerOpen}<div class="theme-picker" role="group" aria-label="Choose workspace theme color"><span class="theme-picker-label">Workspace color</span><div class="theme-swatches">{#each workspaceThemes as option}<button type="button" class="theme-swatch" class:active={theme === option.id} style={`--swatch: ${option.preview}`} aria-label={`Use ${option.name} theme`} onclick={() => theme = option.id}></button>{/each}</div><span class="theme-current">{selectedTheme.name}</span></div>{/if}
      </div>
    </aside>

    <main id="home" class="main-area">
      <header class="topbar"><div class="breadcrumb">Manage and track your tasks seamlessly with clear priorities and progress.</div><div class="top-actions">
        <span class="cloud-status cloud-{cloudStatus}" title={cloudError || (cloudStatus === 'synced' ? 'Your tasks are synced to Supabase' : cloudStatus === 'local' ? 'Tasks are saved in this browser until Supabase is configured' : 'Connecting to Supabase')}><i></i>{cloudStatus === 'synced' ? 'Cloud synced' : cloudStatus === 'connecting' ? 'Connecting…' : cloudStatus === 'error' ? 'Cloud issue' : 'Device storage'}</span>
        {#if reminderPermission === 'default'}<button class="reminder-button" onclick={enableReminders}>♧ Enable reminders</button>{:else if reminderPermission === 'granted'}<span class="reminder-status enabled">♧ <span>Reminders on</span></span>{:else if reminderPermission === 'denied'}<span class="reminder-status">♧ <span>Reminders blocked</span></span>{:else}<span class="reminder-status">♧</span>{/if}
        <span class="manager-chip"><span class="manager-avatar">{new Intl.DateTimeFormat('en',{weekday:'short'}).format(new Date()).slice(0,1)}</span><span>My workspace</span><span>⌄</span></span>
      </div></header>
      <section class="content">
        <div class="board-toolbar"><div class="view-tabs" aria-label="Task view">
          <button class:active={viewMode === 'board'} onclick={() => viewMode = 'board'}>▣ <span>Board</span></button><button class:active={viewMode === 'list'} onclick={() => viewMode = 'list'}>☷ <span>List</span></button><button class:active={viewMode === 'table'} onclick={() => viewMode = 'table'}>▦ <span>Table</span></button><button class:active={viewMode === 'timeline'} onclick={() => viewMode = 'timeline'}>◷ <span>Timeline</span></button>
        </div><div class="board-actions"><button onclick={() => sortOpen = !sortOpen}>☷ <span>Filter</span></button><button onclick={() => sortMode = sortMode === 'recent' ? 'priority' : 'recent'}>↕ <span>Sort</span></button><button onclick={() => viewMode = 'board'}>◇ <span>Group by</span></button><button class="primary-add" aria-label="Add task" onclick={openCreateNote}>+</button></div></div>
        {#if filter !== 'wall'}<div class="filter-summary"><span>{filter === 'today' ? 'Today' : filter === 'upcoming' ? 'Upcoming tasks' : filter === 'missed' ? 'Missed tasks' : 'Completed tasks'}</span><button onclick={() => filter = 'wall'}>Clear filter ×</button></div>{/if}
        {#if sortOpen}<div class="filter-popover"><span>Filter tasks</span><button onclick={() => {filter='wall';sortOpen=false}}>All tasks</button><button onclick={() => {filter='today';sortOpen=false}}>Today</button><button onclick={() => {filter='upcoming';sortOpen=false}}>Upcoming</button><button onclick={() => {filter='completed';sortOpen=false}}>Completed</button><button onclick={() => {filter='missed';sortOpen=false}}>Missed</button></div>{/if}
        {#if viewMode === 'board'}
          <div class="kanban-board">
            {#each columns as column}<section class="board-column" aria-label={`${column.name} tasks`}><header class="column-heading"><div><span class="column-dot {column.color}"></span><h2>{column.name}</h2><span class="column-count">{visibleTasks.filter((task) => (task.status || (task.done ? 'done' : 'todo')) === column.id).length}</span></div><div class="column-controls"><button aria-label={`Add ${column.name} task`} onclick={openCreateNote}>+</button><button aria-label={`${column.name} options`}>···</button></div></header>
              <div class="column-cards">{#each visibleTasks.filter((task) => (task.status || (task.done ? 'done' : 'todo')) === column.id) as task (task.id)}<article class="task-card"><div class="task-card-meta"><span class="priority-badge priority-{task.priority.toLowerCase()}">{task.priority}</span><button class="card-menu" aria-label={`Edit ${task.title}`} onclick={(event) => openEditNote(task,event)}>···</button></div><button class="task-card-title" onclick={(event) => openEditNote(task,event)}>{task.title}</button>{#if task.notes}<p class="task-card-description">{task.notes}</p>{/if}<div class="task-card-footer"><div class="assignees"><span class="assignee assignee-one">{task.title.slice(0,1).toUpperCase()}</span><span class="assignee assignee-two">{task.project.slice(0,1)}</span></div><div class="card-stats">{#if task.dueAt}<span title={formatDue(task.dueAt)}>◷ {new Intl.DateTimeFormat('en',{month:'short',day:'numeric'}).format(new Date(task.dueAt))}</span>{/if}<button aria-label="Mark complete" onclick={() => toggleTask(task.id)}>☐</button><button class="delete-card" aria-label={`Delete ${task.title}`} onclick={() => deleteTask(task.id)}>×</button></div></div><div class="card-move"><span>{task.project}</span><select aria-label={`Move ${task.title}`} value={task.status || (task.done ? 'done' : 'todo')} onchange={(event) => setTaskStatus(task.id,event.currentTarget.value)}>{#each columns as option}<option value={option.id}>{option.name}</option>{/each}</select></div></article>{/each}
                {#if visibleTasks.filter((task) => (task.status || (task.done ? 'done' : 'todo')) === column.id).length === 0}<button class="column-empty" onclick={openCreateNote}>+ Add a task</button>{/if}</div></section>{/each}
          </div>
        {:else if viewMode === 'list'}
          <div class="list-view">{#each visibleTasks as task (task.id)}<div class="list-row"><button class="row-check" class:checked={task.done} aria-label="Toggle complete" onclick={() => toggleTask(task.id)}>{task.done ? '✓' : ''}</button><button class="row-task-title" onclick={(event) => openEditNote(task,event)}>{task.title}<small>{task.notes || task.project}</small></button><span class="priority-badge priority-{task.priority.toLowerCase()}">{task.priority}</span><select aria-label={`Status for ${task.title}`} value={task.status || (task.done ? 'done' : 'todo')} onchange={(event) => setTaskStatus(task.id,event.currentTarget.value)}>{#each columns as column}<option value={column.id}>{column.name}</option>{/each}</select><button class="row-edit" onclick={(event) => openEditNote(task,event)}>Edit</button></div>{/each}<button class="list-add" onclick={openCreateNote}>+ Add a task</button></div>
        {:else if viewMode === 'table'}
          <div class="table-view"><table><thead><tr><th>Task</th><th>Project</th><th>Priority</th><th>Status</th><th>Due date</th></tr></thead><tbody>{#each visibleTasks as task (task.id)}<tr><td><button class="row-task-title" onclick={(event) => openEditNote(task,event)}>{task.title}</button></td><td>{task.project}</td><td><span class="priority-badge priority-{task.priority.toLowerCase()}">{task.priority}</span></td><td><select aria-label={`Status for ${task.title}`} value={task.status || (task.done ? 'done' : 'todo')} onchange={(event) => setTaskStatus(task.id,event.currentTarget.value)}>{#each columns as column}<option value={column.id}>{column.name}</option>{/each}</select></td><td>{task.dueAt ? formatDue(task.dueAt) : '—'}</td></tr>{/each}</tbody></table><button class="list-add" onclick={openCreateNote}>+ Add a task</button></div>
        {:else}
          <div class="timeline-view"><div class="timeline-heading"><h2>Task timeline</h2><span>{visibleTasks.length} tasks</span></div>{#each visibleTasks as task (task.id)}<button class="timeline-row" onclick={(event) => openEditNote(task,event)}><span class="timeline-date">{task.dueAt ? new Intl.DateTimeFormat('en',{month:'short',day:'numeric'}).format(new Date(task.dueAt)) : 'No date'}</span><span class="timeline-track"><i class="column-dot {task.status === 'done' ? 'green' : task.status === 'progress' ? 'blue' : 'purple'}"></i><b>{task.title}</b><small>{task.project}</small></span><span class="priority-badge priority-{task.priority.toLowerCase()}">{task.priority}</span></button>{/each}<button class="list-add" onclick={openCreateNote}>+ Add a task</button></div>
        {/if}
      </section>
    </main>
  </div>
  {#if modalOpen}
    <div class="modal-backdrop">
      <dialog bind:this={paperDialog} class="paper-sheet paper-{modalColor}" aria-labelledby="paper-title" oncancel={(event) => { event.preventDefault(); closeEditor(); }}>
        <div class="paper-header"><span class="paper-kicker">LEXTERBEAT <span>·</span> TO DO LIST</span><button type="button" class="paper-close" aria-label="Close editor" onclick={closeEditor}>×</button></div>
        <h2 id="paper-title">{editingTaskId ? 'Edit task' : 'Create a task'}</h2>
        <form class="paper-form" onsubmit={saveNote}>
          <label class="paper-label" for="paper-task-title">WHAT DO YOU NEED TO DO?</label>
          <input id="paper-task-title" class="paper-title-input" bind:this={titleInput} bind:value={modalTitle} maxlength="160" placeholder="Write a task title..." required />

          <label class="paper-label" for="paper-task-notes">TASK DETAILS</label>
          <textarea id="paper-task-notes" class="paper-notes-input" bind:value={modalNotes} rows="5" placeholder="Add any notes or details here..."></textarea>

          <div class="paper-field-heading"><span class="paper-label">DATE & TIME</span><span class="optional-label">OPTIONAL</span></div>
          <div class="date-time-control">
            <button class="date-trigger" type="button" aria-expanded={datePickerOpen} onclick={() => datePickerOpen = !datePickerOpen}>
              <span class="date-trigger-icon">▦</span>
              <span class:date-placeholder={!modalDue}>{modalDue ? formatDue(modalDue) : 'Choose a date and time'}</span>
              <span class="date-trigger-chevron">{datePickerOpen ? '⌃' : '⌄'}</span>
            </button>
            {#if datePickerOpen}
              <div class="calendar-popover" aria-label="Choose due date and time">
                <div class="calendar-header">
                  <button type="button" aria-label="Previous month" onclick={() => setCalendarMonth(-1)}>‹</button>
                  <strong>{calendarMonthLabel}</strong>
                  <button type="button" aria-label="Next month" onclick={() => setCalendarMonth(1)}>›</button>
                </div>
                <div class="picker-layout">
                  <div class="calendar-section">
                    <div class="weekdays">{#each weekdays as day}<span>{day}</span>{/each}</div>
                    <div class="calendar-days">
                      {#each calendarDays as day (day.value)}
                        <button type="button" class:outside-month={!day.inMonth} class:today={day.today} class:selected-day={day.selected} aria-label={new Intl.DateTimeFormat('en', { dateStyle: 'full' }).format(new Date(`${day.value}T12:00`))} aria-pressed={day.selected} onclick={() => setPickerDate(day.value)}>{day.day}</button>
                      {/each}
                    </div>
                    <div class="calendar-quick-actions"><button type="button" onclick={() => setQuickDate(0)}>Today</button><button type="button" onclick={() => setQuickDate(1)}>Tomorrow</button><button type="button" onclick={clearPickerDate}>Clear</button></div>
                  </div>
                  <div class="time-section">
                    <span class="picker-section-label">TIME</span>
                    <label><span>Hour</span><select aria-label="Hour" value={timeHour} onchange={(event) => updatePickerTime('hour', event.currentTarget.value)}>{#each hours as hour}<option value={hour}>{hour}</option>{/each}</select></label>
                    <label><span>Minute</span><select aria-label="Minute" value={timeMinute} onchange={(event) => updatePickerTime('minute', event.currentTarget.value)}>{#each minutes as minute}<option value={minute}>{minute}</option>{/each}</select></label>
                    <label><span>Period</span><select aria-label="AM or PM" value={timePeriod} onchange={(event) => updatePickerTime('period', event.currentTarget.value)}><option value="AM">AM</option><option value="PM">PM</option></select></label>
                  </div>
                </div>
              </div>
            {/if}
          </div>

          <div class="editor-row"><label><span class="paper-label">STATUS</span><select bind:value={modalStatus}>{#each columns as column}<option value={column.id}>{column.name}</option>{/each}</select></label><label><span class="paper-label">PRIORITY</span><select bind:value={modalPriority}><option>Low</option><option>Medium</option><option>High</option></select></label></div>

          <fieldset class="color-fieldset">
            <legend class="paper-label">PAPER COLOR</legend>
            <div class="color-options">
              {#each noteColors as color}
                <button type="button" class="color-swatch swatch-{color}" class:chosen={modalColor === color} aria-label={`Choose ${color} paper`} aria-pressed={modalColor === color} onclick={() => modalColor = color}></button>
              {/each}
            </div>
          </fieldset>

          <div class="paper-actions"><button type="button" class="cancel-note" onclick={closeEditor}>Cancel</button><button class="save-note" type="submit">{editingTaskId ? 'Save changes' : 'Add task'} <span>↗</span></button></div>
        </form>
      </dialog>
    </div>
  {/if}
  {#if reminderQueue.length}
    {@const reminder = reminderQueue[0]}
    <div class="due-reminder-overlay">
      <dialog open class="due-reminder-card" aria-modal="true" aria-labelledby="due-reminder-title" aria-describedby="due-reminder-details">
        <div class="reminder-card-top">
          <span class="reminder-brand"><span class="reminder-brand-mark">L</span> LEXTERBEAT REMINDER</span>
          <button class="reminder-close" type="button" aria-label="Dismiss reminder" onclick={dismissReminder}>×</button>
        </div>
        <div class="reminder-clock-mark" aria-hidden="true"><span>◷</span></div>
        <span class="due-now-label"><span></span> DUE NOW</span>
        <h2 id="due-reminder-title">Time for this task</h2>
        <p class="reminder-intro">You planned a moment for:</p>
        <div class="reminder-task-panel">
          <strong>{reminder.title}</strong>
          {#if reminder.notes}<p id="due-reminder-details">{reminder.notes}</p>{:else}<p id="due-reminder-details">Take a breath and make a start when you're ready.</p>{/if}
          {#if reminder.dueAt}<span class="reminder-due-time">SCHEDULED FOR · {formatDue(reminder.dueAt)}</span>{/if}
        </div>
        <div class="reminder-actions">
          <button class="reminder-complete" type="button" onclick={completeReminder}><span>✓</span> Mark as complete</button>
          <button class="reminder-snooze" type="button" onclick={snoozeReminder}>Remind me in 5 minutes</button>
        </div>
        <button class="reminder-dismiss" type="button" onclick={dismissReminder}>Dismiss reminder</button>
        {#if reminderQueue.length > 1}<span class="reminder-queue-count">{reminderQueue.length - 1} more due {reminderQueue.length === 2 ? 'task' : 'tasks'}</span>{/if}
      </dialog>
    </div>
  {/if}
</div>
