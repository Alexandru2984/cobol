(() => {
  'use strict';
  const root = document.documentElement;
  const themeButtons = document.querySelectorAll('[data-theme-toggle]');
  const applyTheme = (theme) => {
    root.dataset.theme = theme;
    themeButtons.forEach(button => {
      button.setAttribute('aria-pressed', String(theme === 'dark'));
      button.setAttribute('aria-label', theme === 'dark' ? 'Activeaza tema luminoasa' : 'Activeaza tema intunecata');
    });
  };
  try {
    const saved = localStorage.getItem('ledger-theme');
    applyTheme(saved === 'light' || saved === 'dark' ? saved : (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));
  } catch { applyTheme(matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'); }
  themeButtons.forEach(button => button.addEventListener('click', () => {
    const next = root.dataset.theme === 'dark' ? 'light' : 'dark';
    applyTheme(next);
    try { localStorage.setItem('ledger-theme', next); } catch { /* Storage may be disabled. */ }
  }));
  const params = new URLSearchParams(location.search);
  const view = params.get('view') || 'LEDGER';
  document.querySelector(`[data-nav="${['LEDGER', 'REPORT', 'BUDGET', 'AUDIT'].includes(view) ? view : 'LEDGER'}"]`)?.setAttribute('aria-current', 'page');
  const dateValue = date => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  document.querySelectorAll('[data-range]').forEach(button => button.addEventListener('click', () => {
    const today = new Date();
    let start = new Date(today.getFullYear(), today.getMonth(), 1);
    let end = today;
    if (button.dataset.range === 'previous') {
      start = new Date(today.getFullYear(), today.getMonth() - 1, 1);
      end = new Date(today.getFullYear(), today.getMonth(), 0);
    } else if (button.dataset.range === 'year') {
      start = new Date(today.getFullYear(), 0, 1);
    }
    document.querySelector('#filter-from').value = dateValue(start);
    document.querySelector('#filter-to').value = dateValue(end);
    document.querySelector('#filter-form').requestSubmit();
  }));
  document.querySelectorAll('[data-month-step]').forEach(button => button.addEventListener('click', () => {
    const input = document.querySelector('#budget-month');
    if (!input.value || !input.checkValidity()) { input.reportValidity(); return; }
    const selected = new Date(`${input.value}-01T12:00:00Z`);
    selected.setUTCMonth(selected.getUTCMonth() + Number(button.dataset.monthStep));
    if (selected.getUTCFullYear() < 1 || selected.getUTCFullYear() > 9999) return;
    input.value = selected.toISOString().slice(0, 7);
    document.querySelector('#budget-month-form').requestSubmit();
  }));
  const deleteDialog = document.querySelector('#delete-dialog');
  let pendingDelete;
  document.querySelectorAll('[data-delete]').forEach(form => form.addEventListener('submit', event => {
    if (form.dataset.confirmed === 'true') return;
    event.preventDefault();
    if (!deleteDialog?.showModal) {
      if (confirm('Stergi aceasta tranzactie?')) { form.dataset.confirmed = 'true'; form.requestSubmit(); }
      return;
    }
    const isBudget = form.dataset.delete === 'budget';
    deleteDialog.querySelector('h2').textContent = isBudget ? 'Elimini limita de buget?' : 'Stergi tranzactia?';
    deleteDialog.querySelector('p:not(.eyebrow)').textContent = isBudget
      ? 'Tranzactiile raman in registru. Poti seta o limita noua oricand.'
      : 'Tranzactia va fi eliminata din registru. Actiunea ramane in jurnalul de audit.';
    deleteDialog.querySelector('[value=confirm]').textContent = isBudget ? 'Elimina limita' : 'Sterge tranzactia';
    pendingDelete = form;
    deleteDialog.returnValue = '';
    deleteDialog.showModal();
  }));
  deleteDialog?.addEventListener('close', () => {
    if (deleteDialog.returnValue === 'confirm' && pendingDelete) {
      pendingDelete.dataset.confirmed = 'true';
      pendingDelete.requestSubmit();
    }
    pendingDelete = null;
  });
  const help = document.querySelector('#help-dialog');
  document.querySelectorAll('[data-help]').forEach(button => button.addEventListener('click', () => help?.showModal()));
  document.querySelectorAll('[data-print]').forEach(button => button.addEventListener('click', () => window.print()));
  document.addEventListener('keydown', event => {
    if (event.altKey || event.ctrlKey || event.metaKey || event.target.matches('input, select, textarea, [contenteditable="true"]') || document.querySelector('dialog[open]')) return;
    if (event.key === '/' && document.querySelector('#search')) {
      event.preventDefault();
      document.querySelector('#search').focus();
    } else if (event.key.toLowerCase() === 'n' && document.querySelector('#entry-desc')) {
      event.preventDefault();
      document.querySelector('#entry-desc').focus();
    } else if (event.key === '?' && help) {
      event.preventDefault();
      help.showModal();
    }
  });
  // Clear transient feedback from the URL so refreshes remain simple GETs.
  if (params.has('notice')) {
    params.delete('notice');
    history.replaceState(null, '', location.pathname + (params.size ? '?' + params : '') + location.hash);
  }
})();
